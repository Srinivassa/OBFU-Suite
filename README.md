# OBFU-Suite

### An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

**OBFU-Suite** is a configurable and reproducible benchmark suite for evaluating **HLS/RTL hardware obfuscation** across both RTL and technology-mapped gate-level representations. The suite provides structurally diverse but functionally validated benchmark variants generated using representative state-of-the-art obfuscation methodologies.

It is designed to support reproducible hardware-security research, benchmark comparison, and cross-abstraction security evaluation.


## Why OBFU-Suite?

The globalization of the semiconductor supply chain has made hardware **Intellectual Property (IP)** increasingly vulnerable to threats such as:

- IP piracy
- Reverse engineering
- Hardware Trojans
- Malicious hardware modifications

To mitigate these threats, numerous **High-Level Synthesis (HLS)** and **Register Transfer Level (RTL)** obfuscation techniques have been proposed.

Recent advances in **Machine Learning (ML)** and **Deep Learning (DL)** have shown the potential to compromise many hardware-security mechanisms. While gate-level security research benefits from standardized benchmark resources such as **Trust-Hub**, **no common benchmark previously existed for evaluating HLS/RTL obfuscation techniques under a unified and reproducible framework**.

**OBFU-Suite addresses this gap** by providing a standardized benchmark generation and validation framework for HLS/RTL hardware obfuscation, together with corresponding technology-mapped gate-level netlists for cross-abstraction security evaluation.

## Features

- Standardized benchmark suite for **HLS/RTL hardware obfuscation**
- Multiple **state-of-the-art obfuscation methodologies**
- Four balanced key configurations
- Four obfuscation coverage levels
- Functionally equivalent but structurally diverse RTL variants
- Corresponding **technology-mapped gate-level netlists**
- Automated RTL synthesis, gate-level synthesis, and functional validation
- Suitable for:
  - Machine Learning (ML) attacks
  - Deep Learning (DL) attacks
  - Graph Neural Network (GNN) attacks
  - Oracle-guided attacks
  - Oracle-less attacks
  - Cross-abstraction RTL-to-gate-level security analysis



# Benchmark Configuration

Each supported obfuscation methodology is generated using the **same benchmark configuration**, enabling fair comparison across different protection techniques.

| Configuration | Value |
|-------------------------|--------------------------------|
| Key Patterns | 4 Balanced Keys |
| Obfuscation Coverage | 25%, 50%, 75%, 100% |
| Design Representation | RTL + Gate-Level Netlist |
| Standard Cell Library | Nangate 45nm |
| RTL Validation | Vivado 2026.1 |
| Gate-Level Generation | Yosys + ABC |
| Gate-Level Validation | Quartus Prime Lite |
| Functional Simulation | ModelSim + TCL |

## Key Patterns

The benchmark uses four balanced secret keys throughout the dataset.

| Key Configuration | Pattern |
|-------------------|---------|
| Key-0101 | `01010101...` |
| Key-1010 | `10101010...` |
| Key-0110 | `01100110...` |
| Key-1001 | `10011001...` |

Each key contains an equal number of **0s** and **1s**, providing balanced key distributions for ML/DL-based security evaluation.

## Obfuscation Coverage

Every benchmark is generated using four protection levels.

| Coverage Level | Description |
|----------------|-------------|
| **25%** | Low obfuscation coverage |
| **50%** | Medium obfuscation coverage |
| **75%** | High obfuscation coverage |
| **100%** | Full obfuscation coverage |



## Dataset Size

For **every** combination of:

- Obfuscation methodology
- Key pattern
- Obfuscation coverage level

OBFU-Suite contains:

> **5,000 structurally unique but functionally equivalent hardware variants.**

This results in a large-scale benchmark suitable for ML/DL training, testing, and reproducible security evaluation.


# Included Obfuscation Methodologies

OBFU-Suite currently includes four representative HLS/RTL obfuscation methodologies.

## PROTECTS

**Reference**

> *PROTECTS: Progressive RTL Obfuscation with Threshold Control Technique During Architectural Synthesis.*

**Configuration**

- 4 balanced key patterns
- 25%, 50%, 75%, and 100% obfuscation coverage
- 5,000 RTL variants per key pattern
- Corresponding technology-mapped gate-level netlists



## KOIL

**Reference**

> *High-Level Synthesis of Key-Obfuscated RTL IP with Design Lockout and Camouflaging.*

**Configuration**

