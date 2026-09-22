#include "sberti.h"
#include "champsim.h"
#include <iostream>
#include <cmath>

using namespace std;

// =====================================================================
// CONSTRUCTOR / DESTRUCTOR
// =====================================================================

SBertiPrefetcher::SBertiPrefetcher(string type) : Prefetcher(type) {
    current_cycle = 0;
    recent_head = 0;
    current_pref_addr = nullptr;
    memset(recent_prefetches, 0, sizeof(recent_prefetches));
    l1d_init_current_pages_table();
    l1d_init_prev_requests_table();
    l1d_init_prev_prefetches_table();
    l1d_init_record_pages_table();
    l1d_init_ip_table();
    stride_initialize();
    rl_init();
    cout << "SBerti (Smart Stride + Berti) Prefetcher Initialized" << endl;
    cout << "SBerti Layer3 internal RL degree control: " << (rl_enabled ? "ENABLED" : "disabled") << endl;
}

SBertiPrefetcher::~SBertiPrefetcher() {
}

void SBertiPrefetcher::init_knobs() {}
void SBertiPrefetcher::init_stats() {}

void SBertiPrefetcher::print_config() {
    cout << "sberti prefetcher" << endl;
}

void SBertiPrefetcher::dump_stats() {
    cout << "sberti_layer3_enabled " << (rl_enabled ? 1 : 0) << endl;
    cout << "sberti_fixed_cap_enabled " << (fixed_cap_enabled ? 1 : 0) << endl;
    cout << "sberti_fixed_cap " << (fixed_cap_enabled ? fixed_cap : 0) << endl;
    cout << "sberti_rl_epoch_len " << rl_epoch_len << endl;
    cout << "sberti_rl_epochs " << rl_epochs << endl;
    cout << "sberti_rl_bw_high_epochs " << rl_bw_high_epochs << endl;
    cout << "sberti_rl_final_degree " << rl_degree << endl;
    cout << "sberti_rl_last_accuracy " << rl_last_accuracy << endl;
    cout << "sberti_total_prefetch_issued " << rl_total_issued << endl;
    cout << "sberti_total_prefetch_useful " << rl_total_useful << endl;
    double ov = (rl_total_issued > 0) ? ((double)rl_total_useful / (double)rl_total_issued) : 0.0;
    cout << "sberti_overall_accuracy " << ov << endl;
    for (int d = 0; d < SB_RL_NUM_ACTIONS; d++)
        cout << "sberti_rl_degree" << (d+1) << "_epochs " << rl_degree_hist[d] << endl;
    for (int d = 0; d < 8; d++)
        cout << "sberti_natdepth" << (d+1) << " " << rl_natdepth_hist[d] << endl;
}

// =====================================================================
// DEDUP HELPERS
// =====================================================================

void SBertiPrefetcher::update_bw(uint8_t bw) {
    rl_bw_level = bw;
}

void SBertiPrefetcher::rl_init() {
    const char *env = getenv("SBERTI_RL");
    rl_enabled = (env != NULL && atoi(env) == 1);

    fixed_cap_enabled = false;
    fixed_cap = 0;

    const char *fixed_env = getenv("SBERTI_FIXED_CAP");

    if (fixed_env != NULL) {
        char *fixed_end = NULL;
        long fixed_value = strtol(fixed_env, &fixed_end, 10);

        if (fixed_env[0] == '\0'
            || fixed_end == NULL
            || *fixed_end != '\0'
            || !(fixed_value == 1
                 || fixed_value == 2
                 || fixed_value == 4
                 || fixed_value == 8)) {
            cerr << "Invalid SBERTI_FIXED_CAP="
                 << fixed_env
                 << " (allowed: 1,2,4,8)"
                 << endl;
            exit(1);
        }

        if (rl_enabled) {
            cerr << "SBERTI_FIXED_CAP cannot be combined "
                 << "with SBERTI_RL=1"
                 << endl;
            exit(1);
        }

        fixed_cap_enabled = true;
        fixed_cap = (int)fixed_value;
    }

    const char *ep = getenv("SBERTI_EPOCH");
    rl_epoch_len = (ep != NULL && atoi(ep) > 0)
                 ? (uint64_t)atoi(ep) : (uint64_t)SB_RL_EPOCH_ACCESSES;
    for (int s = 0; s < SB_RL_NUM_STATES; s++)
        for (int a = 0; a < SB_RL_NUM_ACTIONS; a++)
            rl_qtable[s][a] = 0.0;
    rl_state = 0;
    rl_action = 1;
    rl_degree = 8;
    rl_access_counter = 0;
    rl_pref_issued = 0;
    rl_pref_useful = 0;
    rl_prev_accuracy = 0.0;
    rl_last_accuracy = 0.0;
    rl_epochs = 0;
    rl_bw_level = 0;
    rl_bw_high_epochs = 0;
    rl_total_issued = 0;
    rl_total_useful = 0;
    for (int d = 0; d < SB_RL_NUM_ACTIONS; d++) rl_degree_hist[d] = 0;
    for (int d = 0; d < 8; d++) rl_natdepth_hist[d] = 0;
    for (int i = 0; i < SB_RL_TRACK_ENTRIES; i++) rl_track_table[i] = 0;
}

