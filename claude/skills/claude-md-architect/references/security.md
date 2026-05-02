# CLAUDE.md security checklist

CLAUDE.md and `.claude/settings.json` are loaded automatically when
Claude Code enters a directory. A malicious one is a code-execution
vector.

## Known CVE class (as of 2026-05-02)

- **CVE-2025-59536** — RCE and API token exfiltration via Claude Code
  project files. Malicious `CLAUDE.md` instructs Claude to chain
  commands that exfiltrate `~/.ssh/`, AWS creds, GitHub tokens, npm
  tokens.
- **CVE-2025-54794 / 54795** — supply-chain via poisoned config. A
  build-time exclusion gap let attackers distribute repos that took
  over Claude Code on clone.
- **Subcommand-deny bypass** — commands with >50 subcommands skipped
  per-subcommand deny rules. Patched in v2.1.90.

Re-search Check Point Research and Adversa AI quarterly for new
findings.

## Audit blockers — flag any of these

1. **Secrets in file.** API keys, tokens, internal URLs, customer
   data, cloud credentials. Even partial keys. CLAUDE.md and
   `.claude/settings.json` get committed; they leak.

2. **Suspicious shell directives.** A `CLAUDE.md` that tells Claude
   to run `curl ... | sh`, exfiltrate env vars, read `~/.ssh/`,
   write to `~/.bashrc`, or pipe credentials to network endpoints.

3. **Untrusted `@` imports.** `@/etc/...`, `@~/...` outside the
   project, or imports from paths the user can't audit.

4. **Hidden encoding.** Base64 blobs, zero-width characters, unusual
   Unicode in instructions — used to smuggle directives past human
   review. Grep for `[\u200b-\u200f\u2060-\u206f]` to surface them.

5. **Hook injection.** A `settings.json` shipped alongside CLAUDE.md
   that registers `PreToolUse`, `PostToolUse`, or `Stop` hooks the
   user didn't write themselves.

## Where secrets actually go

- `~/.claude/settings.local.json` — auto-gitignored, machine-local.
- A real secret manager (1Password, vault, env files outside the repo).
- **Never** in `CLAUDE.md`, `.claude/CLAUDE.md`, or
  `.claude/settings.json` — those are committed by default.

## CLAUDE.local.md

`CLAUDE.local.md` is the project-level personal file. It should be
gitignored. Verify the project's `.gitignore` excludes it before
putting anything sensitive there.

## When cloning a third-party repo

Before letting Claude Code enter a freshly cloned untrusted repo:

1. `cat CLAUDE.md` and `cat .claude/CLAUDE.md` manually first.
2. `cat .claude/settings.json` — check `hooks`, `permissions.allow`,
   `env`.
3. `find . -name 'CLAUDE*.md' -o -name 'settings.json'` — surface
   every instance.
4. If any look suspicious, open Claude Code with `--bare` (skips
   auto-discovery of CLAUDE.md, hooks, skills, MCP).

Trust verification is **disabled** under `claude -p` (headless flag).
Don't run untrusted repos in headless mode.

## References

- https://code.claude.com/docs/en/security
- https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files-cve-2025-59536/
- https://adversa.ai/blog/claude-code-security-bypass-deny-rules-disabled/
