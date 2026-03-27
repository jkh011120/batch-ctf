# batch-ctf

Claude Code skill that scans the current directory for CTF challenge folders and spawns parallel agents to solve each one simultaneously.

## Features

- Auto-detects challenge categories (pwn, reverse, web, crypto, forensics, misc, etc.)
- Parallel solving with one agent per challenge
- Per-challenge writeup generation
- Final summary report with all flags

## Installation

```bash
# 사용할 프로젝트 디렉토리에서:
mkdir -p .claude/skills
git clone https://github.com/jkh011120/batch-ctf.git /tmp/batch-ctf
cp -r /tmp/batch-ctf/.claude/skills/batch-ctf .claude/skills/
rm -rf /tmp/batch-ctf
```

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