int SBertiPrefetcher::rl_get_state(double accuracy) {
    int acc_bucket;
    if (accuracy < 0.25)      acc_bucket = 0;
    else if (accuracy < 0.50) acc_bucket = 1;
    else if (accuracy < 0.75) acc_bucket = 2;
    else                      acc_bucket = 3;
    int deg_bucket = (rl_degree > 2) ? 1 : 0;
    return acc_bucket * 2 + deg_bucket;
}

int SBertiPrefetcher::rl_select_action(int state) {
    if (SB_RL_EPSILON_PCT > 0 && (rand() % 100) < SB_RL_EPSILON_PCT)
        return rand() % SB_RL_NUM_ACTIONS;
    int best = 0;
    double best_q = rl_qtable[state][0];
    for (int a = 1; a < SB_RL_NUM_ACTIONS; a++) {
        if (rl_qtable[state][a] > best_q) { best_q = rl_qtable[state][a]; best = a; }
    }
    return best;
}

void SBertiPrefetcher::rl_sarsa_update(int s, int a, double reward, int s_next, int a_next) {
    double target = reward + SB_RL_GAMMA * rl_qtable[s_next][a_next];
    rl_qtable[s][a] += SB_RL_ALPHA * (target - rl_qtable[s][a]);
}

void SBertiPrefetcher::rl_track_prefetch(uint64_t addr) {
    uint64_t line = addr >> LOG2_BLOCK_SIZE_SB;
    rl_track_table[line % SB_RL_TRACK_ENTRIES] = line;
    rl_pref_issued++;
    rl_total_issued++;
}

void SBertiPrefetcher::rl_check_demand(uint64_t addr) {
    uint64_t line = addr >> LOG2_BLOCK_SIZE_SB;
    uint64_t idx = line % SB_RL_TRACK_ENTRIES;
    if (line != 0 && rl_track_table[idx] == line) {
        rl_pref_useful++;
        rl_total_useful++;
        rl_track_table[idx] = 0;
    }
}

int SBertiPrefetcher::rl_cap_degree(int natural_degree) {
    if (fixed_cap_enabled)
        return (natural_degree > fixed_cap) ? fixed_cap : natural_degree;

    if (!rl_enabled) return natural_degree;

    return (natural_degree > rl_degree) ? rl_degree : natural_degree;
}

void SBertiPrefetcher::rl_epoch_end() {
    double accuracy = (rl_pref_issued > 0)
                    ? ((double)rl_pref_useful / (double)rl_pref_issued) : 0.0;
    rl_last_accuracy = accuracy;
    double useful_rate = (double)rl_pref_useful / (double)rl_epoch_len;
    double reward = (useful_rate - rl_prev_accuracy) * 100.0;
    if (rl_bw_level >= 3) {
        reward -= 5.0 * (double)rl_degree;
        rl_bw_high_epochs++;
    }
    int next_state  = rl_get_state(accuracy);
    int next_action = rl_select_action(next_state);
    rl_sarsa_update(rl_state, rl_action, reward, next_state, next_action);
    rl_state  = next_state;
    rl_action = next_action;
    static const int deg_map[4] = {1, 2, 4, 8};
    rl_degree = deg_map[next_action];
    rl_degree_hist[next_action]++;
    rl_prev_accuracy = useful_rate;
    rl_pref_issued = 0;
    rl_pref_useful = 0;
    rl_epochs++;
}

void SBertiPrefetcher::addRecentPrefetch(uint64_t addr) {
    recent_prefetches[recent_head] = addr;
    recent_head = (recent_head + 1) % RECENT_WINDOW_SIZE;
}

bool SBertiPrefetcher::hasRecentlyPrefetched(uint64_t addr) {
    for (int i = 0; i < RECENT_WINDOW_SIZE; i++) {
        if (recent_prefetches[i] == addr) return true;
    }
    return false;
}

// Issue prefetch: replaces intern_->prefetch_line()
// Just pushes to the pref_addr vector that Athena's l2c_prefetcher_operate reads
bool SBertiPrefetcher::issue_prefetch(uint64_t addr, uint64_t ip) {
    if (hasRecentlyPrefetched(addr)) return false;
    if (current_pref_addr == nullptr) return false;
    current_pref_addr->push_back(addr);
    addRecentPrefetch(addr);
    rl_track_prefetch(addr);
    return true;
}

// =====================================================================
// BERTI HELPER IMPLEMENTATIONS
// =====================================================================

uint64_t SBertiPrefetcher::l1d_get_latency(uint64_t cycle, uint64_t cycle_prev) {
    return cycle - cycle_prev;
}

int SBertiPrefetcher::l1d_calculate_stride(uint64_t prev_offset, uint64_t current_offset) {
    int stride;
    if (current_offset > prev_offset) {
        stride = (int)(current_offset - prev_offset);
    } else {
        stride = (int)(prev_offset - current_offset);
        stride *= -1;
    }
    return stride;
}

// --- CURRENT PAGES TABLE ---

void SBertiPrefetcher::l1d_init_current_pages_table() {
    memset(l1d_current_pages_table, 0, sizeof(l1d_current_pages_table));
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_ENTRIES; i++) {
        l1d_current_pages_table[i].page_addr = 0;
        l1d_current_pages_table[i].ip = 0;
        l1d_current_pages_table[i].u_vector = 0;
        l1d_current_pages_table[i].last_burst = 0;
        l1d_current_pages_table[i].lru = i;
    }
}

