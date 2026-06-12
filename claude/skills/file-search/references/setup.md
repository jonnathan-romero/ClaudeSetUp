# Setup & dependencies

The skill shells out to two Rust CLIs plus extraction backends, and bundles a
small extractor for spreadsheets/slides. Install only what's missing
(`command -v <tool>`).

## Core tools

| Tool | Purpose | Arch | Debian/Ubuntu | macOS (brew) |
|---|---|---|---|---|
| `rga` (ripgrep-all) | search inside documents/archives | `pacman -S ripgrep-all` | binary from releases¹ | `brew install rga` |
| `fd` | filename/path search | `pacman -S fd` | `apt install fd-find`² | `brew install fd` |

¹ `rga` isn't in apt — grab a binary from https://github.com/phiresky/ripgrep-all/releases or `cargo install --locked ripgrep_all`. Use **≥ 0.10.10** (earlier versions carry CVE-2025-62518).
² On Debian/Ubuntu the binary is `fdfind`; symlink it: `ln -s $(command -v fdfind) ~/.local/bin/fd`.

The built-in **Grep** tool already wraps ripgrep for code/text, so a standalone `rg` isn't required by this skill.

## Extraction backends (for `rga`)

`rga` calls these at runtime; without them the matching adapter silently does nothing. Check what's live with `rga --rga-list-adapters`.

| Backend | Unlocks | Arch | Debian/Ubuntu | macOS |
|---|---|---|---|---|
| `poppler` / `pdftotext` | **.pdf** | `pacman -S poppler` | `apt install poppler-utils` | `brew install poppler` |
| `pandoc` | **.docx .odt .epub .ipynb .html .fb2** | `pacman -S pandoc` | `apt install pandoc` | `brew install pandoc` |

`zip`, `tar`, gzip/bzip2/xz/zstd decompression, and sqlite are built into `rga` — no extra backend.

## .xlsx / .pptx — the bundled adapters

`rga` can't read Excel/PowerPoint on its own: its pandoc adapter has a hardcoded
extension list that excludes `.xlsx`/`.pptx`, and pandoc only gained those
readers in 3.8.3 (most installs are older). So this skill ships its own extractor
and registers it as two custom `rga` adapters.

- **`scripts/office_extract.py`** — a self-contained `uv` script (inline deps `openpyxl` + `python-pptx`) that reads an xlsx/pptx from stdin and prints its text.
- **`scripts/setup_office_search.py`** — writes the two adapters into `~/.config/ripgrep-all/config.jsonc`, pointing at the extractor. Idempotent; leaves any other custom adapters alone. It also warms `uv`'s cache so the first search isn't slow.

`install.sh` runs the setup script automatically after deploying the skill. To
wire it up manually (e.g. on another machine):

```bash
~/.claude/skills/file-search/scripts/setup_office_search.py
rga --rga-list-adapters | grep -E 'xlsx|pptx'   # confirm both are registered
```

Requires `uv` on PATH (https://docs.astral.sh/uv/). The extractor reads the file
from stdin, so it also works for spreadsheets/slides nested inside archives.

## Alternatives (not used here, for reference)

- **`ugrep` + `ug+`** — filter-based document search (`--filter='pdf:pdftotext % -'`) with native nested-archive descent, but no extraction cache (re-extracts every search).
- **`rgpipe`** — a ripgrep `--pre` preprocessor that adds office/legacy formats; no Rust adapter config, but no cache or archive recursion.
- **Apache Tika** — universal extractor (1000+ formats) via one JVM process; the heaviest dependency, best as a catch-all fallback.
- **recoll** — indexed full-text search across documents; wins for a large, fixed corpus queried repeatedly, at the cost of maintaining an index instead of grepping on the fly.
