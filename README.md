# SHA-256 Hardware Implementation in SystemVerilog

A SystemVerilog RTL implementation of the SHA-256 hash core, accompanied by a testbench with directed known-answer vectors.


## Overview

SHA-256 is a cryptographic hash function in the SHA-2 family. It processes message data in 512-bit blocks and produces a 256-bit digest.

This project implements the core datapath and control logic in SystemVerilog. The design uses an iterative, round-based architecture: the working registers and round logic are reused across the 64 rounds for a message block.

## Features

- SystemVerilog implementation of the SHA-256 core.
- 512-bit message-block input and 256-bit digest output.
- Iterative round processing using the eight 32-bit working variables (`a` through `h`).
- SHA-256 round-constant lookup logic.
- Message-schedule logic using a 16-word sliding window.
- Control and status signals for initialization, processing, readiness, and digest validity.
- Testbench containing known-answer vectors for `abc`, the empty message, and `test`.
- Testbench components for stimulus generation, driving, monitoring, scoreboard comparison, assertions, and functional coverage.

## Repository Structure

```text
sha_256/
├── src/
│   ├── sha256_core.sv         # Main SHA core datapath and control FSM
│   ├── sha256_k_constants.sv  # Round constants K[t]
│   └── sha256_w_mem.sv        # Message schedule and 16-word window
└── tb/
    └── sha256_tb.sv           # SystemVerilog testbench
```

## Design Architecture

### 1. SHA Core — `sha256_core.sv`

The top-level core accepts a 512-bit message block and coordinates the round-processing sequence. It maintains eight 32-bit working registers (`a` through `h`) and eight 32-bit hash-state registers.

The round datapath implements the SHA-256 operations, including:

- The **Choose** (`Ch`) and **Majority** (`Maj`) functions.
- The upper-case sigma functions using 32-bit rotations.
- The round calculations `T1` and `T2`.
- Hash-state accumulation after the round sequence.

The top-level interface includes `clk`, active-low `reset_n`, `init`, `next`, `mode`, `block`, `ready`, `digest`, and `digest_valid`.

### 2. Round Constants — `sha256_k_constants.sv`

This module selects the 32-bit round constant `K[t]` using the six-bit round index.

### 3. Message Schedule — `sha256_w_mem.sv`

This module loads the sixteen 32-bit words from the 512-bit input block. For later rounds, it calculates the next schedule word using the SHA-256 small-sigma functions and advances a sliding 16-word window.

### 4. Testbench — `sha256_tb.sv`

The testbench instantiates the core and generates the clock and reset. Its verification environment contains transaction, generator, driver, monitor, scoreboard, and functional-coverage components. It also includes an assertion to check that `init` and `next` are not asserted simultaneously.

The directed vectors in the testbench are:

| Input message | Expected SHA-256 digest |
|---|---|
| `abc` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| Empty message | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `test` | `9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08` |

These are single-block test cases: the testbench supplies the 512-bit padded block directly to the core.

## Interface Summary

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `clk` | Input | 1 | Clock |
| `reset_n` | Input | 1 | Active-low reset |
| `init` | Input | 1 | Initializes the hash state and loads the message block |
| `next` | Input | 1 | Control input used to start/advance block processing |
| `mode` | Input | 1 | Selects the SHA-256 or SHA-224 initial state in the RTL |
| `block` | Input | 512 | Padded message block |
| `ready` | Output | 1 | Indicates readiness according to the control FSM |
| `digest` | Output | 256 | Concatenated 256-bit hash-state output |
| `digest_valid` | Output | 1 | Indicates a valid digest according to the control FSM |

> **Scope:** The top-level interface accepts one already-padded 512-bit block. Automatic message padding and top-level multi-block message management are not provided by this interface.
## Simulation

The testbench uses SystemVerilog features including classes, mailboxes, a virtual interface, a clocking block, assertions, and covergroups. Use a simulator that supports these constructs.

The repository does not currently include a simulator-specific build script. Compile the RTL files and testbench with your simulator's SystemVerilog options, then run `sha256_tb` as the top-level module.

Source file list:

```text
src/sha256_k_constants.sv
src/sha256_w_mem.sv
src/sha256_core.sv
tb/sha256_tb.sv
```

Review the simulator output for scoreboard pass/fail messages and the final report. The presence of expected values in the source code does not by itself prove that the tests pass; confirm the results from an actual simulation run before reporting verification success.

## Synthesis and Analysis

The SHA-256 RTL was synthesized using **Cadence Genus**.

The project includes:
- **Pre-synthesis waveforms** to inspect RTL functional behavior.
- **Post-synthesis waveforms** to examine the synthesized design's behavior.
- **Area report** to analyze synthesized hardware resource usage.
- **Timing report** to evaluate timing characteristics.
- **Power report** to analyze estimated power consumption.

These reports provide a basis for evaluating the implementation across functionality, area, timing, and power.

## Tools

- **RTL Design:** SystemVerilog
- **Simulation and Verification:** SystemVerilog testbench, EDA playground.
- **Logic Synthesis:** Cadence Genus
- **Analysis:** Pre- and post-synthesis waveforms, power, area, and timing reports
## Author

**Meghana V**

---

This project demonstrates SHA-256 RTL design and verification concepts. It is not presented as a formally verified or production-certified cryptographic IP core.