- 4 balanced key patterns
- 25%, 50%, 75%, and 100% obfuscation coverage
- 5,000 RTL variants per key pattern
- Corresponding technology-mapped gate-level netlists



## ILP

**Reference**

> *Low Cost Functional Obfuscation of Reusable IP Cores Used in Consumer Electronics Hardware Through Robust Locking.*

**Configuration**

- 4 balanced key patterns
- 25%, 50%, 75%, and 100% obfuscation coverage
- 5,000 RTL variants per key pattern
- Corresponding technology-mapped gate-level netlists



## ASSURE

**Reference**

> *ASSURE: RTL Locking Against an Untrusted Foundry.*

**Configuration**

- 4 balanced key patterns
- 25%, 50%, 75%, and 100% obfuscation coverage
- 5,000 RTL variants per key pattern
- Corresponding technology-mapped gate-level netlists


# Benchmark Domains

OBFU-Suite includes benchmark designs from multiple application domains.

| Domain | Example Benchmarks |
|--------|--------------------|
| Signal Processing | ARF, FIR, FFT, BPF, IIRB |
| Image Processing | DCT, DWT, JPEG-IDCT, IDCT |
| Video Processing | MPEG |
| Computer Graphics | MESA-Horner, MESA-Matrix, Feedback-Point |

This diversity enables evaluation across structurally different hardware applications.


# RTL-to-Gate-Level Benchmark Flow

Every released benchmark maintains a one-to-one correspondence between RTL and gate-level representations.

Golden RTL
      │
      ├──────────────► Golden Gate-Level Netlist
      │
      ▼
Obfuscated RTL Variant
      │
      ▼
RTL Validation (Vivado)
      │
      ▼
Logic Synthesis
      │
      ▼
ABC Technology Mapping
      │
      ▼
Technology-Mapped Gate-Level Netlist
      │
      ▼
Gate-Level Validation & Simulation


This organization enables security evaluation **before and after synthesis**.


# Validation Pipeline

Every benchmark variant is automatically validated before being included in OBFU-Suite.

| Validation Stage | Tool |
|------------------|------|
| RTL Synthesis Validation | Vivado 2026.1 |
| Gate-Level Netlist Validation | Quartus Prime Lite |
| RTL Functional Validation | ModelSim + TCL |
| Gate-Level Functional Validation | ModelSim + TCL |

A released variant must satisfy:

- RTL synthesis success
- Gate-level synthesis success
- Authorized-key functional correctness
- Incorrect-key distinguishability
- RTL-to-gate-level functional consistency


# Repository Structure

OBFU-Suite/
├── PROTECTS/
│   ├── RTL/
│   └── Gate-Level/
│  
│
├── KOIL/
│   ├── RTL/
│   └── Gate-Level/
│
├── ILP/
│   ├── RTL/
│   └── Gate-Level/
│
├── ASSURE/
│   ├── RTL/
│   └── Gate-Level/
│
├── scripts/
│   ├── generation/
│   └── Gate-Level/
│
├── documentation/
├── LICENSE
└── README.md

Each methodology contains datasets generated using:

- 4 balanced key patterns
- 4 obfuscation coverage levels
- 5,000 structurally unique RTL variants per configuration
- Corresponding validated gate-level netlists

# Research Applications

OBFU-Suite supports research on:

- HLS/RTL hardware obfuscation
- Logic locking and RTL locking
- Structural vulnerability analysis
- Oracle-guided and oracle-less attacks
- ML/DL-based hardware-security attacks
- Graph Neural Network (GNN) attacks
- Cross-abstraction RTL-to-gate-level security evaluation
- Attack-versus-defense benchmarking

# Benchmark Release

**GitHub Release**

**OBFU-Suite:** An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

GitHub Release:
https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite

# Citation

If you use **OBFU-Suite** in your research, please cite:

```bibtex
@misc{OBFUSuite,
  author       = {Dara, Srinivasa Rao and Roy, Dipanjan and Kavati, Ilaiah},
  title        = {{OBFU-Suite}: An Obfuscation Benchmark for Unified {HLS/RTL} and Gate-Level Security Assessment},
  year         = {2026},
  howpublished = {\url{https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite}},
  note         = {GitHub benchmark release}
}

# License

Please refer to the **LICENSE** file for usage, modification, and redistribution terms.

# Contact

For questions, issues, or benchmark requests, please use the GitHub **Issues** page or contact the repository authors.
