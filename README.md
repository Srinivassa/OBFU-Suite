# OBFU-Suite

### An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

OBFU-Suite is a configurable and reproducible benchmark suite for evaluating
hardware obfuscation techniques at the HLS/RTL and gate levels. The suite is
designed to provide a common experimental foundation for security evaluation
of obfuscated hardware designs and to enable systematic investigation of
security properties across design abstractions.

The benchmark suite incorporates representative state-of-the-art (SOTA)
obfuscation methodologies and provides structurally diverse RTL benchmark
variants across multiple obfuscation coverage levels and key configurations.
For each validated RTL variant, the corresponding technology-mapped
gate-level netlist is also provided.

---

## Key Features

- Configurable HLS/RTL hardware-obfuscation benchmarks
- Representative state-of-the-art obfuscation methodologies
- Multiple obfuscation coverage levels
- Multiple key configurations
- Structurally diverse obfuscated RTL variants
- Corresponding technology-mapped gate-level netlists
- Automated RTL synthesis validation
- Independent gate-level netlist validation
- RTL-level functional validation
- Gate-level simulation validation
- Authorized-key functional-correctness checking
- Incorrect-key distinguishability checking
- Cross-abstraction RTL and gate-level security evaluation
- Reproducible benchmark-generation and validation flow

---

## Motivation

Hardware-security research at the gate level benefits from established
benchmark resources for evaluating obfuscation and attack methodologies.
However, comparable standardized and reproducible resources for HLS/RTL-level
hardware obfuscation remain limited.

OBFU-Suite addresses this gap by providing benchmark variants at both the
HLS/RTL and technology-mapped gate levels. This organization enables
researchers to evaluate whether security properties introduced at the
HLS/RTL level remain effective after synthesis and under gate-level analysis.

The suite is intended to support both conventional hardware-security
methodologies and emerging data-driven approaches, including machine-learning
(ML) and deep-learning (DL)-based attack and defense techniques.

---

## Benchmark Organization

Each benchmark in OBFU-Suite is organized around an original golden design
and its corresponding obfuscated variants.

The benchmark organization follows:

    Golden RTL
        |
        +----------------------+
        |                      |
        v                      v
    Obfuscation           Original Design
        |
        v
    Obfuscated RTL Variant
        |
        v
    RTL Validation
        |
        v
    Technology Mapping
        |
        v
    Gate-Level Netlist
        |
        v
    Gate-Level Validation
        |
        v
    Gate-Level Simulation

The golden design provides the functional reference for validation, while
each obfuscated variant represents a structurally modified implementation
configured with a corresponding key.

---

## Design Abstractions

OBFU-Suite provides benchmark artifacts at two design abstractions:

### RTL Level

The RTL-level benchmarks contain obfuscated Verilog representations generated
using the prescribed obfuscation methodologies.

Each variant is validated for:

1. RTL synthesizability
2. Authorized-key functional correctness
3. Incorrect-key functional distinguishability

### Gate Level

Validated RTL variants are transformed into technology-mapped gate-level
netlists using the prescribed RTL-to-gate-level synthesis flow.

The gate-level artifacts enable:

- Gate-level structural analysis
- Gate-level security evaluation
- Cross-abstraction attack studies
- Evaluation of synthesis-induced structural transformations

---

## Obfuscation Coverage

The suite provides benchmark variants across multiple obfuscation coverage
levels.

Typical coverage configurations include:

| Coverage | Description |
|----------|-------------|
| 25% | Low obfuscation coverage |
| 50% | Medium obfuscation coverage |
| 75% | High obfuscation coverage |
| 100% | Full obfuscation coverage |

The exact available coverage levels depend on the benchmark and
obfuscation methodology.

---

## Key Configurations

OBFU-Suite provides configurable key settings associated with the selected
obfuscation methodology.

Key configurations are provided together with the corresponding benchmark
variants to enable controlled evaluation of:

- Key-dependent behavior
- Key-space characteristics
- Security vulnerabilities
- Attack effectiveness
- Generalization across variants

---

## Benchmark Domains

The suite contains representative benchmarks from multiple application
domains, including:

- Signal Processing
- Image Processing
- Video Processing
- Computer Graphics

The benchmark collection is intended to provide structural and functional
diversity rather than being restricted to a single application class.

---

## Validation Methodology

Every generated benchmark variant is subjected to an automated validation
pipeline before release.

### 1. RTL Synthesis Validation

Each generated obfuscated RTL variant is processed using the prescribed
Vivado synthesis environment.

A variant is retained only if it successfully completes the prescribed
synthesis flow.

Variants that fail synthesis are automatically rejected.

### 2. Gate-Level Netlist Validation

The validated RTL variants are converted into technology-mapped gate-level
netlists using the prescribed Yosys--ABC synthesis flow and the target
standard-cell library.

The generated gate-level netlists are independently checked using the
prescribed Quartus Prime Lite environment.

Netlists that fail the prescribed compilation/synthesis flow are excluded
from the released gate-level benchmark set.

### 3. RTL Simulation Validation

The obfuscated RTL variant is simulated against the corresponding golden
RTL design.

