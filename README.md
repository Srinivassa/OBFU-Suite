# OBFU-Suite

### An Obfuscation Benchmark for Unified HLS/RTL and Gate-Level Security Assessment

OBFU-Suite is a configurable and reproducible benchmark suite for evaluating
HLS/RTL hardware obfuscation and its security after synthesis.

It provides:

- Multiple state-of-the-art HLS/RTL obfuscation methods
- Multiple obfuscation coverage levels
- Multiple balanced key configurations
- Functionally correct and structurally diverse RTL variants
- Corresponding technology-mapped gate-level netlists
- Automated RTL and gate-level validation

OBFU-Suite is designed for hardware-security benchmarking, including
conventional, ML-, DL-, and cross-abstraction attack studies.

---

## Why OBFU-Suite?

Hardware IP is exposed to threats such as IP piracy, reverse engineering,
hardware Trojans, and malicious modifications.

Many HLS/RTL obfuscation techniques have been proposed, but researchers often
create their own datasets using different designs, keys, coverage levels, and
generation procedures.

This makes fair comparison and reproducibility difficult.

OBFU-Suite provides a common benchmark configuration and a common generation
and validation flow for HLS/RTL obfuscation.

Unlike an RTL-only dataset, OBFU-Suite also provides the corresponding
technology-mapped gate-level netlists. This enables security evaluation:

**RTL → Synthesis → Gate Level**

and supports cross-abstraction security studies.

---

## Benchmark Configuration

| Configuration | Values |
|---|---|
| Obfuscation coverage | 25%, 50%, 75%, 100% |
| Key patterns | 0101..., 1010..., 0110..., 1001... |
| Design levels | RTL + Gate Level |
| Gate technology | 45-nm standard-cell library |
| RTL synthesis | Vivado 2026.1 |
| RTL-to-gate synthesis | Yosys + ABC |
| Gate-level validation | Quartus Prime Lite |
| Simulation | ModelSim / TCL |

### Key Patterns

```text
01010101...
10101010...
01100110...
10011001...
