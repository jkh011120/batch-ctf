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
  └─ Agent isolation: unique Docker/Ghidra names per challenge

Phase 3: Parallel Execution
  └─ Spawn one Agent per challenge (all in parallel)
  └─ Each agent applies category-specific solving techniques
  └─ Agents are fully isolated — no shared temp files or container names

Phase 3.5: Retry Loop (on failure)
  └─ Analyze failure → rotate strategy → retry (max 3 attempts)
  └─ Re-classify category if needed (e.g. reverse → pwn)
  └─ GDB automated debug loop for PWN (max 5 iterations)

Phase 4: Writeup Generation
  └─ Each challenge gets a writeup.md (solved or unsolved)

Phase 5: Final Report
  └─ REPORT.md with flag table, stats, and links to writeups
```

### Category-Specific Techniques

| Category | What It Does |
|----------|-------------|
| **PWN** | checksec → decompile (IDA Pro MCP / Ghidra headless) → bug hunting → exploit plan → exploit development → GDB debug loop (max 5 iterations) |
| **Reverse** | Decompile → anti-analysis bypass (packing/anti-debug detection) → fake flag detection → Z3 constraint solving → dynamic analysis (strace/ltrace). Supports Go, Rust, .NET, Python bytecode, Java, APK (Flutter/Blutter), WASM |
| **Web (whitebox)** | Read all source → map attack surface → CVE search in dependencies → vulnerability chain exploitation (SSTI, SQLi, SSRF, deserialization, prototype pollution, JWT, etc.) |
| **Web (blackbox)** | Fingerprint → directory fuzzing (ffuf/gobuster) → .git leak check → systematic vuln testing (SQLi, SSTI, SSRF, XSS, command injection, etc.) |
| **Crypto** | Identify cryptosystem → apply known attacks (RSA: Coppersmith/Wiener/Hastad, AES: padding oracle/bit-flip, ECC, PRNG: MT19937, lattice/LLL, etc.) → SageMath via Docker |
| **Forensics** | Volatility 3 for memory dumps, tshark for PCAPs (HTTP objects, DNS exfil detection), steganography (exiftool, binwalk, steghide, zsteg), disk forensics (sleuthkit: mmls/fls/icat) |
| **Misc** | Python/bash jail escapes, encoding puzzles, QR codes (zbar), DNS exploitation (zone transfer), esoteric languages, Z3 constraint solving |

### Decompilation Priority

For PWN and Reverse challenges, the best available decompiler is used automatically:

1. **IDA Pro MCP** (best) — via `/binary-analyze` skill pipeline
2. **Ghidra Headless** (good) — automated headless analysis + decompilation
3. **objdump + strings** (fallback) — manual disassembly

### Parallel Agent Isolation

When solving multiple challenges simultaneously, each agent uses unique names to prevent collisions:

- Docker images: `batch_ctf_<challenge_name>`
- Docker containers: `batch_ctf_<challenge_name>_tmp`
- Ghidra projects: `/tmp/ghidra_<challenge_name>_<PID>`
- Temp files: scoped to each challenge directory

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

### 1. Install the skill

```bash
# In your project directory:
mkdir -p .claude/skills
git clone https://github.com/jkh011120/batch-ctf.git /tmp/batch-ctf
cp -r /tmp/batch-ctf/.claude/skills/batch-ctf .claude/skills/
rm -rf /tmp/batch-ctf
```

### 2. Install system dependencies

A setup script is provided to install all required tools:

```bash
wget -O /tmp/setup.sh https://raw.githubusercontent.com/jkh011120/batch-ctf/main/setup.sh
bash /tmp/setup.sh
```

Or install manually — see [System Tools](#system-tools) below.

### 3. SageMath (for crypto challenges)

SageMath is used via Docker (no native install needed):

```bash
docker pull sagemath/sagemath
```

The skill automatically calls it as:

```bash
# Run sage code
docker run --rm -v $(pwd):/work -w /work sagemath/sagemath sage -c "print(factor(2^256-1))"

# Run sage script
docker run --rm -v $(pwd):/work -w /work sagemath/sagemath sage solve.sage
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

| Tool | Used For | Install |
|------|----------|---------|
| Python 3 + pwntools | PWN exploit development | `pip install pwntools` |
| Ghidra (headless) | Binary decompilation | [setup script](#2-install-system-dependencies) |
| GDB + pwndbg | Exploit debugging | `apt install gdb` + [pwndbg](https://github.com/pwndbg/pwndbg) |
| checksec | Binary protection analysis | `apt install checksec` |
| one_gadget | ROP gadget finding | `gem install one_gadget` |
| patchelf | Binary patching with correct libc | `apt install patchelf` |
| Docker | Libc extraction, SageMath | `apt install docker.io` |
| ffuf | Web directory fuzzing | [ffuf releases](https://github.com/ffuf/ffuf/releases) |
| tshark | PCAP analysis | `apt install tshark` |
| Volatility 3 | Memory forensics | `pip install volatility3` |
| SageMath | Crypto challenges | `docker pull sagemath/sagemath` |
| Z3 | Constraint solving | `pip install z3-solver` |
| binwalk | Firmware/stego extraction | `apt install binwalk` |
| steghide / zsteg | Steganography | `apt install steghide` / `gem install zsteg` |
| exiftool | Metadata analysis | `apt install libimage-exiftool-perl` |
| sleuthkit | Disk forensics | `apt install sleuthkit` |
| ROPgadget | ROP chain building | `pip install ROPgadget` |
| angr | Symbolic execution | `pip install angr` |

Not all tools are required — the skill uses whatever is available and falls back gracefully.

## License

MIT