uint64_t SBertiPrefetcher::l1d_get_current_pages_entry(uint64_t page_addr) {
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_ENTRIES; i++) {
        if (l1d_current_pages_table[i].page_addr == page_addr)
            return i;
    }
    return L1D_CURRENT_PAGES_TABLE_ENTRIES;
}

void SBertiPrefetcher::l1d_update_lru_current_pages_table(uint64_t index) {
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_ENTRIES; i++) {
        if (l1d_current_pages_table[i].lru < l1d_current_pages_table[index].lru) {
            l1d_current_pages_table[i].lru++;
        }
    }
    l1d_current_pages_table[index].lru = 0;
}

uint64_t SBertiPrefetcher::l1d_get_lru_current_pages_entry() {
    uint64_t lru = L1D_CURRENT_PAGES_TABLE_ENTRIES;
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_ENTRIES; i++) {
        l1d_current_pages_table[i].lru++;
        if (l1d_current_pages_table[i].lru == L1D_CURRENT_PAGES_TABLE_ENTRIES) {
            l1d_current_pages_table[i].lru = 0;
            lru = i;
        }
    }
    assert(lru != L1D_CURRENT_PAGES_TABLE_ENTRIES);
    return lru;
}

int SBertiPrefetcher::l1d_get_berti_current_pages_table(uint64_t index, uint64_t &ctr) {
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    uint64_t max_score = 0;
    uint64_t b = 0;
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_NUM_BERTI; i++) {
        uint64_t score = l1d_current_pages_table[index].berti_ctr[i];
        if (score > max_score) {
            b = l1d_current_pages_table[index].berti[i];
            max_score = score;
            ctr = l1d_current_pages_table[index].berti_ctr[i];
        }
    }
    return (int)b;
}

void SBertiPrefetcher::l1d_add_current_pages_table(uint64_t index, uint64_t page_addr, uint64_t ip, uint64_t offset) {
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    l1d_current_pages_table[index].page_addr = page_addr;
    l1d_current_pages_table[index].ip = ip;
    l1d_current_pages_table[index].u_vector = (uint64_t)1 << offset;
    l1d_current_pages_table[index].first_offset = offset;
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_NUM_BERTI; i++) {
        l1d_current_pages_table[index].berti_ctr[i] = 0;
    }
    l1d_current_pages_table[index].last_burst = 0;
}

uint64_t SBertiPrefetcher::l1d_update_demand_current_pages_table(uint64_t index, uint64_t offset) {
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    l1d_current_pages_table[index].u_vector |= (uint64_t)1 << offset;
    l1d_update_lru_current_pages_table(index);
    return l1d_current_pages_table[index].ip;
}

void SBertiPrefetcher::l1d_add_berti_current_pages_table(uint64_t index, int b) {
    assert(b != 0);
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_NUM_BERTI; i++) {
        if (l1d_current_pages_table[index].berti_ctr[i] == 0) {
            l1d_current_pages_table[index].berti[i] = b;
            l1d_current_pages_table[index].berti_ctr[i] = 1;
            break;
        } else if (l1d_current_pages_table[index].berti[i] == b) {
            l1d_current_pages_table[index].berti_ctr[i]++;
            break;
        }
    }
    l1d_update_lru_current_pages_table(index);
}

bool SBertiPrefetcher::l1d_requested_offset_current_pages_table(uint64_t index, uint64_t offset) {
    assert(index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
    return l1d_current_pages_table[index].u_vector & ((uint64_t)1 << offset);
}

void SBertiPrefetcher::l1d_remove_current_table_entry(uint64_t index) {
    l1d_current_pages_table[index].page_addr = 0;
    l1d_current_pages_table[index].u_vector = 0;
    l1d_current_pages_table[index].berti[0] = 0;
}

// --- PREVIOUS REQUESTS TABLE ---

void SBertiPrefetcher::l1d_init_prev_requests_table() {
    memset(l1d_prev_requests_table, 0, sizeof(l1d_prev_requests_table));
    l1d_prev_requests_table_head = 0;
    for (int i = 0; i < L1D_PREV_REQUESTS_TABLE_ENTRIES; i++) {
        l1d_prev_requests_table[i].page_addr_pointer = L1D_PREV_REQUESTS_TABLE_NULL_POINTER;
    }
}

uint64_t SBertiPrefetcher::l1d_find_prev_request_entry(uint64_t pointer, uint64_t offset) {
    for (int i = 0; i < L1D_PREV_REQUESTS_TABLE_ENTRIES; i++) {
        if (l1d_prev_requests_table[i].page_addr_pointer == pointer &&
            l1d_prev_requests_table[i].offset == offset)
            return i;
    }
    return L1D_PREV_REQUESTS_TABLE_ENTRIES;
}

void SBertiPrefetcher::l1d_add_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle) {
    if (l1d_find_prev_request_entry(pointer, offset) != L1D_PREV_REQUESTS_TABLE_ENTRIES)
        return;
    l1d_prev_requests_table[l1d_prev_requests_table_head].page_addr_pointer = pointer;
    l1d_prev_requests_table[l1d_prev_requests_table_head].offset = offset;
    l1d_prev_requests_table[l1d_prev_requests_table_head].time = cycle & L1D_TIME_MASK;
    l1d_prev_requests_table_head = (l1d_prev_requests_table_head + 1) & L1D_PREV_REQUESTS_TABLE_MASK;
}

