---
name: gh-search
description: Searches and discovers repositories, code, issues, PRs, and commits across all of GitHub with the `gh search` CLI and read-only `gh api` calls. ALWAYS trigger when the user wants to find GitHub projects ("is there a library/tool that does X", "find popular Rust TUI repos", "what repos use this dependency", "search GitHub for"), search code across many repos ("find real-world usages of this API", "who else calls X on GitHub", "gh search code"), find issues or PRs across repositories ("has anyone reported this upstream", "find PRs that touched X", "prior art for this feature"), or size up a repo you found (its README, stars, recent activity, structure). Covers GitHub search qualifiers (stars:, language:, topic:, pushed:, in:), the 1000-result cap and how to page past it, and JSON/jq output. Read-only — never creates, edits, comments, or merges. Do NOT use to search the CURRENT local checkout (use the Grep tool for local code/text) or to create/edit/comment-on/merge issues, PRs, or releases.
allowed-tools: Bash(gh search *), Bash(gh repo view *), Bash(gh issue list *), Bash(gh pr list *), Bash(gh release list *), Bash(gh api *), Read
---

# gh-search

Find and evaluate things across **all of GitHub** — repos, code, issues, PRs, commits — using the GitHub CLI. This is for *remote discovery* ("what's out there on GitHub"), not for searching the local checkout (the built-in **Grep** tool already does that better).

## Read-only — this skill never writes

This skill only *reads* GitHub. Use these verbs only: `search`, `view`, `list`, `status`, and `api` **with GET requests** (the default; never `-X POST/PATCH/PUT/DELETE`). Never create, edit, delete, comment on, label, close, or merge issues, PRs, releases, or any other resource. If a task needs a write, stop and tell the user — don't do it under this skill.

## Pick the right subcommand

