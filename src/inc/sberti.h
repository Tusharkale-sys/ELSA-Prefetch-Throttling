#ifndef SBERTI_H
#define SBERTI_H

#include "prefetcher.h"
#include <cstdint>
#include <cstring>
#include <vector>
#include <cstdlib>
#include <cassert>

using namespace std;

// =====================================================================
// BERTI CONSTANTS
// =====================================================================
#define LOG2_BLOCK_SIZE_SB       6
#define LOG2_PAGE_SIZE_SB        12
#define BLOCK_SIZE_SB            64

#define L1D_PAGE_BLOCKS_BITS     6
#define L1D_PAGE_OFFSET_MASK     ((1<<L1D_PAGE_BLOCKS_BITS)-1)
#define L1D_PAGE_BLOCKS          (1<<L1D_PAGE_BLOCKS_BITS)

#define L1D_CURRENT_PAGES_TABLE_ENTRIES      16
#define L1D_CURRENT_PAGES_TABLE_NUM_BERTI    8
#define L1D_CURRENT_PAGES_TABLE_NUM_BERTI_PER_ACCESS 4
#define L1D_BERTI_CTR_MED_HIGH_CONFIDENCE   3

#define L1D_PREV_REQUESTS_TABLE_ENTRIES      64
#define L1D_PREV_REQUESTS_TABLE_MASK         (L1D_PREV_REQUESTS_TABLE_ENTRIES-1)
#define L1D_PREV_REQUESTS_TABLE_NULL_POINTER L1D_CURRENT_PAGES_TABLE_ENTRIES

#define L1D_PREV_PREFETCHES_TABLE_ENTRIES    64
#define L1D_PREV_PREFETCHES_TABLE_MASK       (L1D_PREV_PREFETCHES_TABLE_ENTRIES-1)
#define L1D_PREV_PREFETCHES_TABLE_NULL_POINTER L1D_CURRENT_PAGES_TABLE_ENTRIES

#define L1D_RECORD_PAGES_TABLE_ENTRIES       16
#define L1D_TRUNCATED_PAGE_ADDR_MASK         ((1<<12)-1)

#define L1D_IP_TABLE_ENTRIES                 512
#define L1D_IP_TABLE_INDEX_MASK              (L1D_IP_TABLE_ENTRIES-1)
#define L1D_IP_TABLE_NULL_POINTER            L1D_RECORD_PAGES_TABLE_ENTRIES

#define L1D_TIME_MASK                        ((1<<16)-1)
#define L1D_TIME_OVERFLOW                    (1<<16)
#define L1D_MAX_NUM_BURST_PREFETCHES         4

// =====================================================================
// SMART STRIDE CONSTANTS
// =====================================================================
#define STRIDE_SETS     64
#define STRIDE_WAYS     4
#define STRIDE_MAX_CONF 7
#define STRIDE_MAX_DEPTH 8
#define RECENT_WINDOW_SIZE 32

// =====================================================================
// DATA STRUCTURES
// =====================================================================

#define SB_RL_NUM_STATES      8
#define SB_RL_NUM_ACTIONS     4
#define SB_RL_EPOCH_ACCESSES  4096
#define SB_RL_TRACK_ENTRIES   64
#define SB_RL_ALPHA           0.5
#define SB_RL_GAMMA           0.6
#define SB_RL_EPSILON_PCT     0

struct CurrentPagesTableEntry {
    uint64_t page_addr;
    uint64_t ip;
    uint64_t u_vector;
    uint64_t first_offset;
    uint64_t last_burst;
    int      berti[L1D_CURRENT_PAGES_TABLE_NUM_BERTI];
    uint64_t berti_ctr[L1D_CURRENT_PAGES_TABLE_NUM_BERTI];
    uint64_t lru;
};

struct PrevRequestsTableEntry {
    uint64_t page_addr_pointer;
    uint64_t offset;
    uint64_t time;
};

struct PrevPrefetchesTableEntry {
    uint64_t page_addr_pointer;
    uint64_t offset;
    uint64_t time_lat;
    bool     completed;
};

struct RecordPagesTableEntry {
    uint64_t page_addr;
    uint64_t u_vector;
    uint64_t first_offset;
    int      berti;
    uint64_t lru;
};

struct SmartStrideEntry {
    bool     valid;
    uint64_t tag;
    uint64_t last_addr;
    int64_t  stride;
    int      conf;
    int      depth;
    int      late_conf;
    uint64_t lru_cycle;
};

// =====================================================================
// SBERTI CLASS
// =====================================================================

class SBertiPrefetcher : public Prefetcher {
private:
    // Cycle counter (replaces intern_->current_time)
    uint64_t current_cycle;

    // Recent prefetch dedup window
    uint64_t recent_prefetches[RECENT_WINDOW_SIZE];
    int      recent_head;

    // Berti tables
    CurrentPagesTableEntry   l1d_current_pages_table[L1D_CURRENT_PAGES_TABLE_ENTRIES];
    PrevRequestsTableEntry   l1d_prev_requests_table[L1D_PREV_REQUESTS_TABLE_ENTRIES];
    PrevPrefetchesTableEntry l1d_prev_prefetches_table[L1D_PREV_PREFETCHES_TABLE_ENTRIES];
    RecordPagesTableEntry    l1d_record_pages_table[L1D_RECORD_PAGES_TABLE_ENTRIES];
    uint64_t                 l1d_ip_table[L1D_IP_TABLE_ENTRIES];

    uint64_t l1d_prev_requests_table_head;
    uint64_t l1d_prev_prefetches_table_head;

