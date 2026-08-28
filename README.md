# OBFU-Suite: An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

## Contact

This repository contains the benchmark artifacts and generation/validation
resources associated with:

Srinivasa Rao Dara, Dipanjan Roy, and Ilaiah Kavati,

"OBFU-Suite: An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level
Security Assessment."

---

## Overview

OBFU-Suite is a configurable benchmark suite for reproducible security
evaluation of HLS/RTL hardware obfuscation.

The suite provides benchmark variants generated using multiple
state-of-the-art HLS/RTL obfuscation methodologies under a common
configuration. It includes both obfuscated RTL variants and their
corresponding technology-mapped gate-level netlists.

OBFU-Suite is intended for evaluating hardware-security techniques,
including structural analysis, key-recovery attacks, ML/DL-based attacks,
and cross-abstraction security analysis.

---

## Benchmark Configuration

Each obfuscation methodology is generated using the same benchmark
configuration.

### Key Patterns

Four balanced key patterns are used:

    01010101...
    10101010...
    01100110...
    10011001...

Each key contains an equal number of 0s and 1s.

### Obfuscation Coverage

Each benchmark is generated at:

    25%
    50%
    75%
    100%

### Dataset Size

For each benchmark, obfuscation methodology, key pattern, and coverage
configuration, 5,000 structurally unique and functionally equivalent
variants are generated.

---

## Included Obfuscation Methodologies

### PROTECTS

Reference:

> PROTECTS: Progressive RTL Obfuscation with Threshold Control Technique
> During Architectural Synthesis.

Configuration:

- 4 key patterns
- 4 coverage levels
- 5,000 variants per configuration

### KOIL

Reference:

> High-Level Synthesis of Key-Obfuscated RTL IP with Design Lockout and
> Camouflaging.

Configuration:

- 4 key patterns
- 4 coverage levels
- 5,000 variants per configuration

### ILP

Reference:

> Low Cost Functional Obfuscation of Reusable IP Cores Used in Consumer
> Electronics Hardware Through Robust Locking.

Configuration:

- 4 key patterns
- 4 coverage levels
- 5,000 variants per configuration

### ASSURE

Reference:

> ASSURE: RTL Locking Against an Untrusted Foundry.

Configuration:

- 4 key patterns
- 4 coverage levels
- 5,000 variants per configuration

---

## Requirements

The benchmark-generation and validation flow uses:

- Vivado 2026.1
- Yosys
- ABC
- Nangate 45-nm standard-cell library
- Quartus Prime Lite
- ModelSim
- Python
- TCL

---

## RTL-to-Gate-Level Generation

The provided RTL variants can be converted into technology-mapped
gate-level netlists using the Yosys--ABC flow.

The synthesis flow is:

    RTL
     |
     v
    Logic Synthesis
     |
     v
    ABC Technology Mapping
     |
     v
    Technology-Mapped Gate-Level Netlist

The complete batch synthesis script is available under:

    scripts/synthesis/

Run:

    chmod +x scripts/synthesis/rtl_to_gate.sh

    ./scripts/synthesis/rtl_to_gate.sh

Before execution, update the input, output, library, and mapping-file paths
in the script for the local environment.

---

## Validation

Each released variant is validated through automated synthesis and
simulation checks.

### RTL Validation

- RTL synthesis
- Authorized-key functional correctness
- Incorrect-key functional distinguishability

### Gate-Level Validation

- Independent synthesis/compilation check
- Authorized-key functional correctness
- Incorrect-key functional distinguishability
- Gate-level functional consistency

Only variants satisfying the prescribed validation criteria are retained.

---
Demonstration / Attack Framework Execution
The generated gate-level and RTL-level graph datasets can be evaluated using graph-neural-network attack frameworks. Below are the commands to execute graph extraction, model training, and key-bit prediction.

# RTL-Level Demonstration:

###1. Graph Extraction (RTL) Convert the RTL Verilog files into graph datasets:

