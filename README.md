# Synchronous-FIFO-Verification

A 16 x 8-bit synchronous FIFO written in Verilog and verified with a self-checking SystemVerilog testbench: constrained-random stimulus, a queue-based scoreboard, SVA assertions and functional coverage. Five deliberately injected bugs are used to measure how well the testbench actually detects errors.

This is an educational project built step by step while learning digital design verification.

## Contents

- [Design under test](#design-under-test)
- [Verification environment](#verification-environment)
- [Results](#results)
- [How to run](#how-to-run)
- [Known limitations](#known-limitations)
- [Future work](#future-work)

## Repository structure

```
sync-fifo-verification/
├── README.md
├── .gitignore
├── src/
│   └── sync_fifo.v                 # design under test (with switchable bugs)
├── tb/
│   ├── tb_sync_fifo_directed.v     # directed testbench (7 tests)
│   ├── tb_random.sv                # random testbench + scoreboard (top: tb_random)
│   ├── fifo_sva.sv                 # SystemVerilog assertions (passive checker)
│   └── fifo_cov.sv                 # functional coverage (passive collector)
└── sim/                            # waveform and transcript screenshots
```

## Design under test

`src/sync_fifo.v` is a single-clock FIFO built as a circular buffer.

| Parameter | Default | Meaning |
|---|---|---|
| `DATA_WIDTH` | 8 | Width of each entry |
| `DEPTH` | 16 | Number of entries (power of two) |

| Port | Dir | Description |
|---|---|---|
| `clk` | in | Clock, all logic on the rising edge |
| `rst_n` | in | Active-low asynchronous reset |
| `wr_en`, `data_in` | in | Write request and data |
| `rd_en` | in | Read request |
| `data_out` | out | Registered read data, valid one clock cycle after `rd_en` |
| `full`, `empty` | out | Status flags |

Behavior:

- Read and write pointers are `log2(DEPTH)+1` bits wide. The extra bit tells a full FIFO from an empty one: `empty` when the pointers are equal, `full` when the address bits are equal but the extra bits differ.
- A write while `full` and a read while `empty` are ignored.
- Simultaneous read and write are allowed.
- Reset clears the pointers and `data_out`; memory contents are not cleared.

The design synthesizes in Quartus Prime Lite for an Intel MAX 10 device, where the storage is inferred as on-chip RAM.

## Verification environment

```
                         tb_random
  +---------------------------------------------------------------+
  |  fifo_txn  (random wr / rd / data)                            |
  |      |  weights change per phase, driven on negedge clk       |
  |      v                                                        |
  |  +----------+      +-------------+      +------------------+  |
  |  | stimulus | ---> |  sync_fifo  | ---> |    scoreboard    |  |
  |  +----------+      |    (DUT)    |      | queue ref. model |  |
  |                    +-------------+      +------------------+  |
  |                      |         |                              |
  |               +-----------+ +-----------+                     |
  |               | fifo_sva  | | fifo_cov  |   (passive)         |
  |               +-----------+ +-----------+                     |
  +---------------------------------------------------------------+
```

Stimulus is driven on the falling clock edge and the DUT samples on the rising edge, which avoids race conditions between testbench and design.

### Directed tests (`tb/tb_sync_fifo_directed.v`)

| Test | Scenario | What is checked |
|---|---|---|
| T1 | Right after reset | `empty=1`, `full=0` |
| T2 | Write `DEPTH` values | `full=1` |
| T3 | Read all values back | Same order as written, `empty=1` at the end |
| T4 | Write while full | Extra write ignored, data intact |
| T5 | Read while empty | `data_out` and pointers unchanged |
| T6 | Write and read in the same cycle (half full) | Correct data, FIFO order preserved |
| T7 | Reset in the middle of operation | FIFO empty, old data not leaked |

### Constrained-random test (`tb/tb_random.sv`)

Random transactions (`wr`, `rd`, `data`) are generated in four phases with different write/read probabilities so that both full and empty are reached:

| Phase | Cycles | P(write) / P(read) | Purpose |
|---|---|---|---|
| A | 200 | 80% / 20% | Drive the FIFO to full |
| B | 200 | 20% / 80% | Drive the FIFO to empty |
| C | 400 | 50% / 50% | Many simultaneous reads and writes |
| D | 24 | 0% / 100% | Drain, so leftover data is also checked |

### Scoreboard

A plain SystemVerilog queue models an ideal FIFO. On every rising edge the testbench:

1. checks `data_out` against the value expected from the read of the previous cycle (output is registered);
2. checks that `full` and `empty` match the model occupancy;
3. updates the model, using the state before the edge, exactly as the DUT does.

### Assertions (`tb/fifo_sva.sv`)

| Assertion | Rule |
|---|---|
| `a_not_full_and_empty` | `full` and `empty` are never both 1 |
| `a_no_x_flags` | Flags are never X/Z after reset |
| `a_empty_after_reset` | FIFO is empty and not full right after reset is released |
| `a_write_makes_nonempty` | Writing to an empty FIFO clears `empty` |
| `a_read_makes_nonfull` | Reading from a full FIFO clears `full` |
| `a_full_stays_full` | A write on a full FIFO (without read) leaves it full |
| `a_empty_stays_empty` | A read on an empty FIFO (without write) leaves it empty |
| `a_empty_read_keeps_data` | A read on an empty FIFO does not change `data_out` |

### Functional coverage (`tb/fifo_cov.sv`)

The FIFO level is split into 5 bins (`zero`, `low`, `mid`, `high`, `full`) and crossed with the write request and read request, giving 5 x 2 x 2 = **20 bins**. These include the corner cases write-on-full, read-on-empty, and simultaneous read/write at every level.

### Bug injection

`src/sync_fifo.v` contains five switchable bugs (all off by default):

| Bug | Description |
|---|---|
| `BUG1` | Extra pointer bit forgotten: `full = (wr_ptr == rd_ptr)` |
| `BUG2` | Write is not blocked when the FIFO is full |
| `BUG3` | Read is not blocked when the FIFO is empty |
| `BUG4` | Bit 0 of the data is lost, only for the last memory location |
| `BUG5` | The write is dropped when a read happens in the same cycle |

## Results

Simulator: ModelSim Intel FPGA Edition 2020.1.

### Correct design

| Testbench | Result |
|---|---|
| Directed (T1-T7) | All tests pass |
| Random + scoreboard | 1948 checks, 0 errors (`SCOREBOARD PASSED`) |
| Functional coverage | 20 / 20 bins (100%) |

During the random run the FIFO was full in 159 cycles, empty in 157 cycles, and received simultaneous read and write in 166 cycles, over about 830 clock cycles.

### Bug injection

| Bug | Detected by | First error | Scoreboard errors (of 1948 checks) |
|---|---|---|---|
| BUG1 | `full` flag check | 35 ns | 1631 |
| BUG2 | `full` flag check | 405 ns | 310 |
| BUG3 | `empty` flag check | 75 ns | 377 |
| BUG4 | `data_out` data check | 1775 ns | 14 |
| BUG5 | `empty` flag check | 85 ns | 423 |

The scoreboard detected all five bugs.

Observations:

- **BUG4 is the subtle one.** Only 14 errors, first one at 1775 ns, and every error is a value with bit 0 cleared. The flags stayed correct, the statistics were identical to the correct design, and coverage still reported 20/20. Only the data comparison in the scoreboard exposes it.
- **BUG2, BUG3 and BUG5 appear only in corner cases** (write on full, read on empty, simultaneous read/write). After the first mismatch the DUT and the model stay out of sync, so errors multiply.
- **Coverage measures stimulus, not correctness.** BUG4 passed with 100% coverage. Coverage numbers are only meaningful on the correct design: when the DUT is buggy its flags are wrong, and the coverage level counter, which uses those flags, is wrong too.

## How to run

### ModelSim / Questa

From the repository root:

```
vlib work

# directed testbench (top: tb)
vlog src/sync_fifo.v tb/tb_sync_fifo_directed.v
vsim -voptargs=+acc work.tb
run -all

# random testbench with scoreboard, assertions and coverage (top: tb_random)
vlog -sv src/sync_fifo.v tb/fifo_sva.sv tb/fifo_cov.sv tb/tb_random.sv
vsim -voptargs=+acc work.tb_random
run -all
```

At the end of the transcript the random testbench prints statistics, the scoreboard result, assertion failures and the coverage report.

### Inject a bug

Add a define at compile time, then re-run `vsim`:

```
vlog -sv +define+BUG1 src/sync_fifo.v tb/fifo_sva.sv tb/fifo_cov.sv tb/tb_random.sv
```

### Compile-time options

| Define | Effect |
|---|---|
| `BUG1` ... `BUG5` | Enable one injected bug in the DUT |
| `USE_RANDOMIZE` | Use `randomize()` with `constraint dist` instead of `$urandom_range` |
| `USE_COVERGROUP` | Use a real `covergroup` / `cross` instead of counter-based coverage |

`USE_RANDOMIZE` and `USE_COVERGROUP` are meant for simulators with full SystemVerilog verification support (Questa, VCS, Xcelium, Riviera-PRO). The results above were produced in the default mode, which runs on any simulator.

## Known limitations

- **Assertions were not executed in ModelSim Intel FPGA Edition 2020.1.** The compiler accepts the SVA but warns (`vlog-2186`) that assertions are only supported in Questa, and `assertion failures: 0` was reported even with `BUG1` enabled. The assertion results in the transcript are therefore not used as evidence here. Running the assertions on a simulator with full SVA support is still to be done.
- Functional coverage uses counters in the default mode, and its level counter is derived from the DUT flags, so it is only valid on the correct design.
- The random test uses the simulator's default seed, so runs are repeatable but cover one seed only.
- Single clock domain only.

## Future work

- Run the assertions and the `covergroup` / `randomize()` modes on a simulator with full SystemVerilog support and add the results.
- Add data-oriented coverage (for example odd and even values written to every memory location) and take the level from the reference model instead of the DUT flags.
- Run multiple seeds and report coverage per seed.
- Restructure the testbench into UVM-style components (driver, monitor, scoreboard).
- Extend the project to an asynchronous FIFO.

## Author

Thang Luu Quoc, Electronics and Telecommunications Engineering, VNU University of Engineering and Technology.