    // Smart Stride table
    SmartStrideEntry stride_table[STRIDE_SETS][STRIDE_WAYS];

    // Pending prefetch list (filled during invoke, read by caller)
    vector<uint64_t> *current_pref_addr;

    bool     rl_enabled;

    // Experimental same-mechanism static control.
    // When enabled, cap the natural sBerti depth at one of
    // the exact SARSA action values {1,2,4,8}.
    bool     fixed_cap_enabled;
    int      fixed_cap;

    double   rl_qtable[SB_RL_NUM_STATES][SB_RL_NUM_ACTIONS];
    int      rl_state;
    int      rl_action;
    int      rl_degree;
    uint64_t rl_access_counter;
    uint64_t rl_epoch_len;
    uint8_t  rl_bw_level;
    uint64_t rl_bw_high_epochs;
    uint64_t rl_pref_issued;
    uint64_t rl_pref_useful;
    double   rl_prev_accuracy;
    double   rl_last_accuracy;
    uint64_t rl_track_table[SB_RL_TRACK_ENTRIES];
    uint64_t rl_epochs;
    uint64_t rl_degree_hist[SB_RL_NUM_ACTIONS];
    uint64_t rl_natdepth_hist[8];
    uint64_t rl_total_issued;
    uint64_t rl_total_useful;

private:
    // Dedup helpers
    void     addRecentPrefetch(uint64_t addr);
    bool     hasRecentlyPrefetched(uint64_t addr);
    bool     issue_prefetch(uint64_t addr, uint64_t ip);

    // Berti helpers
    uint64_t l1d_get_latency(uint64_t cycle, uint64_t cycle_prev);
    int      l1d_calculate_stride(uint64_t prev_offset, uint64_t current_offset);

    void     l1d_init_current_pages_table();
    uint64_t l1d_get_current_pages_entry(uint64_t page_addr);
    void     l1d_update_lru_current_pages_table(uint64_t index);
    uint64_t l1d_get_lru_current_pages_entry();
    int      l1d_get_berti_current_pages_table(uint64_t index, uint64_t &ctr);
    void     l1d_add_current_pages_table(uint64_t index, uint64_t page_addr, uint64_t ip, uint64_t offset);
    uint64_t l1d_update_demand_current_pages_table(uint64_t index, uint64_t offset);
    void     l1d_add_berti_current_pages_table(uint64_t index, int b);
    bool     l1d_requested_offset_current_pages_table(uint64_t index, uint64_t offset);
    void     l1d_remove_current_table_entry(uint64_t index);

    void     l1d_init_prev_requests_table();
    uint64_t l1d_find_prev_request_entry(uint64_t pointer, uint64_t offset);
    void     l1d_add_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle);
    void     l1d_reset_pointer_prev_requests(uint64_t pointer);
    uint64_t l1d_get_latency_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle);
    void     l1d_get_berti_prev_requests_table(uint64_t pointer, uint64_t offset, uint64_t cycle, int *b);

    void     l1d_init_prev_prefetches_table();
    uint64_t l1d_find_prev_prefetch_entry(uint64_t pointer, uint64_t offset);
    void     l1d_add_prev_prefetches_table(uint64_t pointer, uint64_t offset, uint64_t cycle);
    void     l1d_reset_pointer_prev_prefetches(uint64_t pointer);
    void     l1d_reset_entry_prev_prefetches_table(uint64_t pointer, uint64_t offset);
    uint64_t l1d_get_and_set_latency_prev_prefetches_table(uint64_t pointer, uint64_t offset, uint64_t cycle);
    uint64_t l1d_get_latency_prev_prefetches_table(uint64_t pointer, uint64_t offset);

    void     l1d_init_record_pages_table();
    uint64_t l1d_get_lru_record_pages_entry();
    void     l1d_update_lru_record_pages_table(uint64_t index);
    void     l1d_add_record_pages_table(uint64_t index, uint64_t page_addr, uint64_t vector, uint64_t first_offset, int b);
    uint64_t l1d_get_entry_record_pages_table(uint64_t page_addr, uint64_t first_offset);
    uint64_t l1d_get_entry_record_pages_table(uint64_t page_addr);
    void     l1d_copy_entries_record_pages_table(uint64_t index_from, uint64_t index_to);
    void     l1d_record_current_page(uint64_t index_current);

    void     l1d_init_ip_table();

    // Smart Stride helpers
    void     stride_initialize();
    uint64_t strideHashPc(uint64_t pc);
    void     stride_operate(uint64_t addr, uint64_t ip, uint8_t cache_hit, uint64_t current_cycle_arg);
    void     stride_trigger_prefetch(uint64_t addr, uint64_t ip);

    void     rl_init();
public:
    void     update_bw(uint8_t bw);
private:
    int      rl_get_state(double accuracy);
    int      rl_select_action(int state);
    void     rl_sarsa_update(int s, int a, double reward, int s_next, int a_next);
    void     rl_epoch_end();
    void     rl_track_prefetch(uint64_t addr);
    void     rl_check_demand(uint64_t addr);
    int      rl_cap_degree(int natural_degree);

    void     init_knobs();
    void     init_stats();

public:
    SBertiPrefetcher(string type);
    ~SBertiPrefetcher();
    void invoke_prefetcher(uint64_t pc, uint64_t address, uint8_t cache_hit, uint8_t type, vector<uint64_t> &pref_addr);
    void dump_stats();
    void print_config();
};

#endif /* SBERTI_H */