void SBertiPrefetcher::l1d_reset_pointer_prev_requests(uint64_t pointer) {
    for (int i = 0; i < L1D_PREV_REQUESTS_TABLE_ENTRIES; i++) {
        if (l1d_prev_requests_table[i].page_addr_pointer == pointer) {
            l1d_prev_requests_table[i].page_addr_pointer = L1D_PREV_REQUESTS_TABLE_NULL_POINTER;
        }
    }
}

uint64_t SBertiPrefetcher::l1d_get_latency_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle) {
    uint64_t index = l1d_find_prev_request_entry(pointer, offset);
    if (index == L1D_PREV_REQUESTS_TABLE_ENTRIES) return 0;
    return l1d_get_latency(cycle, l1d_prev_requests_table[index].time);
}

void SBertiPrefetcher::l1d_get_berti_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle, int *b) {
    int my_pos = 0;
    uint64_t extra_time = 0;
    uint64_t last_time = l1d_prev_requests_table[(l1d_prev_requests_table_head + L1D_PREV_REQUESTS_TABLE_MASK) & L1D_PREV_REQUESTS_TABLE_MASK].time;
    for (uint64_t i = (l1d_prev_requests_table_head + L1D_PREV_REQUESTS_TABLE_MASK) & L1D_PREV_REQUESTS_TABLE_MASK;
         i != l1d_prev_requests_table_head;
         i = (i + L1D_PREV_REQUESTS_TABLE_MASK) & L1D_PREV_REQUESTS_TABLE_MASK) {
        if (last_time < l1d_prev_requests_table[i].time) {
            extra_time = L1D_TIME_OVERFLOW;
        }
        last_time = l1d_prev_requests_table[i].time;
        if (l1d_prev_requests_table[i].page_addr_pointer == pointer) {
            if (l1d_prev_requests_table[i].time <= (cycle & L1D_TIME_MASK) + extra_time) {
                b[my_pos] = l1d_calculate_stride(l1d_prev_requests_table[i].offset, offset);
                my_pos++;
                if (my_pos == L1D_CURRENT_PAGES_TABLE_NUM_BERTI_PER_ACCESS)
                    return;
            }
        }
    }
    b[my_pos] = 0;
}

// --- PREVIOUS PREFETCHES TABLE ---

void SBertiPrefetcher::l1d_init_prev_prefetches_table() {
    memset(l1d_prev_prefetches_table, 0, sizeof(l1d_prev_prefetches_table));
    l1d_prev_prefetches_table_head = 0;
    for (int i = 0; i < L1D_PREV_PREFETCHES_TABLE_ENTRIES; i++) {
        l1d_prev_prefetches_table[i].page_addr_pointer = L1D_PREV_PREFETCHES_TABLE_NULL_POINTER;
    }
}

uint64_t SBertiPrefetcher::l1d_find_prev_prefetch_entry(uint64_t pointer, uint64_t offset) {
    for (int i = 0; i < L1D_PREV_PREFETCHES_TABLE_ENTRIES; i++) {
        if (l1d_prev_prefetches_table[i].page_addr_pointer == pointer &&
            l1d_prev_prefetches_table[i].offset == offset)
            return i;
    }
    return L1D_PREV_PREFETCHES_TABLE_ENTRIES;
}

void SBertiPrefetcher::l1d_add_prev_prefetches_table(uint64_t pointer, uint64_t offset, uint64_t cycle) {
    if (l1d_find_prev_prefetch_entry(pointer, offset) != L1D_PREV_PREFETCHES_TABLE_ENTRIES)
        return;
    l1d_prev_prefetches_table[l1d_prev_prefetches_table_head].page_addr_pointer = pointer;
    l1d_prev_prefetches_table[l1d_prev_prefetches_table_head].offset = offset;
    l1d_prev_prefetches_table[l1d_prev_prefetches_table_head].time_lat = cycle & L1D_TIME_MASK;
    l1d_prev_prefetches_table[l1d_prev_prefetches_table_head].completed = false;
    l1d_prev_prefetches_table_head = (l1d_prev_prefetches_table_head + 1) & L1D_PREV_PREFETCHES_TABLE_MASK;
}

void SBertiPrefetcher::l1d_reset_pointer_prev_prefetches(uint64_t pointer) {
    for (int i = 0; i < L1D_PREV_PREFETCHES_TABLE_ENTRIES; i++) {
        if (l1d_prev_prefetches_table[i].page_addr_pointer == pointer) {
            l1d_prev_prefetches_table[i].page_addr_pointer = L1D_PREV_PREFETCHES_TABLE_NULL_POINTER;
        }
    }
}

void SBertiPrefetcher::l1d_reset_entry_prev_prefetches_table(uint64_t pointer, uint64_t offset) {
    uint64_t index = l1d_find_prev_prefetch_entry(pointer, offset);
    if (index != L1D_PREV_PREFETCHES_TABLE_ENTRIES) {
        l1d_prev_prefetches_table[index].page_addr_pointer = L1D_PREV_PREFETCHES_TABLE_NULL_POINTER;
    }
}

