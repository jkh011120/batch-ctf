---
name: batch-ctf
description: Batch CTF solver - scans current directory for all challenge folders, spawns parallel agents to solve each one simultaneously. Supports all categories (pwn, reverse, web, crypto, forensics, misc, etc.) with auto-detection. Produces per-challenge writeups and a final summary report.
license: MIT
compatibility: Requires Claude Code with bash, Python 3, pwntools, and internet access. Orchestrates solve-challenge and ctf-* skills.
allowed-tools: Bash Read Write Edit Glob Grep Agent Task WebFetch WebSearch Skill
metadata:
  user-invocable: "true"
  argument-hint: "[challenge_dir] [--flag-format FLAG{...}] [--jobs N]"
---

# Batch CTF Solver

You are a CTF competition orchestrator. Your job is to solve **all** challenges in the current directory **in parallel**, producing writeups and collecting flags.

## Workflow

### Phase 1: Discovery

Scan the current working directory to identify challenge folders and files.

```bash
# List all items in CWD
ls -la
# Identify challenge folders (each subfolder = one challenge)
# Also check for standalone files that might be challenges themselves
file *
```

**Challenge detection rules:**
1. Each **subdirectory** is treated as one challenge
2. A standalone binary/archive with no folder is also a challenge — create a working dir for it
3. Look inside each folder for clues:
   - `docker-compose.yml`, `Dockerfile` → likely pwn or web
   - `*.py`, `*.sage`, `*.txt` with numbers → likely crypto
   - `*.pcap`, `*.raw`, `*.E01`, `*.mem`, `*.vmem` → likely forensics
   - `target.txt` or `url.txt` → web (blackbox), read the file for target URL
   - Source code (`*.php`, `*.js`, `*.go`, `*.java`, etc.) → web (whitebox)
   - ELF/PE/Mach-O binary → reverse or pwn (check if remote service info exists)
   - `*.apk`, `*.hap` → mobile reverse engineering
   - `*.wasm` → web assembly reverse
   - `flag_format.txt` or challenge description → note the flag format
   - `*.pdf`, `*.png`, `*.jpg`, `*.bmp`, `*.wav`, `*.mp3` → forensics/stego
   - `*.sol`, `*.vy` → blockchain/web3
4. Check for `README.md`, `description.txt`, or `challenge.txt` for metadata (points, category hints, author)

### Phase 1.5: Prior Writeup Research

Before solving, search for similar challenges online to inform strategy:

```bash
# For each challenge, search for prior writeups
# Use challenge name, file hashes, or unique strings as search terms
```

- Use **WebSearch** to search: `"challenge_name" CTF writeup` or unique strings found in the binary/source
- If the challenge appears to be a known/recycled challenge, use the writeup as a reference
- Do NOT blindly copy — adapt the approach, as flags and small details often change
- This step is especially valuable for crypto and misc categories where the technique matters more than the specific values

### Phase 2: Classification & Pre-processing

For each challenge, determine its category and prepare the environment.

**Auto-detection** — analyze file types, keywords, service behavior, and content. Do NOT hardcode categories — detect them.

**Difficulty estimation** — assign each challenge a difficulty score (1-5) based on:
- File complexity (binary size, number of source files, obfuscation level)
- Protection level (checksec results, anti-debug, packing)
- Challenge points if available from metadata
- Number of files and moving parts

**Priority ordering:**
- Solve easiest challenges first (score 1-2) — quick wins for flags
- Medium challenges next (score 3)
- Hard challenges last (score 4-5) — allocate more agent resources and retries

**Isolation rules for parallel agents:**
- Every agent MUST use the **challenge directory name** as a unique prefix for all shared resources
- Docker image tag: `batch_ctf_<challenge_name>` (not generic names like `chall_name`)
- Docker container name: `batch_ctf_<challenge_name>_tmp` (not `tmp_chall`)
- Ghidra project directory: `/tmp/ghidra_<challenge_name>_$$` (use PID `$$` for extra uniqueness)
- Temp files: always write inside the challenge directory or use `/tmp/<challenge_name>_*`
- This prevents file system and Docker name collisions when agents run in parallel

**Category-specific pre-processing:**