Two conditions are evaluated:

#### Authorized Key

The obfuscated design must reproduce the golden design output for the
prescribed validation stimuli.

#### Incorrect Keys

Representative incorrect keys must produce at least one observable output
deviation from the golden design for the prescribed distinguishing stimuli.

Variants that fail either condition are rejected.

### 4. Gate-Level Simulation Validation

The corresponding golden and obfuscated gate-level representations are
simulated using identical input stimuli and key configurations.

The following conditions are verified:

- Authorized key: obfuscated gate-level output must match the golden
  gate-level output.
- Incorrect key: at least one observable output deviation must be exposed.

This additional validation verifies that the intended functional and
key-dependent behavior is preserved after RTL-to-gate-level synthesis.

---

## RTL-to-Gate-Level Flow

The gate-level artifacts are generated using the following synthesis flow:

    Obfuscated RTL
          |
          v
    Logic Synthesis
          |
          v
    ABC Technology Mapping
          |
          v
    45-nm Standard-Cell Library
          |
          v
    Technology-Mapped
    Gate-Level Netlist

The resulting gate-level Verilog files contain technology-mapped
standard-cell instances from the specified library.

---

## Example Gate-Level Cells

Depending on the benchmark, the technology-mapped netlists may contain
standard-cell instances such as:

- INV_X1
- AND2_X1
- OR2_X1
- XOR2_X1
- XNOR2_X1
- NAND2_X1
- NOR2_X1
- Sequential standard cells

The exact cell composition depends on the synthesized benchmark and the
target library.

---

## Repository Structure

The repository is organized to separate benchmark sources, generated
variants, gate-level artifacts, and supporting scripts.

A typical organization is:

    OBFU-Suite/
    |
    +-- benchmarks/
    |   +-- RTL/
    |   +-- gate_level/
    |
    +-- obfuscation/
    |   +-- methodology_1/
    |   +-- methodology_2/
    |
    +-- configurations/
    |
    +-- scripts/
    |   +-- generation/
    |   +-- synthesis/
    |   +-- validation/
    |   +-- simulation/
    |
    +-- documentation/
    |
    +-- README.md
    +-- LICENSE

The exact directory organization may vary with the released version.

---

## Benchmark Naming

Each benchmark variant maintains a consistent identifier across the RTL and
gate-level representations.

For example:

    Benchmark_ID
        |
        +-- Obfuscated RTL Variant
        |
        +-- Technology-Mapped Gate-Level Netlist

This one-to-one correspondence provides traceability between design
abstractions and supports reproducible cross-abstraction experiments.

---

## Reproducibility

OBFU-Suite is designed to support reproducible hardware-security research.

The release provides the benchmark artifacts together with the associated
configuration information and generation/validation resources required to
reproduce the reported benchmark organization.

The recommended experimental setup uses the same:

- Benchmark configuration
- Obfuscation configuration
- Key configuration
- Obfuscation coverage
- Synthesis environment
- Standard-cell library
- Validation configuration

used for the released benchmark artifacts.

---

## Recommended Use Cases

OBFU-Suite can be used for research on:

### Hardware Obfuscation

- Logic obfuscation
- RTL obfuscation
- HLS/RTL security
- Key-based hardware protection

### Attack Evaluation

- Structural attacks
- Key-recovery attacks
- Functional attacks
- Machine-learning-based attacks
- Deep-learning-based attacks

### Cross-Abstraction Security

- RTL-to-gate-level security analysis
- Synthesis-induced information leakage
- Gate-level structural analysis of RTL-protected designs
- Cross-abstraction attack scenarios

### Benchmarking

- Attack-versus-defense comparison
- Obfuscation-strength evaluation
- Generalization studies
- Reproducibility studies
- Security evaluation across different design abstractions

---

## Tools and Environment

The benchmark-generation and validation flow uses the following tools and
resources, depending on the benchmark-generation stage:

| Tool / Resource | Purpose |
|-----------------|---------|
| Vivado 2026.1 | RTL synthesis validation |
| Yosys | RTL synthesis and logic processing |
| ABC | Logic optimization and technology mapping |
| Nangate 45-nm Library | Technology mapping |
| Quartus Prime Lite | Independent gate-level validation |
| ModelSim | Gate-level / simulation validation |
| Python | Automation and orchestration |
| TCL | Simulation and tool-flow automation |

Specific tool versions and configurations used for individual experiments
are documented with the corresponding benchmark release.

---

## Release

The current benchmark release is available at:

https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite

The release contains the benchmark artifacts and associated resources
required for the corresponding benchmark version.

---

## Citation

If you use OBFU-Suite in your research, please cite:

```bibtex
@misc{OBFUSuite,
  author       = {Dara, Srinivasa Rao and Roy, Dipanjan and Kavati, Ilaiah},
  title        = {{OBFU-Suite}: An Obfuscation Benchmark for Unified {HLS/RTL} and Gate-Level Security Assessment},
  year         = {2026},
  howpublished = {\url{https://github.com/Srinivassa/OBFU-Suite/releases/tag/OBFU-Suite}},
  note         = {GitHub benchmark release}
}
