# batch-ctf

Claude Code skill that automatically solves CTF (Capture The Flag) challenges in batch. It scans the current directory, detects challenge categories, and spawns parallel agents to solve each one simultaneously.

## How It Works

```
/batch-ctf
```

### Pipeline Overview

```
Phase 1: Discovery
  └─ Scan directory → identify challenge folders → detect file types

Phase 1.5: Prior Research
  └─ WebSearch for similar challenges / known writeups

Phase 2: Classification & Pre-processing
  └─ Auto-detect category (pwn/web/crypto/reverse/forensics/misc)
  └─ Estimate difficulty (1-5) → sort by easiest first
  └─ Category-specific setup (checksec, docker libc extract, etc.)

Phase 3: Parallel Execution
  └─ Spawn one Agent per challenge (all in parallel)
  └─ Each agent applies category-specific solving techniques

Phase 3.5: Retry Loop (on failure)
  └─ Analyze failure → rotate strategy → retry (max 3 attempts)
  └─ Re-classify category if needed (e.g. reverse → pwn)

Phase 4: Writeup Generation
  └─ Each challenge gets a writeup.md (solved or unsolved)

Phase 5: Final Report
  └─ REPORT.md with flag table, stats, and links to writeups
```

### Category-Specific Techniques

| Category | What It Does |
|----------|-------------|
| **PWN** | checksec → decompile (IDA Pro MCP / Ghidra headless) → bug hunting → exploit plan → exploit development → GDB debug loop (max 5 iterations) |
| **Reverse** | Decompile → anti-analysis bypass → fake flag detection → Z3 constraint solving. Supports Go, Rust, .NET, Python bytecode, Java, APK (Flutter/Blutter), WASM |
| **Web (whitebox)** | Read all source → map attack surface → CVE search in dependencies → vulnerability chain exploitation |
| **Web (blackbox)** | Fingerprint → directory fuzzing (ffuf/gobuster) → .git leak check → systematic vuln testing (SQLi, SSTI, SSRF, XSS, etc.) |
| **Crypto** | Identify cryptosystem → apply known attacks (Coppersmith, Wiener, padding oracle, MT19937, lattice/LLL, etc.) → SageMath integration |
| **Forensics** | Volatility 3 for memory dumps, tshark for PCAPs, steganography tools (exiftool, binwalk, steghide, zsteg), disk image recovery (mmls, fls, icat) |
| **Misc** | Python jail escapes, encoding puzzles, QR codes, DNS exploitation, esoteric languages, Z3 constraint solving |

### Decompilation Priority

For PWN and Reverse challenges, the best available decompiler is used automatically:

1. **IDA Pro MCP** (best) — via `/binary-analyze` skill pipeline
2. **Ghidra Headless** (good) — automated headless analysis + decompilation
3. **objdump + strings** (fallback) — manual disassembly

### Output Structure

After execution, your directory will look like:

```
./
├── REPORT.md                    # Summary with all flags
├── challenge_1/
│   ├── writeup.md               # Detailed writeup
│   ├── exploit.py               # Exploit script (if pwn/web)
│   ├── bugs.md                  # Bug report (if pwn)
│   └── exploit_plan.md          # Exploitation strategy (if pwn)
├── challenge_2/
│   ├── writeup.md
│   └── solve.py
└── ...
```

## Installation

```bash
# In your project directory:
mkdir -p .claude/skills
git clone https://github.com/jkh011120/batch-ctf.git /tmp/batch-ctf
cp -r /tmp/batch-ctf/.claude/skills/batch-ctf .claude/skills/
rm -rf /tmp/batch-ctf
```

## Usage

```bash
# Solve all challenges in current directory
/batch-ctf

# Specify flag format
/batch-ctf --flag-format "codegate{...}"

# Solve specific directory
/batch-ctf ./quals/

# Limit parallel agents
/batch-ctf --jobs 5
```

## Dependencies

### Required Claude Code Skills

This skill orchestrates the following skills at runtime. Install them for full functionality:

| Skill | Purpose | Required? |
|-------|---------|-----------|
| `/solve-challenge` | Core challenge solver | Required |
| `/ctf-pwn` | Binary exploitation | Recommended |
| `/ctf-crypto` | Cryptography attacks | Recommended |
| `/ctf-web` | Web exploitation | Recommended |
| `/ctf-reverse` | Reverse engineering | Recommended |
| `/ctf-forensics` | Digital forensics | Recommended |
| `/ctf-misc` | Misc challenges | Recommended |
| `/ctf-malware` | Malware analysis | Optional |
| `/ctf-osint` | OSINT techniques | Optional |
| `/binary-analyze` | IDA Pro MCP pipeline | Optional |

Without the category-specific skills, batch-ctf will still attempt to solve challenges using its built-in techniques, but accuracy may be reduced.

### System Tools

| Tool | Used For |
|------|----------|
| Python 3 + pwntools | PWN exploit development |
| Ghidra (headless) | Binary decompilation |
| checksec | Binary protection analysis |
| one_gadget | ROP gadget finding |
| patchelf | Binary patching with correct libc |
| Docker | Extracting libc from challenge containers |
| ffuf / gobuster | Web directory fuzzing |
| tshark | PCAP analysis |
| Volatility 3 | Memory forensics |
| SageMath | Crypto challenges |
| Z3 (Python) | Constraint solving |
| binwalk, steghide, zsteg | Steganography |
| GDB + pwndbg/gef | Exploit debugging |

Not all tools are required — the skill uses whatever is available and falls back gracefully.

## License

MIT
