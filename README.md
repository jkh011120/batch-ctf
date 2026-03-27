# batch-ctf

Claude Code skill that scans the current directory for CTF challenge folders and spawns parallel agents to solve each one simultaneously.

## Features

- Auto-detects challenge categories (pwn, reverse, web, crypto, forensics, misc, etc.)
- Parallel solving with one agent per challenge
- Per-challenge writeup generation
- Final summary report with all flags

## Installation

Copy `.claude/skills/batch-ctf/` into your project's `.claude/skills/` directory.

## Dependencies

This skill invokes the following Claude Code skills at runtime:

- `/solve-challenge` — core challenge solver (required)
- `/ctf-pwn` — binary exploitation
- `/ctf-crypto` — cryptography
- `/ctf-web` — web exploitation
- `/ctf-reverse` — reverse engineering
- `/ctf-forensics` — digital forensics
- `/ctf-misc` — miscellaneous challenges
- `/ctf-malware` — malware analysis
- `/ctf-osint` — open source intelligence

Ensure these skills are installed in your environment before using `batch-ctf`.

## Usage

```
/batch-ctf [challenge_dir] [--flag-format FLAG{...}] [--jobs N]
```

## License

MIT
