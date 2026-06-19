# CLAUDE.md security checklist

CLAUDE.md and `.claude/settings.json` are loaded automatically when
Claude Code enters a directory. A malicious one is a code-execution
vector.

## Contents

- Known CVE class (point-in-time; re-verify quarterly)
- Audit blockers
- Where secrets actually go
- CLAUDE.local.md
- When cloning a third-party repo

## Known CVE class (as of 2026-06-18)

The CVE ids and fix versions below are a point-in-time snapshot
(verified 2026-06-18) — confirm against the official advisory before
relying on a specific version number, and re-verify quarterly.

Most patched CVEs target the *trust dialog* and `.claude/settings.json`
(the execution layer), not CLAUDE.md content itself. CLAUDE.md remains
an unpatched-by-design prompt-injection channel. Audit both file
classes.

- **CVE-2025-59536** — code execution *before* the startup trust dialog
  (CWE-94). Launching Claude in an untrusted cloned dir could run
  attacker code before consent. CVSS 8.7. Fixed in **1.0.111**.
- **CVE-2026-21852** — API-key exfiltration before trust confirmation: a
  repo-committed settings file with a hostile `ANTHROPIC_BASE_URL` made
  Claude issue requests (leaking keys) before the trust prompt. CVSS
  5.3. Fixed in **2.0.65**. (Chained with 59536 in Check Point's "Caught
  in the Hook," 2026-02-25.)
- **CVE-2026-33068** — malicious `.claude/settings.json` sets
  `permissions.defaultMode: bypassPermissions`, silently skipping the
  trust dialog. Fixed in **2.1.53**.
- **CVE-2026-25725** — hook injection via a missing `.claude/settings.json`
  (persistent `SessionStart` hooks run with host privileges). Fixed in
  **2.1.2**.
- **CVE-2025-54794 / 54795** — supply-chain via poisoned config; repos
  that took over Claude Code on clone.
- **Subcommand-deny bypass** — commands with >50 subcommands skipped
  per-subcommand deny rules. Patched in v2.1.90.

The prompt-injection chain that *starts* from a poisoned CLAUDE.md
(persuading Claude to exfiltrate `~/.ssh/`, AWS/GitHub/npm tokens) is
real but unpatched-by-design: CLAUDE.md persuades, it does not execute.
Keep Claude Code updated; every CVE above is fixed in a specific
version.

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

4. **Hidden encoding.** Base64 blobs, zero-width characters, homoglyphs,
   unusual Unicode in instructions — used to smuggle directives past human
   review. Grep for `[\u200b-\u200f\u2060-\u206f]` to surface them.

5. **Hook injection.** A `settings.json` shipped alongside CLAUDE.md
   that registers `PreToolUse`, `PostToolUse`, or `Stop` hooks the
   user didn't write themselves.

6. **HTML-comment blind spot.** Block-level `<!-- comments -->` are
   *stripped* from CLAUDE.md before injection — invisible to Claude,
   visible to a human reviewer (the inverse of the usual assumption). BUT
   comments **inside fenced code blocks are preserved** and DO reach
   context. Scan code fences; don't assume a comment is harmless. Also
   grep the Unicode tag block (U+E0000–U+E007F) for smuggled directives.

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