---bash
perl netlist_to_subgraph_rtl.pl -f ASSURE_IIRB_100pct_1010 -i ./circuit_datasets/ASSURE_IIRB_100pct_1010 > log_build_exploit_ASSURE_IIRB_100pct_1010.txt
---
###2. Model Training (RTL) Train the GNN model using a 3-hop enclosing subgraph:

---bash:
python Main_rtl.py \
  --file-name ASSURE_IIRB_100pct_1010 \
  --links-name link.txt \
  --save-model \
  --split-val \
  --use-dis \
  --batch_size 64 \
  --hop 3 \
  --num_layers 6 \
  --num_mlp_layers 2 \
  --hidden_dim 64 \
  --final_dropout 0.5 \
  --filename Release_ASSURE_IIRB_100pct_1010_result_b64_h3_fan_6layers_hd64.txt \
  > log_train_ASSURE_IIRB_100pct_1010_rtl_3hop.txt 2>&1
---
###3. Key-Bit Prediction (RTL) Evaluate the trained model on the unseen test graphs:

---bash
python Main_rtl.py \
  --file-name ASSURE_IIRB_100pct_1010 \
  --links-name link.txt \
  --only-predict \
  --split-val \
  --use-dis \
  --no-parallel \
  --device 0 \
  --batch_size 64 \
  --hop 3 \
  --num_layers 6 \
  --num_mlp_layers 2 \
  --hidden_dim 64 \
  --final_dropout 0.5 \
  > predict_ASSURE_IIRB_100pct_1010_rtl_b64_h3_6layers_hd64.txt 2>&1
---
Gate-Level Demonstration
### 1. Graph Extraction (Gate-Level) Convert the Gate-Level Verilog files into graph datasets:

---bash
perl netlist_to_subgraphs.pl -f ASSURE_IIRB_100_obf-gate-sample -i ./circuit_datasets/ASSURE_IIRB_100_obf-gate-sample > log_build_exploit_ASSURE_IIRB_100_obf-gate-sample.txt
---
### 2. Model Training (Gate-Level) Train the GNN model using a 2-hop enclosing subgraph:
Train the GNN model using a 2-hop enclosing subgraph:

---bash
python Main.py \
  --file-name ASSURE_IIRB_100_obf-gate \
  --links-name link.txt \
  --save-model \
  --split-val \
  --use-dis \
  --batch_size 64 \
  --hidden_dim 64 \
  --num_layers 6 \
  --filename Release_ASSURE_IIRB_100_obf-gate_result_b64_h2_fan_6layers_hd64.txt \
  > Release_log_ASSURE_IIRB_100_obf-gate_b64_h2_6layers_hd64.txt
---
### 3. Key-Bit Prediction (Gate-Level) Evaluate the trained model on the unseen test graphs:


Evaluate the trained model on the unseen test graphs:

```bash
python Main.py \
  --file-name ASSURE_IIRB_100_obf-gate-sample \
  --links-name link.txt \
  --only-predict \
  --no-parallel \
  --device 0 \
  --batch_size 64 \
  --hidden_dim 64 \
  --num_layers 6 \
  --num_mlp_layers 3 \
  --final_dropout 0.5 \
  --hop 1 \
  --graph_pooling_type sum \
  --neighbor_pooling_type max
```


## Dataset Organization

    OBFU-Suite/
    ├── PROTECTS/
    ├── KOIL/
    ├── ILP/
    ├── ASSURE/
    ├── scripts/
    └── README.md

The exact directory structure may vary between releases.

---

## Release

The benchmark release is available at:

https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite

---

## Citation

If you use OBFU-Suite in your work, please cite:

@misc{OBFUSuite,
  author       = {Dara, Srinivasa Rao and Roy, Dipanjan and Kavati, Ilaiah},
  title        = {{OBFU-Suite}: An Obfuscation Benchmark for Unified {HLS/RTL}
                  and Gate-Level Security Assessment},
  year         = {2026},
  howpublished = {\url{https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite}},
  note         = {GitHub benchmark release}
}

---

## Acknowledgement

We acknowledge the developers of the hardware-security, HLS, RTL synthesis,
and EDA tools used in the generation and validation of OBFU-Suite.