#### PWN challenges
- Run `checksec` on the binary
- Identify architecture: `file ./binary` and `readelf -h ./binary`
- If `Dockerfile` or `docker-compose.yml` exists:
  ```bash
  # IMPORTANT: Use challenge-specific names to avoid collisions with parallel agents
  CHALL_NAME=$(basename $(pwd))
  DOCKER_TAG="batch_ctf_${CHALL_NAME}"
  DOCKER_CONTAINER="batch_ctf_${CHALL_NAME}_tmp"

  # Build and extract libc/ld from container
  docker build -t "$DOCKER_TAG" .
  docker create --name "$DOCKER_CONTAINER" "$DOCKER_TAG"
  # Try multiple libc paths (varies by distro)
  for libpath in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib /usr/lib; do
    docker cp "$DOCKER_CONTAINER":$libpath/libc.so.6 ./libc.so.6 2>/dev/null && break
  done
  for ldpath in /lib/x86_64-linux-gnu /lib64 /lib; do
    docker cp "$DOCKER_CONTAINER":$ldpath/ld-linux-x86-64.so.2 ./ld-linux-x86-64.so.2 2>/dev/null && break
  done
  docker rm "$DOCKER_CONTAINER"
  docker rmi "$DOCKER_TAG" 2>/dev/null  # cleanup image to save disk
  # Patch binary with correct libc/ld
  patchelf --set-interpreter ./ld-linux-x86-64.so.2 --set-rpath . ./binary_name
  ```
- Extract libc version and find one_gadget:
  ```bash
  strings libc.so.6 | grep "GNU C Library"
  one_gadget libc.so.6
  ```

**PWN 5-Step Pipeline:**

**Step 1 — Binary Analysis & Bug Hunting (`bugs.md`)**

Use the best available decompilation tool in this priority order:

**Option A: IDA Pro MCP (best quality, if available)**
- Invoke `/binary-analyze` or `/binary-recon` skill to perform full binary analysis
- This provides: function index, scored candidates, decompiled output, xrefs, call graphs
- Use IDA's decompilation for accurate type recovery and control flow analysis

**Option B: Ghidra Headless (good quality, free)**
```bash
# IMPORTANT: Use challenge-specific project dir to avoid collisions with parallel agents
GHIDRA_HOME=${GHIDRA_HOME:-/opt/ghidra}
CHALL_NAME=$(basename $(pwd))
PROJECT_DIR="/tmp/ghidra_${CHALL_NAME}_$$"
mkdir -p "$PROJECT_DIR"
BINARY=$(readlink -f ./binary_name)

# Run headless analysis with decompilation
$GHIDRA_HOME/support/analyzeHeadless "$PROJECT_DIR" "proj_${CHALL_NAME}" \
  -import "$BINARY" \
  -postScript DecompileAllFunctions.java \
  -postScript ExportFunctionSignatures.java \
  -scriptPath $GHIDRA_HOME/Ghidra/Features/Decompiler/ghidra_scripts \
  -deleteProject \
  2>&1 | tee ghidra_analysis.log

# If custom decompile script not available, use built-in export
$GHIDRA_HOME/support/analyzeHeadless "$PROJECT_DIR" "proj_${CHALL_NAME}" \
  -import "$BINARY" \
  -postScript ExportCCode.java ./decompiled_${CHALL_NAME}.c \
  -deleteProject

# Cleanup temp project dir
rm -rf "$PROJECT_DIR"
```

**Option C: objdump + strings (fallback)**
```bash
objdump -d ./binary_name > disasm.txt
objdump -t ./binary_name > symbols.txt
strings -n 6 ./binary_name > strings.txt
```

After decompilation (any method):
- Run `checksec`, analyze all protections
- Identify ALL vulnerabilities (not just one): BOF, format string, heap bugs, race conditions, integer overflow, UAF, type confusion, off-by-one, double free, etc.
- Map all input vectors: stdin, argv, environment, files, network
- Document each bug in `bugs.md`:
  ```markdown
  # Bug Report: [challenge_name]

  ## Binary Info
  - Arch: x86_64 / i386 / ARM / MIPS
  - Protections: [checksec output]
  - Decompiler used: IDA Pro / Ghidra / manual

  ## Bug 1: [type, e.g. Heap Buffer Overflow]
  - **Location**: function_name+offset (source line if available)
  - **Root Cause**: [why the bug exists]
  - **Trigger**: [exact input/sequence to trigger]
  - **Impact**: [what primitive it gives — arbitrary write, leak, control flow hijack, etc.]
  - **Proof**:
    ```python
    # Minimal code to trigger/demonstrate the bug
    from pwn import *
    p = process('./binary')
    p.sendline(b'A' * 0x100)  # triggers crash at ...
    ```

  ## Bug 2: ...
  ```

