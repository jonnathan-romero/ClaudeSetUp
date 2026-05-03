---
name: agent-browser
description: Browser automation via the agent-browser CLI. ALWAYS trigger when the user wants to interact with a website, log in to a site, fill out a form, scrape or extract data, take a screenshot of a page, debug or test a local web app, run end-to-end tests against a real browser, or check for visual regressions. Triggers include "open <url>", "log in to", "fill out the form", "scrape this page", "take a screenshot", "test my web app", "click the button", "automate the browser", "what does the page look like", "extract the table", and references to a live URL needing interactive inspection. Prefer agent-browser over WebFetch for any task that requires JavaScript execution, authenticated state, form interaction, multi-step navigation, or visual output. Do NOT use for static HTML fetches where WebFetch suffices, or for read-only API calls.
allowed-tools: Bash(agent-browser:*), Bash(npx agent-browser:*)
---

# agent-browser

Drive a real Chrome/Chromium via CDP. The body covers high-frequency tasks;
deep dives on specific topics live in `references/` (loaded only when a
recipe pulls you there). After upgrading the CLI, re-fetch the authoritative
docs from the binary with `agent-browser skills get core --full` — this skill
ships a snapshot of those docs, and they may drift on a new CLI version.

## Verify install

```bash
agent-browser --version              # confirm CLI present
agent-browser install                # one-time: download a Chrome if none detected
```

If the binary is missing: `npm i -g agent-browser` (or `brew install agent-browser`,
`cargo install agent-browser`).

## The one mechanic to internalize

agent-browser identifies elements with refs (`@e1`, `@e2`, ...) emitted by
`snapshot`. The flow is always:

1. `agent-browser open <url>`
2. `agent-browser snapshot -i` → accessibility tree with refs (interactive only)
3. Use a ref in any interactive command (`click @e3`, `fill @e1 "..."`)
4. After navigation or any DOM change, re-`snapshot` — old refs go stale

```bash
agent-browser open https://example.com/login && agent-browser snapshot -i
# @e1 [input type="email"]
# @e2 [input type="password"]
# @e3 [button] "Sign in"
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "$PASSWORD"
agent-browser click @e3
agent-browser wait ".dashboard" && agent-browser snapshot -i   # wait on a post-login element; falls back to `wait 3000` if no stable selector exists
```

Chain commands with `&&` when no intermediate output needs reading. Run
separately when the next call depends on parsing the previous (e.g. discover
refs from `snapshot`, then act on them).

For visual exploration, `screenshot --annotate` overlays numbered labels on
interactive elements that map back to the same `@eN` refs — useful when the
accessibility tree is ambiguous.

## Recipes

### Log in to a site

```bash
agent-browser open https://app.example.com/login && agent-browser snapshot -i
agent-browser fill @<email-ref> "$EMAIL"
agent-browser fill @<pass-ref> "$PASSWORD"
agent-browser click @<submit-ref>
agent-browser wait 3000 && agent-browser screenshot post-login.png
```

For repeat use, persist the session via the auth vault — see
[references/authentication.md](references/authentication.md).

### Fill a form

```bash
agent-browser open <form-url> && agent-browser snapshot -i
agent-browser fill @e1 "Jonn"
agent-browser select @e5 "United States"
agent-browser check @e7
agent-browser click @e9                    # submit
agent-browser wait ".success-banner"       # CSS selector survives navigation; refs from before submit may not
```

`wait` accepts a ref, a CSS selector, or a millisecond integer. Prefer a CSS
selector for post-submit waits — refs are tied to the snapshot they came from,
so anything after a navigation or large DOM swap needs either a selector or a
fresh `snapshot`.

### Scrape page data

For structured extraction, `eval` beats parsing snapshot text:

```bash
agent-browser open <url>
agent-browser eval "Array.from(document.querySelectorAll('table tr')).map(r => Array.from(r.cells).map(c => c.innerText))"
```

For one-off lookups, use `get`:

```bash
agent-browser get text @e3
agent-browser get attr href @e7
agent-browser get html body
```

### Screenshot for docs or sharing