uint64_t SBertiPrefetcher::l1d_get_and_set_latency_prev_prefetches_table(uint64_t pointer, uint64_t offset, uint64_t cycle) {
    uint64_t index = l1d_find_prev_prefetch_entry(pointer, offset);
    if (index == L1D_PREV_PREFETCHES_TABLE_ENTRIES) return 0;
    if (!l1d_prev_prefetches_table[index].completed) {
        l1d_prev_prefetches_table[index].time_lat = l1d_get_latency(cycle, l1d_prev_prefetches_table[index].time_lat);
        l1d_prev_prefetches_table[index].completed = true;
    }
    return l1d_prev_prefetches_table[index].time_lat;
}

uint64_t SBertiPrefetcher::l1d_get_latency_prev_prefetches_table(uint64_t pointer, uint64_t offset) {
    uint64_t index = l1d_find_prev_prefetch_entry(pointer, offset);
    if (index == L1D_PREV_PREFETCHES_TABLE_ENTRIES) return 0;
    if (!l1d_prev_prefetches_table[index].completed) return 0;
    return l1d_prev_prefetches_table[index].time_lat;
}

// --- RECORD PAGES TABLE ---

void SBertiPrefetcher::l1d_init_record_pages_table() {
    memset(l1d_record_pages_table, 0, sizeof(l1d_record_pages_table));
    for (int i = 0; i < L1D_RECORD_PAGES_TABLE_ENTRIES; i++) {
        l1d_record_pages_table[i].page_addr = 0;
        l1d_record_pages_table[i].u_vector = 0;
        l1d_record_pages_table[i].lru = i;
    }
}

uint64_t SBertiPrefetcher::l1d_get_lru_record_pages_entry() {
    uint64_t lru = L1D_RECORD_PAGES_TABLE_ENTRIES;
    for (int i = 0; i < L1D_RECORD_PAGES_TABLE_ENTRIES; i++) {
        l1d_record_pages_table[i].lru++;
        if (l1d_record_pages_table[i].lru == L1D_RECORD_PAGES_TABLE_ENTRIES) {
            l1d_record_pages_table[i].lru = 0;
            lru = i;
        }
    }
    assert(lru != L1D_RECORD_PAGES_TABLE_ENTRIES);
    return lru;
}

void SBertiPrefetcher::l1d_update_lru_record_pages_table(uint64_t index) {
    assert(index < L1D_RECORD_PAGES_TABLE_ENTRIES);
    for (int i = 0; i < L1D_RECORD_PAGES_TABLE_ENTRIES; i++) {
        if (l1d_record_pages_table[i].lru < l1d_record_pages_table[index].lru) {
            l1d_record_pages_table[i].lru++;
        }
    }
    l1d_record_pages_table[index].lru = 0;
}

void SBertiPrefetcher::l1d_add_record_pages_table(uint64_t index, uint64_t page_addr, uint64_t vector, uint64_t first_offset, int b) {
    assert(index < L1D_RECORD_PAGES_TABLE_ENTRIES);
    l1d_record_pages_table[index].page_addr = page_addr & L1D_TRUNCATED_PAGE_ADDR_MASK;
    l1d_record_pages_table[index].u_vector = vector;
    l1d_record_pages_table[index].first_offset = first_offset;
    l1d_record_pages_table[index].berti = b;
    l1d_update_lru_record_pages_table(index);
}

uint64_t SBertiPrefetcher::l1d_get_entry_record_pages_table(uint64_t page_addr, uint64_t first_offset) {
    uint64_t trunc = page_addr & L1D_TRUNCATED_PAGE_ADDR_MASK;
    for (int i = 0; i < L1D_RECORD_PAGES_TABLE_ENTRIES; i++) {
        if (l1d_record_pages_table[i].page_addr == trunc &&
            l1d_record_pages_table[i].first_offset == first_offset)
            return i;
    }
    return L1D_RECORD_PAGES_TABLE_ENTRIES;
}

uint64_t SBertiPrefetcher::l1d_get_entry_record_pages_table(uint64_t page_addr) {
    uint64_t trunc = page_addr & L1D_TRUNCATED_PAGE_ADDR_MASK;
    for (int i = 0; i < L1D_RECORD_PAGES_TABLE_ENTRIES; i++) {
        if (l1d_record_pages_table[i].page_addr == trunc)
            return i;
    }
    return L1D_RECORD_PAGES_TABLE_ENTRIES;
}

void SBertiPrefetcher::l1d_copy_entries_record_pages_table(uint64_t index_from, uint64_t index_to) {
    assert(index_from < L1D_RECORD_PAGES_TABLE_ENTRIES);
    assert(index_to < L1D_RECORD_PAGES_TABLE_ENTRIES);
    l1d_record_pages_table[index_to].page_addr    = l1d_record_pages_table[index_from].page_addr;
    l1d_record_pages_table[index_to].u_vector     = l1d_record_pages_table[index_from].u_vector;
    l1d_record_pages_table[index_to].first_offset = l1d_record_pages_table[index_from].first_offset;
    l1d_record_pages_table[index_to].berti        = l1d_record_pages_table[index_from].berti;
    l1d_update_lru_record_pages_table(index_to);
}

