OBFU-Suite
An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

OBFU-Suite is a configurable and reproducible benchmark suite for security evaluation of HLS/RTL hardware obfuscation. The suite provides structurally diverse obfuscated RTL variants together with corresponding technology-mapped gate-level netlists, enabling security evaluation across multiple design abstractions.

1. Motivation

The globalization of the semiconductor supply chain has made hardware Intellectual Property (IP) increasingly vulnerable to threats such as IP piracy, reverse engineering, hardware Trojans, and malicious modifications. To address these threats, numerous High-Level Synthesis (HLS) and Register Transfer Level (RTL) hardware-obfuscation techniques have been proposed.

Recent advances in Machine Learning (ML) and Deep Learning (DL) have demonstrated the potential to compromise hardware-security mechanisms through automated analysis of structural and functional characteristics. However, unlike the gate-level domain, where publicly available benchmark resources such as Trust-Hub have supported systematic hardware-security evaluation, standardized benchmark resources for evaluating attacks against HLS/RTL obfuscation remain limited.

As a result, researchers often construct their own datasets using different designs, obfuscation methodologies, key configurations, and generation procedures. Such differences make fair comparison, reproducibility, and systematic benchmarking difficult.

OBFU-Suite addresses this gap by providing a unified benchmark framework for HLS/RTL hardware obfuscation, incorporating multiple state-of-the-art obfuscation methodologies under a common generation and validation methodology. In addition to RTL-level artifacts, the suite provides corresponding technology-mapped gate-level netlists, enabling investigation of whether obfuscation properties established at the HLS/RTL level remain effective after synthesis.

2. Features

OBFU-Suite provides:

Standardized benchmark resources for HLS/RTL hardware obfuscation
Multiple representative state-of-the-art obfuscation methodologies
Structurally diverse but functionally validated RTL variants
Multiple obfuscation coverage levels
Multiple key configurations
Corresponding technology-mapped gate-level netlists
Automated RTL synthesis validation
Independent gate-level netlist validation
RTL-level functional validation
Gate-level simulation validation
Authorized-key functional-correctness validation
Incorrect-key distinguishability validation
Cross-abstraction RTL and gate-level evaluation
Support for conventional hardware-security analysis
Support for emerging ML/DL-based attack and defense research
Reproducible benchmark-generation and validation procedures
3. Benchmark Configuration

OBFU-Suite uses a common configuration framework across the supported obfuscation methodologies. This enables controlled comparison while preserving the characteristics of the individual obfuscation techniques.

3.1 Key Configurations

The benchmark uses four balanced key patterns:

01010101...
10101010...
01100110...
10011001...

Each key contains an equal number of 0s and 1s, providing balanced key configurations for controlled experimental evaluation.

The key configurations are applied consistently across the supported obfuscation methodologies and coverage levels.

3.2 Obfuscation Coverage

Each supported methodology is evaluated at four obfuscation coverage levels:

Coverage	Description
25%	Low obfuscation coverage
50%	Medium obfuscation coverage
75%	High obfuscation coverage
100%	Full obfuscation coverage

The coverage level controls the proportion of eligible operations selected for obfuscation according to the corresponding methodology.

4. Dataset Generation

For each supported obfuscation methodology, benchmark variants are generated using controlled combinations of:

Benchmark design
Obfuscation methodology
Obfuscation coverage
Key configuration
Obfuscation parameters

The generation framework produces functionally equivalent but structurally diverse obfuscated RTL variants.

The authorized-key configuration preserves the intended functionality of the original design, while different valid configurations can produce structurally distinct implementations.

5. Included Obfuscation Methodologies

OBFU-Suite incorporates representative state-of-the-art HLS/RTL obfuscation methodologies.

5.1 PROTECTS

Reference:

PROTECTS: Progressive RTL Obfuscation with Threshold Control Technique During Architectural Synthesis.

Configuration:

4 balanced key patterns
25%, 50%, 75%, and 100% obfuscation coverage
Structurally diverse obfuscated RTL variants
Corresponding technology-mapped gate-level netlists
5.2 KOIL

Reference:

High-Level Synthesis of Key-Obfuscated RTL IP with Design Lockout and Camouflaging.

Configuration:

4 balanced key patterns
25%, 50%, 75%, and 100% obfuscation coverage
Structurally diverse obfuscated RTL variants
Corresponding technology-mapped gate-level netlists
5.3 ILP

Reference:

Low Cost Functional Obfuscation of Reusable IP Cores Used in Consumer Electronics Hardware Through Robust Locking.

Configuration:

4 balanced key patterns
25%, 50%, 75%, and 100% obfuscation coverage
Structurally diverse obfuscated RTL variants
Corresponding technology-mapped gate-level netlists
5.4 ASSURE

Reference:

ASSURE: RTL Locking Against an Untrusted Foundry.

Configuration:

4 balanced key patterns
25%, 50%, 75%, and 100% obfuscation coverage
Structurally diverse obfuscated RTL variants
Corresponding technology-mapped gate-level netlists
6. Benchmark Domains

OBFU-Suite contains representative designs from multiple application domains, including:

Signal Processing
Image Processing
Video Processing
Computer Graphics

The diversity of the benchmark collection is intended to reduce dependence on a single application class and provide structurally different designs for security evaluation.

7. RTL and Gate-Level Artifacts

OBFU-Suite provides two complementary design abstractions.

RTL Level

The RTL portion contains:

Golden RTL designs
Obfuscated RTL variants
Key configurations
Obfuscation coverage information
Gate Level