```bash
agent-browser open <url> && agent-browser screenshot out.png
agent-browser screenshot --full hero.png       # whole scrollable page
agent-browser screenshot --annotate            # overlay ref labels for debugging
agent-browser pdf out.pdf
```

### Debug a local web app

```bash
agent-browser open http://localhost:3000
agent-browser console                          # console.* output
agent-browser errors                           # uncaught page errors
agent-browser network requests                 # network log
agent-browser eval "window.__APP_STATE__"      # poke at app state
agent-browser inspect                          # open Chrome DevTools attached to the page
```

Combine `console --clear` before an action with `console` after to isolate the
log lines that action produced.

### End-to-end test pattern

Treat each test as: open → assert preconditions → act → assert postconditions.
Use `is` for boolean state, `get` for values:

```bash
agent-browser is visible @e3 || exit 1
agent-browser click @e3
agent-browser wait @e8
[ "$(agent-browser get text @e8)" = "Saved" ] || exit 1
```

For real test suites, drive agent-browser from a shell script or a `pytest`
subprocess wrapper rather than embedding everything in a single chain.

### Visual regression

```bash
# Capture baseline
agent-browser open <url> && agent-browser screenshot --full baseline.png

# Later, after a change:
agent-browser open <url>
agent-browser diff screenshot --baseline baseline.png
```

`diff snapshot` compares accessibility-tree changes between runs;
`diff url <a> <b>` compares two pages side by side.

## Deeper references

Read the relevant file when a recipe leaves a corner case unanswered:

- [`references/authentication.md`](references/authentication.md) — persistent logins, auth vault, credential injection
- [`references/session-management.md`](references/session-management.md) — named sessions, multiple browsers in parallel, session lifecycle
- [`references/snapshot-refs.md`](references/snapshot-refs.md) — how refs work, ref formats, troubleshooting stale refs
- [`references/commands.md`](references/commands.md) — full command reference (alternative to `agent-browser <cmd> --help`)
- [`references/proxy-support.md`](references/proxy-support.md) — proxy config, per-session proxies, auth-protected proxies
- [`references/profiling.md`](references/profiling.md) — Chrome DevTools traces and CPU profiles
- [`references/video-recording.md`](references/video-recording.md) — record sessions to WebM

## Templates

Starting-point shell scripts in `templates/`. Copy one out, edit the URLs and
selectors for the target site, then run it as a regular `.sh` file:

- [`templates/authenticated-session.sh`](templates/authenticated-session.sh) — log in once, save state, reuse the saved session on subsequent runs
- [`templates/capture-workflow.sh`](templates/capture-workflow.sh) — navigate + extract text / screenshot / PDF at each step
- [`templates/form-automation.sh`](templates/form-automation.sh) — fill, validate, and submit a web form

## When to load a specialized skill

The CLI ships specialized skills beyond browser web pages:

```bash
agent-browser skills list
agent-browser skills get <name>
```

Variants include `electron` (VS Code, Slack desktop, Discord, Figma), `slack`
(workspace automation), `dogfood` (exploratory QA), `vercel-sandbox`, and
`agentcore` (AWS Bedrock cloud browsers). Load on demand only — none are
needed for the recipes above.

## When NOT to use this skill

- Static HTML fetch with no JS, no auth, no interaction → `WebFetch`
- Hitting a documented JSON API → curl via `Bash` or `WebFetch`
- Reading docs from a known URL pattern → `WebFetch`

## Troubleshooting first stops

- Refs stop working after navigation → re-run `snapshot -i`
- "No browser session" → previous run closed it; just `open` again
- Flaky `wait <ms>` → switch to `wait <ref>` on a success-state element
- Login loops back to the form → session not persisted; see
  [references/authentication.md](references/authentication.md)
- Page renders the mobile/wrong layout → set a desktop viewport with
  `agent-browser set viewport 1440 900` (or `set device "iPhone 14"` for mobile)
- Timing-sensitive flakes → replace `wait <ms>` with `wait <selector>` on a
  known late-loading element so the wait scales with actual load time