// --- IP TABLE ---

void SBertiPrefetcher::l1d_init_ip_table() {
    for (int i = 0; i < L1D_IP_TABLE_ENTRIES; i++) {
        l1d_ip_table[i] = L1D_IP_TABLE_NULL_POINTER;
    }
}

void SBertiPrefetcher::l1d_record_current_page(uint64_t index_current) {
    if (l1d_current_pages_table[index_current].u_vector) {
        uint64_t record_index = l1d_ip_table[l1d_current_pages_table[index_current].ip & L1D_IP_TABLE_INDEX_MASK];
        assert(record_index < L1D_RECORD_PAGES_TABLE_ENTRIES);
        uint64_t confidence;
        l1d_add_record_pages_table(record_index,
            l1d_current_pages_table[index_current].page_addr,
            l1d_current_pages_table[index_current].u_vector,
            l1d_current_pages_table[index_current].first_offset,
            l1d_get_berti_current_pages_table(index_current, confidence));
    }
}

// =====================================================================
// SMART STRIDE IMPLEMENTATION
// =====================================================================

void SBertiPrefetcher::stride_initialize() {
    memset(stride_table, 0, sizeof(stride_table));
    for (int i = 0; i < STRIDE_SETS; i++)
        for (int j = 0; j < STRIDE_WAYS; j++)
            stride_table[i][j].valid = false;
}

uint64_t SBertiPrefetcher::strideHashPc(uint64_t pc) {
    uint64_t pc_high = (pc >> 10) ^ (pc >> 20);
    return (pc_high << 6) | (pc & 0x3F);
}

void SBertiPrefetcher::stride_trigger_prefetch(uint64_t addr, uint64_t ip) {
    uint64_t hash = strideHashPc(ip);
    int set_idx = hash % STRIDE_SETS;
    uint64_t tag = hash / STRIDE_SETS;

    int way_idx = -1;
    for (int i = 0; i < STRIDE_WAYS; i++) {
        if (stride_table[set_idx][i].valid && stride_table[set_idx][i].tag == tag) {
            way_idx = i;
            break;
        }
    }

    if (way_idx != -1) {
        SmartStrideEntry &entry = stride_table[set_idx][way_idx];
        if (entry.conf >= 2) {
            int eff_depth = rl_cap_degree(entry.depth);
            for (int d = 1; d <= eff_depth; d++) {
                uint64_t pf_addr = addr + (entry.stride * d);
                issue_prefetch(pf_addr, ip);
            }
        }
    }
}

void SBertiPrefetcher::stride_operate(uint64_t addr, uint64_t ip, uint8_t cache_hit, uint64_t current_cycle_arg) {
    uint64_t hash = strideHashPc(ip);
    int set_idx = hash % STRIDE_SETS;
    uint64_t tag = hash / STRIDE_SETS;

    int way_idx = -1;
    for (int i = 0; i < STRIDE_WAYS; i++) {
        if (stride_table[set_idx][i].valid && stride_table[set_idx][i].tag == tag) {
            way_idx = i;
            break;
        }
    }

    if (way_idx != -1) {
        SmartStrideEntry &entry = stride_table[set_idx][way_idx];
        entry.lru_cycle = current_cycle_arg;

        int64_t new_stride = (int64_t)addr - (int64_t)entry.last_addr;
        bool stride_match = false;

        int64_t bs = (int64_t)(1 << LOG2_BLOCK_SIZE_SB);
        if (new_stride != 0 && llabs(new_stride) < bs) {
            entry.last_addr = addr;
            return;
        }

        if (new_stride == entry.stride) stride_match = true;
        else if (entry.stride != 0 && llabs(new_stride) % llabs(entry.stride) == 0) stride_match = true;

        if (stride_match) {
            if (entry.conf < STRIDE_MAX_CONF) entry.conf++;

            bool is_late = (cache_hit == 0) && hasRecentlyPrefetched(addr);
            bool is_timely = (cache_hit == 1);

            if (is_timely) {
                if (entry.late_conf > 0) entry.late_conf--;
            } else if (is_late) {
                entry.late_conf += 3;
            }
            if (entry.late_conf > 15) entry.late_conf = 15;

            if (entry.late_conf >= 12 && entry.depth < STRIDE_MAX_DEPTH) {
                entry.depth++;
                entry.late_conf = 7;
            } else if (entry.late_conf <= 3 && entry.depth > 1) {
                entry.depth--;
                entry.late_conf = 7;
            }

            entry.last_addr = addr;
        } else {
            entry.conf--;
            entry.last_addr = addr;
            if (entry.conf <= 0) {
                entry.stride = new_stride;
                entry.depth = 1;
                entry.conf = 0;
                entry.late_conf = 7;
            }
        }

        if (entry.conf >= 2) {
            if (entry.depth >= 1 && entry.depth <= 8) rl_natdepth_hist[entry.depth - 1]++;
            int eff_depth = rl_cap_degree(entry.depth);
            int start_depth = (cache_hit == 0) ? (eff_depth > 4 ? eff_depth - 4 : 1) : 1;
            for (int d = start_depth; d <= eff_depth; d++) {
                uint64_t pf_addr = addr + (entry.stride * d);
                issue_prefetch(pf_addr, ip);
            }
        }

    } else {
        int victim = 0;
        uint64_t min_lru = UINT64_MAX;
        for (int i = 0; i < STRIDE_WAYS; i++) {
            if (!stride_table[set_idx][i].valid) { victim = i; min_lru = 0; break; }
            if (stride_table[set_idx][i].lru_cycle < min_lru) {
                min_lru = stride_table[set_idx][i].lru_cycle;
                victim = i;
            }
        }
        SmartStrideEntry &entry = stride_table[set_idx][victim];
        entry.valid     = true;
        entry.tag       = tag;
        entry.last_addr = addr;
        entry.stride    = 0;
        entry.conf      = 0;
        entry.depth     = 1;
        entry.late_conf = 7;
        entry.lru_cycle = current_cycle_arg;
    }
}

