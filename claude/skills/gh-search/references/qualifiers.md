# GitHub search qualifiers reference

Complete qualifier and flag tables for each `gh search` subcommand. Every subcommand accepts a free-text query plus either flag-form filters (`--language=go`) or raw qualifier-form (`language:go`) — they are interchangeable and combinable. Space-separated qualifiers are ANDed. Quote multi-word phrases: `"in progress"`.

## Contents
- [Repositories](#repositories)
- [Code](#code) — and the legacy-vs-modern engine distinction
- [Issues](#issues)
- [Pull requests](#pull-requests)
- [Commits](#commits)
- [Shared: ranges, dates, sorting, negation](#shared-syntax)

## Repositories

`gh search repos [query] [flags]` — default `--limit 30`, default sort `best-match`.

| Flag | Qualifier | Notes |
|---|---|---|
| `--language` | `language:` | e.g. `language:rust` |
| `--stars` | `stars:` | `stars:>100`, `stars:10..50` |
| `--forks` | `forks:` | comparison/range |
| `--topic` | `topic:` | repeat flag to AND topics |
| `--number-topics` | `topics:` | count of topics, e.g. `topics:>3` |
| `--created` | `created:` | `created:<2020-01-01` |
| `--updated` | `pushed:` | last push date; `pushed:>2025-01-01` |
| `--size` | `size:` | kilobytes; `size:50..120` |
| `--license` | `license:` | SPDX id, e.g. `license:apache-2.0` |
| `--archived` | `archived:` | `true`/`false` |
| `--include-forks` | `fork:` | `false` (default) / `true` / `only` |
| `--visibility` | — | `public` / `private` / `internal` |
| `--owner` | `user:`/`org:` | scope to an owner |
| `--match` | `in:` | `name`, `description`, `readme` (combinable: `--match=name,description`) |
| `--good-first-issues` | `good-first-issues:` | `>=10` |
| `--help-wanted-issues` | `help-wanted-issues:` | `>=5` |
| `--followers` | `followers:` | of the owner |

Sort values (`--sort`): `forks`, `help-wanted-issues`, `stars`, `updated`. Order (`--order`): `asc`/`desc` (default `desc`).

## Code

`gh search code [query] [flags]` — default `--limit 30`. **No `--sort`/`--order`** (relevance only).

| Flag | Notes |
|---|---|
| `--language` | filter by language |
| `--filename` | e.g. `--filename=package.json` |
| `--extension` | e.g. `--extension=py` |
| `--owner` | scope to user/org |
| `--repo` / `-R` | scope to one `owner/name` |
| `--size` | file size in KB |
| `--match` | `file` (contents) or `path` |

### Legacy engine vs. modern github.com code search

`gh search code` uses GitHub's **legacy** code-search API. The modern github.com code-search syntax is **not available through the CLI**:

| Feature | `gh search code` (legacy API) | github.com UI (modern) |
|---|---|---|
| Regex `/pattern/` | ❌ | ✅ |
| `symbol:` (definition search) | ❌ | ✅ |
| `content:`, `path:` glob `**/*.js` | ❌ | ✅ |
| Boolean `AND`/`OR`/`NOT`, parentheses | limited | ✅ |
| Results match github.com UI | not guaranteed | — |

If the user needs regex or symbol search, the CLI can't do it — direct them to github.com's code search UI. The modern syntax (for reference when building web-search URLs): qualifiers `repo:owner/name`, `path:`, `language:`, `org:`, `symbol:`, `content:`, `is:archived|fork|vendored|generated`; regex in `/slashes/` (escape inner slashes `/^src\//`); case-insensitive by default.

## Issues

`gh search issues [query] [flags]` — default `--limit 30`.

| Flag | Notes |
|---|---|
| `--state` | `open` / `closed` |
| `--label` | repeat to AND labels |
| `--author` | `--author=octocat` or `@me` |
| `--assignee` / `--no-assignee` | |
| `--mentions`, `--involves`, `--commenter` | participation filters |
| `--milestone`, `--project` | |
| `--created`, `--updated`, `--closed` | date qualifiers |
| `--comments` | `--comments=">100"` |
| `--reactions`, `--interactions` | engagement |
| `--language` | language of the repo |
| `--owner`, `--repo`/`-R` | scope |
| `--include-prs` | include PRs in results |
| `--archived` | |

Sort values: `comments`, `created`, `updated`, `interactions`, `reactions` (and `reactions-+1`, `reactions-heart`, etc.).

## Pull requests

`gh search prs [query] [flags]` — all the issue flags above, plus:

| Flag | Notes |
|---|---|
| `--merged` / `--draft` | state filters |
| `--merged-at` | date qualifier |
| `--base` / `-B`, `--head` / `-H` | branch filters |
| `--checks` | `pending` / `success` / `failure` |
| `--review` | `none` / `required` / `approved` / `changes_requested` |
| `--review-requested` | user/team asked to review (`@me`) |
| `--reviewed-by` | user who reviewed |

## Commits

`gh search commits [query] [flags]` — default `--limit 30`.

| Flag | Notes |
|---|---|
| `--author`, `--author-name`, `--author-email`, `--author-date` | authorship |
| `--committer`, `--committer-name`, `--committer-email`, `--committer-date` | commit metadata |
| `--hash` | commit SHA |
| `--parent`, `--tree`, `--merge` | structural |
| `--owner`, `--repo`/`-R`, `--visibility` | scope |

Sort values: `author-date`, `committer-date`.

## Shared syntax

- **Comparisons / ranges:** `>n`, `>=n`, `<n`, `<=n`, `a..b`, `a..*`, `*..b`. Works for stars, forks, size, comments, and dates.
- **Dates:** ISO `YYYY-MM-DD`, optionally with time/zone. `created:2024-01-01..2024-12-31`.
- **Negation:** prefix `-`. In `gh`, a leading-dash qualifier must come after `--` so it isn't parsed as a flag: `gh search repos foo -- -topic:deprecated`.
- **Self-reference:** `@me` resolves to the authenticated user in `--author`, `--assignee`, `--review-requested`, etc.
- **`in:` for repos:** `in:name`, `in:description`, `in:readme`, `in:topics`.
- **Limits:** queries ≤256 chars and ≤5 boolean operators; ≤1000 results per query (see advanced.md for partitioning past it).
