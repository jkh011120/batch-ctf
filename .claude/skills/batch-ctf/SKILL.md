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
   - `*.pcap`, `*.raw`, `*.E01` → likely forensics
   - `target.txt` or `url.txt` → web (blackbox), read the file for target URL
   - Source code (`*.php`, `*.js`, `*.go`, `*.java`, etc.) → web (whitebox)
   - ELF/PE binary → reverse or pwn (check if remote service info exists)
   - `flag_format.txt` or challenge description → note the flag format

### Phase 2: Classification & Pre-processing

For each challenge, determine its category and prepare the environment.

**Auto-detection** — use the same logic as `/solve-challenge` Step 2 (file types, keywords, service behavior). Do NOT hardcode categories — detect them.

**Category-specific pre-processing:**

#### PWN challenges
- Run `checksec` on the binary
- If `Dockerfile` or `docker-compose.yml` exists:
  ```bash
  # Build and extract libc/ld from container
  docker build -t chall_name .
  docker create --name tmp_chall chall_name
  docker cp tmp_chall:/lib/x86_64-linux-gnu/libc.so.6 ./libc.so.6 2>/dev/null || \
  docker cp tmp_chall:/usr/lib/x86_64-linux-gnu/libc.so.6 ./libc.so.6
  docker cp tmp_chall:/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ./ld-linux-x86-64.so.2 2>/dev/null || \
  docker cp tmp_chall:/lib64/ld-linux-x86-64.so.2 ./ld-linux-x86-64.so.2
  docker rm tmp_chall
  # Patch binary with correct libc/ld
  patchelf --set-interpreter ./ld-linux-x86-64.so.2 --set-rpath . ./binary_name
  ```

**PWN 5-Step Pipeline:**

**Step 1 — Bug Hunting & Documentation (`bugs.md`)**
- Run `checksec`, analyze all protections
- Reverse the binary (decompile with Ghidra headless or read source if provided)
- Identify ALL vulnerabilities (not just one): BOF, format string, heap bugs, race conditions, integer overflow, UAF, etc.
- Document each bug in `bugs.md`:
  ```markdown
  # Bug Report: [challenge_name]

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
  ```

**Step 3 — Invoke `/ctf-pwn` for Review**
- Feed the binary + `bugs.md` + `exploit_plan.md` to `/ctf-pwn`
- Let it cross-check: are there missed bugs? Is the exploit strategy optimal?
- Update plan if `/ctf-pwn` finds a better path or additional vulnerabilities

**Step 4 — Full Exploit Development (`exploit.py`)**
- Write the complete working exploit script based on the reviewed plan
- Must handle:
  - Remote target (read host/port from challenge info or docker-compose)
  - Local testing with patched binary (patchelf'd libc/ld)
  - Proper `#!/usr/bin/env python3` and `from pwn import *`

**Step 5 — Debug & Verify**
- Run the exploit against the LOCAL patched binary first:
  ```bash
  python3 exploit.py LOCAL
  ```
- If it fails, **debug with GDB**:
  ```bash
  # Attach GDB to the process spawned by pwntools
  # In exploit.py: p = gdb.debug('./binary', 'b *main+0x123\nc')
  ```
  - Inspect crash state, registers, stack
  - Fix offsets, padding, alignment issues
  - Iterate until local exploit works reliably
- Then run against remote (if service is available):
  ```bash
  python3 exploit.py REMOTE
  ```
- **The exploit MUST actually produce a shell or flag** — not just a plan

#### Reverse Engineering challenges
- **CRITICAL: Fake flag detection** — modern CTFs embed decoy flags
- After finding any flag candidate:
  1. Verify it matches the expected flag format
  2. Check if the flag is from a trivial path (strings, .rodata) — likely fake
  3. Trace the ACTUAL validation path to the FINAL comparison
  4. If multiple candidates found, validate each against the real check logic
- Continue searching even after finding one candidate

#### Web challenges (Whitebox)
- Read ALL source code files first
- Map the attack surface (routes, auth, input points)
- Search for known CVEs in dependencies:
  ```bash
  # Check package versions
  cat package.json 2>/dev/null    # Node.js
  cat requirements.txt 2>/dev/null # Python
  cat composer.json 2>/dev/null    # PHP
  cat go.mod 2>/dev/null           # Go
  cat pom.xml 2>/dev/null          # Java
  ```
- Use WebSearch to find 1-day exploits for identified versions
- Identify vulnerability chain and obtain flag

#### Web challenges (Blackbox)
- Read `target.txt` or `url.txt` for the target URL
- Perform recon: directory fuzzing, tech fingerprinting, response header analysis
- Test common vulnerability classes systematically
- Use WebSearch for 1-day if tech stack is identified

#### All other categories (crypto, forensics, osint, malware, misc)
- Auto-detected via `/solve-challenge` classification logic
- Invoke the appropriate `/ctf-*` skill
- No special pre-processing needed — the category skill handles it

### Phase 3: Parallel Execution

**Launch one Agent per challenge**, all in parallel:

```
For each challenge_dir in discovered_challenges:
    spawn Agent:
        1. cd into challenge_dir
        2. Apply category-specific pre-processing (Phase 2)
        3. Invoke /solve-challenge for the actual solving
        4. Collect the flag (or document progress if unsolved)
        5. Write writeup (Phase 4)
```

**Parallelism rules:**
- Launch ALL agents simultaneously — do not wait for one to finish before starting another
- Each agent works independently in its own challenge directory
- Use `run_in_background: true` for all agents except the last batch if there are many
- If there are more than 10 challenges, batch them in groups of 10

### Phase 4: Writeup Generation

**Every challenge MUST have a writeup**, regardless of whether it was solved.

Each agent writes `writeup.md` inside its challenge directory with this structure:

```markdown
# [Challenge Name]

## Category
[auto-detected category]

## Description
[challenge description if available]

## Analysis

### Initial Recon
[what was found during initial analysis]

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

## Flags
| # | Challenge | Category | Flag | Status |
|---|-----------|----------|------|--------|
| 1 | challenge_name | pwn | `FLAG{...}` | Solved |
| 2 | challenge_name | web | — | Unsolved |

## Unsolved Challenges
[For each unsolved: brief summary of progress and blockers]

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
8. **Reverse shell = ASK USER** — when exploitation requires a reverse shell (web RCE, pwn shell callback, etc.), do NOT set one up automatically. Instead:
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