**Step 2 — Exploitation Strategy (`exploit_plan.md`)**
- For each bug (or combination of bugs), describe the exploitation path:
  ```markdown
  # Exploitation Plan: [challenge_name]

  ## Strategy
  [Overview: e.g. "Leak libc via format string (Bug 1) → overwrite __free_hook via heap overflow (Bug 2)"]

  ## Step-by-step
  1. **Leak**: Use Bug 1 to leak libc base — send format string `%p.%p.%p...`, parse offset N for libc address
  2. **Compute**: Calculate system() and "/bin/sh" from leaked base
  3. **Overwrite**: Use Bug 2 to corrupt tcache fd → allocate chunk at __free_hook → write system
  4. **Trigger**: Free a chunk containing "/bin/sh" → shell

  ## Mitigations to Bypass
  - ASLR: defeated by leak in Step 1
  - Full RELRO: use __free_hook instead of GOT
  - Stack canary: not relevant (heap-based attack)

  ## Useful Gadgets
  - one_gadget offsets: [from one_gadget output]
  - ROP gadgets: [from ROPgadget/ropper output]
  ```

**Step 3 — Invoke `/ctf-pwn` for Review (if available)**
- Feed the binary + `bugs.md` + `exploit_plan.md` to `/ctf-pwn`
- Let it cross-check: are there missed bugs? Is the exploit strategy optimal?
- Update plan if `/ctf-pwn` finds a better path or additional vulnerabilities
- If `/ctf-pwn` is not available, self-review the plan:
  - Are there simpler exploitation paths?
  - Did we miss any vulnerabilities?
  - Is the exploit plan compatible with all active mitigations?

