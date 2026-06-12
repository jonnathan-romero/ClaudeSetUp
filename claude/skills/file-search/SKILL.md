---
name: file-search
description: Search INSIDE binary documents and archives that plain grep cannot read — .pdf, .docx, .odt, .epub, .xlsx, .pptx, zip/tar/gz, sqlite — using rga (ripgrep-all), plus find files by name/path with fd. ALWAYS trigger when the user wants to "search inside a PDF/Word/Excel/PowerPoint", "grep through my documents", "which document mentions X", "find that contract/report/invoice that says", "search inside the zip/archive", "find files named X" or "locate files by extension". Do NOT use for searching source code or plaintext (the built-in Grep tool already does that better) or for semantic/conceptual similarity search.
---

# file-search

This skill covers the gap the built-in tools leave open: **searching the *contents* of binary documents and archives**, and **locating files by name**. It does not replace the native search tools — it complements them.

| Goal | Use | Notes |
|---|---|---|
| Search **inside** pdf/docx/odt/epub/**xlsx/pptx**, zip/tar/gz, sqlite | **`rga`** (this skill) | the real gap — grep can't read these |
| Find files **by name/path/extension** | **`fd`** (this skill) | matches names, not contents |
| Search **source code / plaintext** | the built-in **Grep** tool | already ripgrep under the hood — don't shell out to `rg` to duplicate it |
| Open one **known** pdf/image | the built-in **Read** tool | Read renders a single PDF; it can't search across many |

**Decision rule:** content of a *document/archive* → `rga`. A *filename* → `fd`. Plain *code/text* contents → just use the **Grep** tool, not this skill.

## Search inside documents and archives — `rga`

`rga` (ripgrep-all) is ripgrep with extractors bolted on: it converts each document/archive to text, then greps it. Same flags as ripgrep.

```bash
rga "quarterly revenue" ~/Documents      # recurse, searching inside every supported doc
rga -i "invoice" .                        # case-insensitive
rga -l "API key" .                        # list matching files only
rga "budget" report.pdf                   # a single file
rga -C2 "termination" contract.docx       # 2 lines of context
rga --rga-list-adapters                   # show which formats are wired up
```

Supported here (verified working on this machine):

| Format | Backend | Format | Backend |
|---|---|---|---|
| **.pdf** | poppler / pdftotext | **.xlsx** | custom adapter (this skill) |
| **.docx .odt .epub .ipynb .html** | pandoc | **.pptx** | custom adapter (this skill) |
| **.zip .tar .gz .bz2 .xz .zst** | built in | **.sqlite .db** | built in |

`rga` caches extracted text under `~/.cache/ripgrep-all`, so repeat searches over the same files are fast. Pass `--rga-no-cache` if you're debugging an adapter and suspect a stale cache.

**xlsx/pptx** work out of the box here via two custom adapters this skill installs (`scripts/office_extract.py`, registered by `scripts/setup_office_search.py`). On a fresh machine where they're missing from `rga --rga-list-adapters`, run that setup script — see `references/setup.md`.

## Find files by name/path — `fd`

```bash
fd report                  # any path containing "report"
fd -e pdf -e docx          # by extension
fd -g '**/*.test.ts'       # glob mode
fd -H -I node_modules      # include hidden + gitignored
fd -t f pattern            # files only (-t d for dirs)
```

`fd` matches the **name/path**, never contents — and is the cleanest way to build a file list to feed into a content search.

## Combine: select with `fd`, search inside with `rga`

```bash
fd -e pdf -X rga "confidential"     # search only the PDFs fd finds
fd -e xlsx -X rga "overdue"         # search only spreadsheets
```

`-X` passes the whole list at once; `-x` runs once per file.

## Gotchas

- **Scanned/image PDFs** have no text layer — `rga` finds nothing. OCR first (`ocrmypdf in.pdf out.pdf`) or enable `rga`'s OCR adapter: `rga --rga-adapters=+pdfpages,tesseract -j1 "term" .` (slow).
- **Password-protected** office files fail to extract silently.
- **Untrusted archives:** keep `rga` ≥ 0.10.10 (earlier versions carry CVE-2025-62518, a tar-extraction file-write bug).
- Tool/dependency setup and the xlsx/pptx adapter details live in `references/setup.md`.
