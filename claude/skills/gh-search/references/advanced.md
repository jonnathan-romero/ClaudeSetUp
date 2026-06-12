# Advanced: gh api, pagination, rate limits, output formatting

When `gh search` subcommands aren't enough — raw qualifiers, fields they don't expose, more than 1000 results, or custom shapes — drop to `gh api`. Everything here stays **read-only** (GET only).

## Contents
- [REST search via gh api](#rest-search-via-gh-api)
- [GraphQL search](#graphql-search)
- [Paging past 1000 results (partitioning)](#paging-past-1000-results)
- [Rate limits and backoff](#rate-limits-and-backoff)
- [Output: --json / --jq / --template](#output-formatting)
- [Inspecting a repo via the API](#inspecting-a-repo-via-the-api)

## REST search via gh api

Pass the query through the `q` field with `-f`, and force GET with `-X GET`:

```bash
gh api -X GET search/repositories -f q='topic:airflow stars:>500' -f sort=stars \
  --jq '.items[] | "\(.stargazers_count)  \(.full_name)"'

gh api -X GET search/code -f q='addEventListener repo:cli/cli' --jq '.items[].path'

gh api -X GET search/issues -f q='repo:cli/cli is:open label:bug' --jq '.total_count'
```

Endpoints: `search/repositories`, `search/code`, `search/issues` (covers both issues and PRs — add `is:pr`/`is:issue`), `search/commits`, `search/users`, `search/topics`, `search/labels`.

Note REST field names are snake_case (`stargazers_count`, `full_name`, `pushed_at`), unlike the `gh search --json` camelCase fields.

The response includes `total_count` and `incomplete_results` — if `incomplete_results` is `true`, the query timed out server-side and you only got partial matches; narrow the query and retry.

## GraphQL search

For fields REST omits or to fetch nested data in one call:

```bash
gh api graphql -f query='
  query($q: String!) {
    search(query: $q, type: REPOSITORY, first: 50) {
      repositoryCount
      nodes {
        ... on Repository { nameWithOwner stargazerCount pushedAt primaryLanguage { name } }
      }
      pageInfo { hasNextPage endCursor }
    }
  }' -f q='topic:cli language:rust stars:>200'
```

GraphQL uses `stargazerCount` (no `s`), distinct from REST's `stargazers_count` and the CLI's `stargazersCount` — three different spellings across three surfaces, so check which one you're on.

For automatic GraphQL pagination, `gh api graphql --paginate` works **only if** the query accepts an `$endCursor: String` variable and selects `pageInfo { hasNextPage endCursor }`.

## Paging past 1000 results

The 1000-result cap is **per query** and `--paginate` cannot exceed it. To cover a larger space, slice the query so each slice returns <1000, then union:

```bash
# Partition by star bands
for band in "stars:1..50" "stars:51..200" "stars:201..1000" "stars:>1000"; do
  gh api -X GET search/repositories -f q="language:go topic:cli $band" \
    --jq '.items[].full_name'
done | sort -u
```

Other good partition axes: `created:` / `pushed:` date windows (e.g. year by year), `language:`, or `size:` ranges. Pick whichever axis spreads your result set most evenly. Run slices **serially** (see rate limits) and dedupe the union.

`--paginate` walks all pages *within* one query's 1000-result window; `--slurp` wraps the pages into a single outer JSON array so you can pipe to `jq` once:

```bash
gh api --paginate -X GET search/repositories -f q='topic:airflow' --slurp \
  --jq 'map(.items[].full_name) | add'
```

## Rate limits and backoff

| Scope | Authenticated limit |
|---|---|
| Search (general) | ~30 requests/min |
| Code search | ~9 requests/min |
| Unauthenticated search | ~10 requests/min |

Plus secondary limits. Handling:
- **Serial, not concurrent** — concurrent search requests trip secondary limits fast.
- On a `Retry-After` response header, wait that many seconds before retrying.
- When `x-ratelimit-remaining: 0`, wait until `x-ratelimit-reset`; otherwise back off ≥1 min and increase exponentially on repeated failures.
- Check budget anytime: `gh api rate_limit --jq '.resources.search'`.

## Output formatting

Available on every `gh search` subcommand and `gh api`:

```bash
# JSON with selected fields
gh search repos cli --json fullName,stargazersCount,url

# jq for filtering/shaping (-q is shorthand for --jq)
gh search repos cli --json fullName,stargazersCount \
  -q 'sort_by(-.stargazersCount) | .[] | .fullName'

# Go template for fixed formatting
gh search repos cli --json fullName,description \
  -t '{{range .}}{{.fullName}}: {{.description}}{{"\n"}}{{end}}'
```

When a `--json` field name is rejected, `gh` prints the complete list of valid fields for that subcommand — read it and use the exact name (e.g. `stargazersCount`, not `stargazerCount`). Don't guess repeatedly.

## Inspecting a repo via the API

All GET — read-only:

```bash
gh api repos/OWNER/NAME                         # full metadata (stars, license, topics, default branch)
gh api repos/OWNER/NAME/readme --jq '.content' | base64 -d
gh api repos/OWNER/NAME/contents --jq '.[].name'          # top-level listing
gh api repos/OWNER/NAME/contents/PATH --jq '.content' | base64 -d   # one file
gh api repos/OWNER/NAME/commits --jq '.[0].commit.committer.date'   # recency
gh api repos/OWNER/NAME/contributors --jq 'length'        # contributor count
gh api repos/OWNER/NAME/languages                         # language breakdown
gh api repos/OWNER/NAME/releases/latest --jq '.tag_name'
```

For a tree listing without cloning:
```bash
gh api repos/OWNER/NAME/git/trees/HEAD?recursive=1 --jq '.tree[].path'
```