**Step 4 — Full Exploit Development (`exploit.py`)**
- Write the complete working exploit script based on the reviewed plan
- Must handle:
  - Remote target (read host/port from challenge info or docker-compose)
  - Local testing with patched binary (patchelf'd libc/ld)
  - Proper `#!/usr/bin/env python3` and `from pwn import *`
- Include helpful debugging:
  ```python
  #!/usr/bin/env python3
  from pwn import *
  import sys

  context.binary = elf = ELF('./binary_name')
  libc = ELF('./libc.so.6', checksec=False) if os.path.exists('./libc.so.6') else None

  def conn():
      if args.REMOTE:
          return remote('host', port)
      elif args.GDB:
          return gdb.debug(elf.path, gdbscript='''
              b *main
              c
          ''')
      else:
          return process(elf.path)

  p = conn()
  # ... exploit logic ...
  p.interactive()
  ```

**Step 5 — Debug & Verify (with Retry Loop)**
- Run the exploit against the LOCAL patched binary first:
  ```bash
  python3 exploit.py LOCAL
  ```
- If it fails, enter the **Automated Debug Loop** (max 5 iterations):
  1. **Capture crash info**: run with `GDB` mode or parse core dump
     ```bash
     # Run with GDB script to capture crash state
     python3 -c "
     from pwn import *
     context.binary = ELF('./binary_name')
     p = gdb.debug('./binary_name', '''
       c
       bt
       info registers
       x/32gx \$rsp
       quit
     ''')
     # ... send exploit payload ...
     " 2>&1 | tee crash_log.txt
     ```
  2. **Analyze crash**: parse registers, stack state, identify root cause
  3. **Fix exploit**: adjust offsets, padding, alignment, gadget addresses
  4. **Re-test**: run exploit again
  5. **If still failing after 3 iterations**: try alternative exploitation strategy from `exploit_plan.md`
  6. **If all strategies exhausted**: try completely different approach (e.g., switch from ROP to ret2dlresolve, format string to GOT overwrite)
- Then run against remote (if service is available):
  ```bash
  python3 exploit.py REMOTE
  ```
- **The exploit MUST actually produce a shell or flag** — not just a plan

#### Reverse Engineering challenges

**Analysis pipeline:**

1. **Initial triage**:
   ```bash
   file ./binary
   strings -n 8 ./binary | head -100
   checksec ./binary 2>/dev/null
   ```

2. **Decompilation** (same priority as PWN: IDA Pro MCP → Ghidra Headless → manual):

   **Ghidra Headless for Reverse:**
   ```bash
   # IMPORTANT: Use challenge-specific paths to avoid collisions with parallel agents
   GHIDRA_HOME=${GHIDRA_HOME:-/opt/ghidra}
   CHALL_NAME=$(basename $(pwd))
   PROJECT_DIR="/tmp/ghidra_${CHALL_NAME}_$$"
   mkdir -p "$PROJECT_DIR"

   # Full analysis with all analyzers enabled
   $GHIDRA_HOME/support/analyzeHeadless "$PROJECT_DIR" "rev_${CHALL_NAME}" \
     -import ./binary \
     -postScript DecompileAllFunctions.java \
     -postScript FindCryptoConstants.java \
     -deleteProject \
     2>&1 | tee ghidra_output.log

   rm -rf "$PROJECT_DIR"
   ```

   **IDA Pro MCP for Reverse:**
   - Invoke `/binary-recon` for function indexing and scoring
   - Invoke `/binary-triage` for high-score function analysis
   - Invoke `/binary-deep` for detailed vulnerability/logic analysis

3. **Special binary types**:
   - **Go binaries**: look for `main.main`, recover function names from `.gopclntab`
   - **Rust binaries**: demangle symbols, look for `main::main`
   - **Swift/Kotlin**: check for runtime metadata
   - **.NET/C#**: use `monodis` or `ilspy` for decompilation
   - **Python bytecode (.pyc)**: use `uncompyle6` or `decompyle3`
     ```bash
     pip install uncompyle6 2>/dev/null
     uncompyle6 challenge.pyc > decompiled.py
     ```
   - **Java (.class/.jar)**: use `jadx` or `cfr`
     ```bash
     jadx -d output/ challenge.jar 2>/dev/null || \
     java -jar /opt/cfr.jar challenge.jar > decompiled.java
     ```
   - **APK (Android)**: use `jadx` for Java, `Blutter` for Flutter/Dart AOT
     ```bash
     jadx -d apk_output/ challenge.apk
     # For Flutter apps:
     python3 blutter.py libapp.so output_dir/
     ```
   - **WASM**: use `wasm-decompile` or `wasm2c`
     ```bash
     wasm-decompile challenge.wasm -o decompiled.dcmp
     ```

4. **Anti-analysis detection & bypass**:
   ```bash
   # Check for common anti-debug
   strings ./binary | grep -iE "ptrace|debugger|gdb|strace|ltrace|SIGTRAP"
   # Check for packing
   entropy=$(python3 -c "
   import math, collections
   data = open('./binary','rb').read()
   freq = collections.Counter(data)
   entropy = -sum((c/len(data)) * math.log2(c/len(data)) for c in freq.values())
   print(f'{entropy:.2f}')
   ")
   # entropy > 7.5 suggests packing — try upx -d or manual unpacking
   upx -d ./binary -o ./binary_unpacked 2>/dev/null
   ```

5. **CRITICAL: Fake flag detection** — modern CTFs embed decoy flags
   - After finding any flag candidate:
     1. Verify it matches the expected flag format
     2. Check if the flag is from a trivial path (strings, .rodata) — likely fake
     3. Trace the ACTUAL validation path to the FINAL comparison
     4. If multiple candidates found, validate each against the real check logic
   - Continue searching even after finding one candidate

6. **Constraint solving** for key/flag validation:
   ```python
   # Use Z3 for flag validation reversal
   from z3 import *
   flag = [BitVec(f'f{i}', 8) for i in range(flag_len)]
   s = Solver()
   # Add constraints from decompiled validation logic
   # s.add(flag[0] == ord('f'))
   # ...
   if s.check() == sat:
       m = s.model()
       result = ''.join(chr(m[f].as_long()) for f in flag)
       print(f"Flag: {result}")
   ```

7. **Dynamic analysis** when static analysis is insufficient:
   ```bash
   # Trace syscalls
   strace -f ./binary 2>&1 | tee strace.log
   # Trace library calls
   ltrace -f ./binary 2>&1 | tee ltrace.log
   # Run with controlled input
   echo "test_input" | ./binary
   ```

#### Web challenges (Whitebox)
- Read ALL source code files first
- Map the attack surface (routes, auth, input points, middleware)
- Search for known CVEs in dependencies:
  ```bash
  # Check package versions
  cat package.json 2>/dev/null    # Node.js
  cat requirements.txt 2>/dev/null # Python
  cat composer.json 2>/dev/null    # PHP
  cat go.mod 2>/dev/null           # Go
  cat pom.xml 2>/dev/null          # Java
  cat Gemfile.lock 2>/dev/null     # Ruby
  ```
- Use **WebSearch** to find 1-day exploits for identified versions
- Check for common vulnerability patterns:
  - SSTI: look for template rendering with user input
  - SQLi: look for string concatenation in queries
  - SSRF: look for user-controlled URLs in fetch/request calls
  - Path traversal: look for user input in file paths
  - Deserialization: look for pickle, yaml.load, unserialize, ObjectInputStream
  - Prototype pollution: look for deep merge/extend with user input
  - JWT: check algorithm confusion, none algorithm, weak secrets
- Identify vulnerability chain and obtain flag

#### Web challenges (Blackbox)
- Read `target.txt` or `url.txt` for the target URL
- **Recon phase**:
  ```bash
  # Technology fingerprinting
  curl -sI http://target/ | head -30
  curl -s http://target/ | head -100

  # Directory fuzzing
  ffuf -u http://target/FUZZ -w /usr/share/wordlists/dirb/common.txt -mc 200,301,302,403 -t 50 2>/dev/null || \
  gobuster dir -u http://target/ -w /usr/share/wordlists/dirb/common.txt 2>/dev/null || \
  # Fallback: manual common paths
  for path in robots.txt .git/HEAD .env admin login api swagger.json graphql; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://target/$path")
    echo "$path -> $code"
  done

  # Check for exposed .git
  curl -s http://target/.git/HEAD && echo "GIT EXPOSED — dump with git-dumper"
  ```
- Test common vulnerability classes systematically:
  1. Authentication bypass (default creds, SQLi in login)
  2. IDOR / access control
  3. SSTI (`{{7*7}}`, `${7*7}`)
  4. XSS (reflected, stored, DOM)
  5. SQL injection (error-based, blind, time-based)
  6. Command injection (`;id`, `|id`, `` `id` ``)
  7. File upload bypass
  8. SSRF
  9. XXE
- Use WebSearch for 1-day if tech stack is identified

#### Crypto challenges
- **Identify the cryptosystem**:
  ```bash
  # Look for crypto-related imports and patterns in source
  grep -rE "AES|RSA|ECC|DES|SHA|MD5|HMAC|CBC|GCM|CTR|ECB|ECDSA|EdDSA" . 2>/dev/null
  grep -rE "from Crypto|import hashlib|from sage|import gmpy2" . 2>/dev/null
  # Check for large numbers (RSA modulus, etc.)
  grep -rE "[0-9]{50,}" . 2>/dev/null
  ```
- **Common attack patterns**:
  - RSA: small e + large message → Coppersmith; shared modulus → common factor; Wiener's for large e/small d; Hastad's broadcast; Franklin-Reiter related message
  - AES-CBC: padding oracle, bit-flipping
  - AES-ECB: block reordering, byte-at-a-time
  - AES-GCM: nonce reuse → key recovery
  - Stream cipher: known plaintext XOR, nonce reuse
  - Hash: length extension, collision (birthday), rainbow tables
  - PRNG: MT19937 state recovery from 624 outputs, LCG prediction
  - Elliptic curve: invalid curve, small subgroup, MOV attack, Smart's attack
  - Lattice: LLL reduction for knapsack, CVP for LWE
- **Use SageMath when needed**:
  ```bash
  sage -c "
  # Example: RSA with small factors
  n = <modulus>
  # Try factoring
  print(factor(n))
  "
  ```
- **Use WebSearch** for known crypto challenge patterns

#### Forensics challenges
- **Identify evidence type**:
  ```bash
  file *
  # Check for disk images, memory dumps, packet captures
  ```
- **Memory forensics** (Volatility 3):
  ```bash
  vol3 -f memory.dmp windows.info 2>/dev/null
  vol3 -f memory.dmp windows.pslist 2>/dev/null
  vol3 -f memory.dmp windows.filescan 2>/dev/null
  vol3 -f memory.dmp windows.cmdline 2>/dev/null
  vol3 -f memory.dmp windows.hashdump 2>/dev/null
  # Linux memory:
  vol3 -f memory.dmp linux.bash 2>/dev/null
  vol3 -f memory.dmp linux.pslist 2>/dev/null
  ```
- **Network forensics** (PCAP):
  ```bash
  # Extract conversations and protocols
  tshark -r capture.pcap -q -z conv,tcp 2>/dev/null
  tshark -r capture.pcap -q -z io,phs 2>/dev/null
  # Export HTTP objects
  tshark -r capture.pcap --export-objects http,exported_files/ 2>/dev/null
  # Look for credentials, flags in cleartext
  tshark -r capture.pcap -Y "http || ftp || smtp || telnet" -T fields -e data 2>/dev/null
  # DNS exfiltration check
  tshark -r capture.pcap -Y "dns" -T fields -e dns.qry.name 2>/dev/null
  ```
- **Steganography**:
  ```bash
  # Image stego
  exiftool image.* 2>/dev/null           # metadata
  binwalk image.* 2>/dev/null             # embedded files
  steghide extract -sf image.jpg -p "" 2>/dev/null  # try empty password
  zsteg image.png 2>/dev/null             # PNG/BMP LSB stego
  stegsolve                                # visual analysis (if GUI available)
  # Audio stego
  sox audio.wav -n spectrogram -o spec.png 2>/dev/null  # spectrogram
  ```
- **Disk forensics**:
  ```bash
  # Mount disk image
  fdisk -l disk.img 2>/dev/null
  mmls disk.img 2>/dev/null               # partition layout
  fls -r disk.img 2>/dev/null             # list files (including deleted)
  icat disk.img <inode> > recovered_file   # recover specific file
  # Alternatively
  7z x archive.* 2>/dev/null              # extract archives
  binwalk -e firmware.bin 2>/dev/null      # extract firmware
  ```

#### Misc challenges
- **Jail/sandbox escapes**:
  ```python
  # Python jail common bypasses
  # Check what's blocked, then try:
  __import__('os').system('sh')
  eval(chr(95)*2+'import'+chr(95)*2+'("os").system("sh")')
  breakpoint()  # drops to pdb → os.system('sh')
  ```
- **Encoding puzzles**: try base64, base32, base85, hex, rot13, morse, braille, binary
- **QR codes / barcodes**:
  ```bash
  zbarimg qr.png 2>/dev/null
  ```
- **Esoteric languages**: brainfuck, whitespace, ook, piet, malbolge — identify and use appropriate interpreter
- **Z3 constraint solving** for logic puzzles
- **DNS challenges**:
  ```bash
  dig @server challenge.domain ANY
  dig @server challenge.domain TXT
  dig @server challenge.domain AXFR  # zone transfer
  ```

### Phase 3: Parallel Execution

**Launch one Agent per challenge**, all in parallel:

```
# Sort challenges by estimated difficulty (easiest first)
sorted_challenges = sort(discovered_challenges, key=difficulty_score)

For each challenge_dir in sorted_challenges:
    spawn Agent:
        1. cd into challenge_dir
        2. Run Phase 1.5 (prior writeup research) for this specific challenge
        3. Apply category-specific pre-processing (Phase 2)
        4. Attempt to solve the challenge using category-specific techniques
        5. If solve fails → enter Retry Loop (Phase 3.5)
        6. Collect the flag (or document progress if unsolved)
        7. Write writeup (Phase 4)
```

**Parallelism rules:**
- Launch ALL agents simultaneously — do not wait for one to finish before starting another
- Each agent works independently in its own challenge directory
- Use `run_in_background: true` for all agents except the last batch if there are many
- If there are more than 10 challenges, batch them in groups of 10

### Phase 3.5: Retry Loop (on failure)

When a challenge agent fails to solve on first attempt:

1. **Analyze failure reason**:
   - Crash/segfault → debug with GDB, fix offsets
   - Wrong output → re-analyze logic, check for off-by-one
   - Timeout → optimize approach or try different technique
   - Category misdetection → reclassify and retry with correct category skill

2. **Strategy rotation** (try up to 3 different approaches):
   - Attempt 1: Primary detected technique
   - Attempt 2: Alternative technique (e.g., if ROP failed, try ret2libc or format string)
   - Attempt 3: Completely different approach (e.g., if static analysis failed, try dynamic/fuzzing)

3. **Category re-evaluation**:
   - If a challenge was classified as "reverse" but has a network service → re-try as "pwn"
   - If "crypto" solve fails → check if it's actually "misc" with encoding tricks
   - If "web" blackbox yields nothing → search harder for source code leaks (.git, .svn, backup files)

4. **Escalation**:
   - After 3 failed attempts, mark as UNSOLVED with detailed progress notes
   - Document: what was tried, what worked partially, where it got stuck
   - Include any partial flags, leaked data, or promising leads for manual follow-up

### Phase 4: Writeup Generation

**Every challenge MUST have a writeup**, regardless of whether it was solved.

Each agent writes `writeup.md` inside its challenge directory with this structure:

```markdown
# [Challenge Name]

## Category
[auto-detected category]

## Difficulty
[estimated difficulty 1-5 and reasoning]

## Description
[challenge description if available]

## Analysis

### Initial Recon
[what was found during initial analysis]

### Prior Research
[any similar challenges or writeups found online]

### Vulnerability / Technique
[identified vulnerability or solving technique]

### Exploitation Steps
[step-by-step how the challenge was solved]

## Solution

### Key Code / Commands
```[language]
[the exploit code, solve script, or key commands used]
```

### Flag
`FLAG{...}` or `UNSOLVED — [reason and progress so far]`

## Retry Log
[if retries were needed: what failed, what was changed, what eventually worked]

## Notes
[any interesting observations, alternative approaches, or things learned]
```

**For unsolved challenges:** document what was tried, what was found, and where you got stuck. This is valuable for manual follow-up.

### Phase 5: Final Report

After all agents complete, generate `REPORT.md` in the root directory:

```markdown
# CTF Batch Solve Report

## Summary
- Total challenges: N
- Solved: X / N
- Categories: [breakdown]
- Estimated total points: [if point values known]

## Flags
| # | Challenge | Category | Difficulty | Flag | Status | Attempts |
|---|-----------|----------|------------|------|--------|----------|
| 1 | challenge_name | pwn | 3 | `FLAG{...}` | Solved | 1 |
| 2 | challenge_name | web | 4 | — | Unsolved | 3 |

## Unsolved Challenges
[For each unsolved: brief summary of progress, blockers, and suggested next steps for manual solving]

## Per-Challenge Writeups
- [challenge_name](./challenge_name/writeup.md)
- ...
```

## Important Rules

1. **Never skip a challenge** — attempt every single one
2. **Never stop at first flag candidate** in reverse challenges — verify it's not fake
3. **Always write writeups** — even for unsolved challenges
4. **Respect challenge isolation** — each agent works only in its own directory
5. **Collect libc/ld from Docker** whenever Dockerfile is present for pwn
6. **Search for 1-day CVEs** when known software versions are identified in web challenges
7. **Auto-detect everything** — don't assume categories, detect them from files and context
8. **Retry before giving up** — use the Phase 3.5 retry loop, try at least 3 approaches
9. **Use the best decompiler available** — IDA Pro MCP > Ghidra Headless > manual disassembly
10. **Search for prior writeups** — don't reinvent the wheel for known challenge types
11. **Reverse shell = ASK USER** — when exploitation requires a reverse shell (web RCE, pwn shell callback, etc.), do NOT set one up automatically. Instead:
    - Prepare the full exploit payload/script ready to fire
    - **STOP and ask the user** to provide:
      - Their listener IP and port
      - Whether they have `nc -lvnp` or other listener ready
      - Any network constraints (NAT, VPN, etc.)
    - Only after user confirms, inject the reverse shell payload
    - This applies to ALL categories: web (RCE → revshell), pwn (remote shell), misc (jail → shell escape), etc.

## Flag Formats

- Default: `flag{...}`, `FLAG{...}`
- Check for `flag_format.txt` or challenge descriptions for custom formats
- Common CTF-specific: `codegate{...}`, `CTF{...}`, `HTB{...}`, etc.
- If `$ARGUMENTS` specifies a flag format, use that

## Challenge

$ARGUMENTS