| Goal | Use |
|---|---|
| Find **repositories** by topic/language/popularity | `gh search repos` |
| Find **code** (snippets, usages, config) across repos | `gh search code` |
| Find **issues** / bug reports / discussions | `gh search issues` |
| Find **pull requests** | `gh search prs` |
| Find **commits** by message/author/hash | `gh search commits` |
| **Inspect one repo** you already found | `gh repo view`, `gh api` (GET) — see [Inspect a repo](#inspect-a-repo-you-found) |
| Search the **local checkout's** code/text | the built-in **Grep** tool — *not this skill* |

Every `gh search` subcommand accepts a free-text query, flag-style filters (`--language=go`), and raw GitHub qualifiers (`language:go`) — mix freely. **Default `--limit` is only 30** on every subcommand; set `-L` explicitly when you want a thorough scan (max 1000 — see [Limits](#limits-that-bite)).

## Discover repositories

```bash
gh search repos "vim plugin" --language=go --stars=">100" --sort=stars --limit=20
gh search repos --topic=cli --topic=rust --sort=stars            # AND of topics
gh search repos --owner=microsoft --language=typescript --archived=false
gh search repos terminal --match=name,description --pushed=">2025-01-01"   # active only
```

Return a clean shortlist instead of raw output — request JSON and format it:

```bash
gh search repos "static site generator" --language=go --sort=stars -L 15 \
  --json fullName,stargazersCount,description,pushedAt,url \
  --jq '.[] | "\(.stargazersCount)★  \(.fullName) — \(.description // "")"'
```

> **Field names are not obvious.** It is `stargazersCount` (not `stargazerCount`), `forksCount`, `pushedAt`. If a `--json` field is rejected, `gh` prints the full list of valid fields — read it and retry. Don't guess twice.

Key repo qualifiers: `stars:` `forks:` `language:` `topic:` `pushed:` `created:` `size:` `license:` `archived:` `--include-forks={false|true|only}` `--match={name|description|readme}` `--visibility`. Ranges and comparisons work: `stars:10..100`, `pushed:>2024-06-01`. Full tables in [references/qualifiers.md](references/qualifiers.md).

## Search code

```bash
gh search code "createServer" --language=js --limit=30
gh search code "boto3.client" --owner=aws --filename=*.py
gh search code "TODO" --repo=cli/cli --match=file
```

**Critical limitations** — `gh search code` runs on GitHub's *legacy* code-search engine, not the github.com UI engine:
- **No regex, no `symbol:`/`content:` qualifiers** — those exist only in the web UI. Results "might not match what is seen on github.com."
- Much stricter rate limit (≈9 requests/min). No `--sort`/`--order` — relevance only.
- Hyphens in queries are finicky; check `gh search code --help` if a query with `-` misbehaves.

When you need regex or the modern engine, say so and point the user to github.com's code search; the CLI can't do it.

## Search issues and PRs

```bash
gh search issues "memory leak" --repo=facebook/react --state=open
gh search issues "panic" --language=go --created=">2025-01-01" --sort=reactions
gh search prs "fix race condition" --owner=golang --merged --limit=20
gh search prs --review-requested=@me --state=open        # @me = the authed user
```

Useful for **prior art**: before filing a bug or building a feature, search whether it was already reported or attempted upstream. Issue/PR-specific qualifiers (`--label`, `--author`, `--assignee`, `--review`, `--merged`, `--draft`, `--comments`) are in [references/qualifiers.md](references/qualifiers.md).

**Negation needs `--`.** A leading-dash qualifier looks like a flag to the parser, so put it after `--`:
```bash
gh search issues "crash" -- -label:wontfix
gh search repos kubernetes -- -topic:deprecated
```

## Inspect a repo you found

Once you have an `owner/name`, evaluate it without cloning:

```bash
gh repo view cli/cli                              # README + stats in the terminal
gh repo view cli/cli --json description,stargazersCount,pushedAt,licenseInfo,primaryLanguage
gh api repos/cli/cli/readme --jq '.content' | base64 -d   # raw README
gh api repos/cli/cli/contents --jq '.[].name'             # top-level file/dir listing
gh api repos/cli/cli/commits --jq '.[0].commit.author.date'   # last commit date (activity)
```

All of these are GET requests — read-only. For anything `gh repo view`/`gh search` can't express (contributors, traffic, tree listing, exact field selection), fall back to `gh api` with REST or GraphQL — see [references/advanced.md](references/advanced.md).

## Limits that bite

- **Default limit 30.** Always raise `-L` for real scans.
- **1000 results per query, hard cap.** Paging never exceeds it. To cover a larger space, *partition* the query into slices that each return <1000 — by `stars:` bands, `created:`/`pushed:` date windows, or `language:` — then union the results. See [references/advanced.md](references/advanced.md).
- **Query limits:** ≤256 characters and ≤5 boolean operators (`AND`/`OR`/`NOT`) per query.
- **Rate limits:** ~30 search requests/min (general), ~9/min for code search. Make requests serially, not concurrently; on a `Retry-After` header, wait that many seconds. A timed-out search sets `incomplete_results: true` and returns partial matches.

## When the CLI isn't enough → `gh api`

Drop to the REST/GraphQL search endpoints for raw qualifiers, pagination control, or fields the subcommands don't expose:

```bash
gh api -X GET search/repositories -f q='topic:airflow stars:>500' --jq '.items[].full_name'
gh api --paginate -X GET search/issues -f q='repo:cli/cli is:open label:bug' --slurp
```

`--paginate` walks all pages (within the 1000 cap); `--slurp` wraps them into one JSON array. GraphQL `search()` is the route for fields REST omits. Details and a pagination template in [references/advanced.md](references/advanced.md).

## References

- [references/qualifiers.md](references/qualifiers.md) — full qualifier tables for repos/code/issues/PRs/commits, plus the legacy-vs-modern code-search distinction
- [references/advanced.md](references/advanced.md) — `gh api` REST + GraphQL, paging past 1000 via partitioning, rate-limit handling, `--json`/`--jq`/`--template` recipes
