# Experimental contract

## Controller

- SARSA learning rate: 0.5
- Discount factor: 0.6
- Exploration: 0
- Scientific epoch: 1024 L2 accesses
- State: `2*b_acc + I[d>2]`
- Reward: `100*(u_t-u_{t-1}) - 5*d_t*I[b_t>=3]`
- OLD4 actions: `{1,2,4,8}`
- NEW5 actions: `{0,1,2,4,8}`
- Physical NEW5 map in source: `[1,2,4,8,0]`

Controlled OFF suppresses the ELSA-controlled SmartStride path only; it is not equivalent to global no-prefetch.

## Statistical discipline

The paper reports geometric-mean IPC effects, paired median percentage changes, win/tie/loss counts, and exact sign tests where used. Deterministic reruns and integrity checks are reproducibility checks rather than independent statistical replicates.

The 617 total is an execution ledger count, not a single sample size.