// =====================================================================
// MAIN INTERFACE
// =====================================================================

void SBertiPrefetcher::invoke_prefetcher(uint64_t pc, uint64_t address, uint8_t cache_hit, uint8_t type, vector<uint64_t> &pref_addr) {
    // Increment our software cycle counter
    current_cycle++;
    uint64_t current_core_cycle = current_cycle;

    // Point issue_prefetch at the current pref_addr vector
    current_pref_addr = &pref_addr;

    uint64_t addr = address;
    uint64_t ip   = pc;

    rl_check_demand(addr);
    rl_access_counter++;
    if (rl_access_counter >= rl_epoch_len) {
        rl_access_counter = 0;
        rl_epoch_end();
    }

    uint64_t line_addr = addr >> LOG2_BLOCK_SIZE_SB;
    uint64_t page_addr = line_addr >> L1D_PAGE_BLOCKS_BITS;
    uint64_t offset    = line_addr & L1D_PAGE_OFFSET_MASK;

    // Update current pages table
    uint64_t index = l1d_get_current_pages_entry(page_addr);

    // BERTI LOGIC
    if (index == L1D_CURRENT_PAGES_TABLE_ENTRIES ||
        !l1d_requested_offset_current_pages_table(index, offset)) {

        if (index < L1D_CURRENT_PAGES_TABLE_ENTRIES) {
            if (l1d_requested_offset_current_pages_table(index, offset)) goto SKIP_BERTI;

            uint64_t first_ip = l1d_update_demand_current_pages_table(index, offset);

            if (cache_hit) {
                uint64_t pref_latency = l1d_get_latency_prev_prefetches_table(index, offset);
                if (pref_latency != 0) {
                    int b[L1D_CURRENT_PAGES_TABLE_NUM_BERTI_PER_ACCESS];
                    l1d_get_berti_prev_requests_table(index, offset, current_core_cycle - pref_latency, b);
                    for (int i = 0; i < L1D_CURRENT_PAGES_TABLE_NUM_BERTI_PER_ACCESS; i++) {
                        if (b[i] == 0) break;
                        l1d_add_berti_current_pages_table(index, b[i]);
                    }
                    stride_trigger_prefetch(addr, ip);
                    l1d_reset_entry_prev_prefetches_table(index, offset);
                }
            }
            if (first_ip != ip) {
                l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] = l1d_ip_table[first_ip & L1D_IP_TABLE_INDEX_MASK];
            }
        } else {
            uint64_t victim_index = l1d_get_lru_current_pages_entry();
            assert(victim_index < L1D_CURRENT_PAGES_TABLE_ENTRIES);
            l1d_reset_pointer_prev_requests(victim_index);
            l1d_reset_pointer_prev_prefetches(victim_index);
            l1d_record_current_page(victim_index);

            index = victim_index;
            l1d_add_current_pages_table(index, page_addr, ip & L1D_IP_TABLE_INDEX_MASK, offset);

            uint64_t index_record = l1d_get_entry_record_pages_table(page_addr, offset);
            if (l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] == L1D_IP_TABLE_NULL_POINTER) {
                if (index_record == L1D_RECORD_PAGES_TABLE_ENTRIES) {
                    uint64_t new_pointer = l1d_get_lru_record_pages_entry();
                    l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] = new_pointer;
                } else {
                    l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] = index_record;
                }
            } else if (l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] != index_record) {
                uint64_t new_pointer = l1d_get_lru_record_pages_entry();
                l1d_copy_entries_record_pages_table(l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK], new_pointer);
                l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK] = new_pointer;
            }
        }

        l1d_add_prev_requests_table(index, offset, current_core_cycle);

        // PREDICT
        uint64_t u_vector = 0;
        uint64_t first_offset = l1d_current_pages_table[index].first_offset;
        int b = 0;
        bool recorded = false;

        uint64_t ip_pointer  = l1d_ip_table[ip & L1D_IP_TABLE_INDEX_MASK];
        uint64_t pgo_pointer = l1d_get_entry_record_pages_table(page_addr, first_offset);
        uint64_t pg_pointer  = l1d_get_entry_record_pages_table(page_addr);
        uint64_t berti_confidence = 0;
        int current_berti = l1d_get_berti_current_pages_table(index, berti_confidence);
        uint64_t match_confidence = 0;

        if (pgo_pointer != L1D_RECORD_PAGES_TABLE_ENTRIES &&
            (l1d_record_pages_table[pgo_pointer].u_vector | l1d_current_pages_table[index].u_vector) == l1d_record_pages_table[pgo_pointer].u_vector) {
            u_vector = l1d_record_pages_table[pgo_pointer].u_vector;
            b = l1d_record_pages_table[pgo_pointer].berti;
            match_confidence = 1;
            recorded = true;
        } else if (ip_pointer < L1D_RECORD_PAGES_TABLE_ENTRIES &&
                   l1d_record_pages_table[ip_pointer].first_offset == first_offset &&
                   (l1d_record_pages_table[ip_pointer].u_vector | l1d_current_pages_table[index].u_vector) == l1d_record_pages_table[ip_pointer].u_vector) {
            u_vector = l1d_record_pages_table[ip_pointer].u_vector;
            b = l1d_record_pages_table[ip_pointer].berti;
            match_confidence = 1;
            recorded = true;
        } else if (current_berti != 0 && berti_confidence >= L1D_BERTI_CTR_MED_HIGH_CONFIDENCE) {
            u_vector = l1d_current_pages_table[index].u_vector;
            b = current_berti;
        } else if (pg_pointer != L1D_RECORD_PAGES_TABLE_ENTRIES) {
            u_vector = l1d_record_pages_table[pg_pointer].u_vector;
            b = l1d_record_pages_table[pg_pointer].berti;
            recorded = true;
        } else if (ip_pointer < L1D_RECORD_PAGES_TABLE_ENTRIES &&
                   l1d_record_pages_table[ip_pointer].u_vector) {
            u_vector = l1d_record_pages_table[ip_pointer].u_vector;
            b = l1d_record_pages_table[ip_pointer].berti;
            recorded = true;
        }

        // Burst Logic
        if (first_offset == offset || l1d_current_pages_table[index].last_burst != 0) {
            uint64_t first_burst;
            if (l1d_current_pages_table[index].last_burst != 0) {
                first_burst = l1d_current_pages_table[index].last_burst;
                l1d_current_pages_table[index].last_burst = 0;
            } else if (b >= 0) {
                first_burst = offset + 1;
            } else {
                first_burst = offset - 1;
            }
            if (recorded && match_confidence) {
                int bursts = 0;
                if (b > 0) {
                    for (uint64_t i = first_burst; i < offset + b; i++) {
                        if ((int)i >= L1D_PAGE_BLOCKS) break;
                        uint64_t pf_line_addr = (page_addr << L1D_PAGE_BLOCKS_BITS) | i;
                        uint64_t pf_addr = pf_line_addr << LOG2_BLOCK_SIZE_SB;
                        uint64_t pf_offset = pf_line_addr & L1D_PAGE_OFFSET_MASK;
                        if ((((uint64_t)1 << i) & u_vector) &&
                            !l1d_requested_offset_current_pages_table(index, pf_offset)) {
                            if (bursts < L1D_MAX_NUM_BURST_PREFETCHES) {
                                bool prefetched = issue_prefetch(pf_addr, ip);
                                if (prefetched) {
                                    l1d_add_prev_prefetches_table(index, pf_offset, current_core_cycle);
                                    bursts++;
                                }
                            } else {
                                l1d_current_pages_table[index].last_burst = i;
                                break;
                            }
                        }
                    }
                } else if (b < 0) {
                    for (int i = (int)first_burst; i > ((int)offset) + b; i--) {
                        if (i < 0) break;
                        uint64_t pf_line_addr = (page_addr << L1D_PAGE_BLOCKS_BITS) | i;
                        uint64_t pf_addr = pf_line_addr << LOG2_BLOCK_SIZE_SB;
                        uint64_t pf_offset = pf_line_addr & L1D_PAGE_OFFSET_MASK;
                        if ((((uint64_t)1 << i) & u_vector) &&
                            !l1d_requested_offset_current_pages_table(index, pf_offset)) {
                            if (bursts < L1D_MAX_NUM_BURST_PREFETCHES) {
                                bool prefetched = issue_prefetch(pf_addr, ip);
                                if (prefetched) {
                                    l1d_add_prev_prefetches_table(index, pf_offset, current_core_cycle);
                                    bursts++;
                                }
                            } else {
                                l1d_current_pages_table[index].last_burst = i;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (b != 0) {
            uint64_t pf_line_addr = line_addr + b;
            uint64_t pf_addr = pf_line_addr << LOG2_BLOCK_SIZE_SB;
            uint64_t pf_offset = pf_line_addr & L1D_PAGE_OFFSET_MASK;
            if (!l1d_requested_offset_current_pages_table(index, pf_offset) &&
                (!match_confidence || (((uint64_t)1 << pf_offset) & u_vector))) {
                bool prefetched = issue_prefetch(pf_addr, ip);
                if (prefetched) {
                    l1d_add_prev_prefetches_table(index, pf_offset, current_core_cycle);
                }
            }
        }
    }

    SKIP_BERTI:;

    // Smart Stride runs on every access
    stride_operate(addr, ip, cache_hit, current_core_cycle);

    // Clear the pointer for safety
    current_pref_addr = nullptr;
}