For validated RTL variants, the corresponding:

Technology-mapped gate-level Verilog netlists
Target standard-cell implementations
RTL-to-gate-level correspondence

are provided.

This organization enables researchers to study security both before and after synthesis.

8. RTL-to-Gate-Level Generation

The gate-level representations are generated using the prescribed Yosys--ABC flow and the target 45-nm standard-cell library.

Obfuscated RTL
       |
       v
Logic Synthesis
       |
       v
ABC Technology Mapping
       |
       v
Technology-Mapped
Gate-Level Netlist

The resulting gate-level Verilog contains technology-mapped standard-cell instances corresponding to the target library.

9. Validation Methodology

Every generated variant is subjected to automated validation before being included in the released benchmark.

9.1 RTL Synthesis Validation

Each generated obfuscated RTL variant is processed using the prescribed Vivado 2026.1 synthesis flow.

Generated RTL Variant
        |
        v
Vivado Synthesis
        |
   +----+----+
   |         |
 Pass      Fail
   |         |
 Retain    Reject

A variant that fails the prescribed synthesis flow is automatically excluded and is not forwarded to subsequent functional validation.

9.2 Gate-Level Netlist Validation

The technology-mapped gate-level netlist generated using the prescribed Yosys--ABC flow is independently checked using the prescribed Quartus Prime Lite environment.

Generated Gate-Level Netlist
             |
             v
     Quartus Prime Lite
             |
       +-----+-----+
       |           |
      Pass        Fail
       |           |
     Retain      Reject

This independent validation provides an additional tool-level consistency check for the released gate-level representations.

9.3 RTL Simulation Validation

The synthesis-valid obfuscated RTL variant is simulated against its corresponding golden RTL design.

Authorized Key

For the authorized key:

Golden RTL Output
        =
Obfuscated RTL Output

for all prescribed validation stimuli.

Incorrect Keys

For representative incorrect keys, at least one distinguishing stimulus must expose an observable output deviation:

Golden RTL Output
        ≠
Obfuscated RTL Output

Variants that fail either criterion are rejected.

9.4 Gate-Level Simulation Validation

Gate-level simulation provides an additional functional validation after synthesis.

The corresponding golden and obfuscated gate-level representations are simulated using identical input stimuli and key configurations.

Authorized Key
Golden Gate Output
        =
Obfuscated Gate Output
Incorrect Key
Golden Gate Output
        ≠
Obfuscated Gate Output

at least for one prescribed distinguishing stimulus.

This stage verifies that the required functional behavior and key-dependent behavior are preserved after RTL-to-gate-level synthesis.

10. Dataset Organization

A typical organization is:

OBFU-Suite/
│
├── PROTECTS/
│   ├── RTL/
│   ├── Gate-Level/
│   └── Configurations/
│
├── KOIL/
│   ├── RTL/
│   ├── Gate-Level/
│   └── Configurations/
│
├── ILP/
│   ├── RTL/
│   ├── Gate-Level/
│   └── Configurations/
│
├── ASSURE/
│   ├── RTL/
│   ├── Gate-Level/
│   └── Configurations/
│
├── scripts/
│   ├── generation/
│   ├── synthesis/
│   └── validation/
│
├── documentation/
│
├── LICENSE
└── README.md

Important: change this tree to exactly match your actual GitHub repository. Do not show folders that do not exist in the release.

11. Benchmark Traceability

Each released gate-level netlist maintains a one-to-one correspondence with its source obfuscated RTL variant.

Benchmark
   |
   +-- Golden RTL
   |
   +-- Obfuscated RTL Variant
   |
   +-- Key Configuration
   |
   +-- Coverage Level
   |
   +-- Gate-Level Netlist

This identifier-based organization enables traceability across design abstractions and supports reproducible cross-abstraction security experiments.

12. Research Applications

OBFU-Suite can support research on:

Hardware Security
HLS/RTL obfuscation
RTL locking
Logic locking
Hardware IP protection
Structural security analysis
Attack Research
Structural attacks
Key-recovery attacks
Oracle-based attacks
Oracle-less attacks
ML-based attacks
DL-based attacks
Graph-based attacks
GNN-based attacks
Cross-Abstraction Analysis
RTL-to-gate-level security
Synthesis-induced information leakage
Gate-level structural analysis
Cross-abstraction attack scenarios
Security degradation after synthesis
Benchmarking
Attack-versus-defense evaluation
Obfuscation-strength analysis
Generalization studies
Reproducibility studies
Comparative security evaluation
13. Tools and Environment

The benchmark-generation and validation framework uses the following tools:

Tool	Purpose
Vivado 2026.1	RTL synthesis validation
Yosys	RTL synthesis and logic processing
ABC	Logic optimization and technology mapping
Nangate 45-nm Library	Technology mapping
Quartus Prime Lite	Independent gate-level validation
ModelSim	Functional/gate-level simulation
Python	Automation and orchestration
TCL	Simulation and tool-flow automation

The exact tool versions and configurations associated with each benchmark release should be documented with the corresponding release.

14. Reproducibility

OBFU-Suite is designed to support reproducible hardware-security experiments.

The released artifacts are organized according to their:

Benchmark
Obfuscation methodology
Coverage level
Key configuration
RTL variant
Gate-level representation

The validation process is automated to minimize manual intervention and ensure consistent benchmark admission.

A released variant is included only after satisfying the prescribed synthesis and functional validation criteria.

15. Release

The current OBFU-Suite benchmark release is available at:

OBFU-Suite GitHub Release

https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite
