# Exporting with nbconvert

Current version is **7.17.1** (2026-04-08); there is no 8.x. Pin it in every command — 7.17.1 is a security release fixing two path-traversal CVEs, arbitrary file **write** via cell-attachment filenames (CVE-2026-39377) and arbitrary file **read** via HTML image embedding (CVE-2026-39378), both affecting 6.5 onward. Converting a notebook from an untrusted source on an older version is a real risk.

## Contents

- [Exporters and their dependencies](#exporters-and-their-dependencies)
- [PDF](#pdf)
- [HTML reports](#html-reports)
- [Hiding cells](#hiding-cells)
- [Slides](#slides)
- [Custom templates](#custom-templates)
- [Gotchas](#gotchas)

## Exporters and their dependencies

Prefix each with `uv run --with "nbconvert==7.17.1" `.

| Command | Produces | Needs |
|---|---|---|
| `jupyter nbconvert --to html nb.ipynb` | `nb.html`, CSS inlined | nothing |
| `jupyter nbconvert --to markdown nb.ipynb` | `nb.md` + `nb_files/` images | nothing |
| `jupyter nbconvert --to script nb.ipynb` | `nb.py` | nothing |
| `jupyter nbconvert --to slides nb.ipynb` | `nb.slides.html` (reveal.js) | nothing |
| `jupyter nbconvert --to notebook --execute --inplace nb.ipynb` | executed `.ipynb` | a kernel |
| `jupyter nbconvert --to latex nb.ipynb` | `nb.tex` | **pandoc** |
| `jupyter nbconvert --to pdf nb.ipynb` | `nb.pdf` via xelatex | **pandoc + TeX** |
| `jupyter nbconvert --to webpdf nb.ipynb` | `nb.pdf` via headless Chromium | playwright + Chromium |
| `--to rst` / `--to asciidoc` | `.rst` / `.asciidoc` | **pandoc** |

`markdown` uses mistune, not pandoc — it is the one text export with no system dependency.

## PDF

Probe, then branch:

```bash
command -v pandoc >/dev/null && kpsewhich adjustbox.sty >/dev/null 2>&1 \
  && echo latex || echo webpdf
```

**LaTeX path** (`--to pdf`) gives the best typography and needs no download, but requires pandoc *and* a TeX subset. The LaTeX template pipes every markdown cell through pandoc, so a notebook with even one markdown cell fails without it:

```
Pandoc wasn't found.
Please check that pandoc is installed:
https://pandoc.org/installing.html
```

Having `xelatex` does not rescue you, and neither does `--to latex` — that path calls pandoc too. There is no pip-installable pandoc: `pypandoc-binary` bundles the binary inside the package directory with no `[project.scripts]` entry, so `shutil.which("pandoc")` still fails.

TeX packages the template needs: `adjustbox ucs eurosym enumitem ulem soul titling grffile fontspec unicode-math tcolorbox upquote parskip environ`. Missing ones surface as `LatexFailed` with the log attached.

Prefer pandoc **≤ 3.8** if installing: pandoc > 3.8 breaks markdown-table export to PDF (nbconvert #2243, open), and nbconvert's internal `_maximal_version = "4.0.0"` means no warning fires.

**webpdf path** needs no system packages and no root:

```bash
env -u DISPLAY uv run --with "nbconvert[webpdf]==7.17.1" --with "playwright==1.62.0" \
  jupyter nbconvert --to webpdf --allow-chromium-download nb.ipynb
```

- `env -u DISPLAY` is load-bearing. With `DISPLAY` set, webpdf hangs and Chromium spikes to 100% CPU (nbconvert #2165, open since 2024, no maintainer reply). A silent hang is the worst possible failure here.
- `--allow-chromium-download` shells out to `playwright install chromium` for you. Drop it on later runs. Chromium lands in `~/.cache/ms-playwright` (~281 MB), outside uv's ephemeral env, so it is once per machine — but **pin playwright**, because the browser build is keyed to the playwright version and an unpinned re-resolve downloads another copy.
- nbconvert calls `chromium.launch()` with no `executable_path` or `channel`, so an already-installed Chrome or Brave **cannot** be reused.
- Knobs: `--WebPDFExporter.paginate=False` for one long page, `--WebPDFExporter.page_render_timeout=3000` (ms, default 100) for JS-heavy output, `--disable-sandbox` in containers only.

Third option: export HTML and print from the browser. Fine for one-offs, not scriptable.

## HTML reports

```bash
uv run --with "nbconvert==7.17.1" jupyter nbconvert --to html \
  --template lab --theme dark --embed-images --no-input nb.ipynb
```

- `--no-input` sets `exclude_input`, `exclude_input_prompt`, and `exclude_output_prompt`. `--no-prompt` drops only the prompts.
- Templates: `lab` (default), `classic`, `basic`, `reveal`. `--theme light|dark` applies to `lab` only.
- `--embed-images` inlines *markdown-cell* images as base64. Code-cell output images are already inline in the `.ipynb`.
- **Not fully offline.** CSS is inlined, but MathJax and require.js are emitted as CDN `<script src>` tags. A notebook with no math is portable; one with math is not. For true offline math, point `--HTMLExporter.mathjax_url` at a local file.

## Hiding cells

The folklore is inverted here. `TagRemovePreprocessor` is **already enabled** for html/latex/pdf/slides/markdown — `TemplateExporter.default_config` sets `enabled: True`. The flag the docs tell you to pass is a no-op there.

Where it *is* required: `--to notebook`. `NotebookExporter` is not a `TemplateExporter`, so it inherits `Preprocessor.enabled = False` and strips nothing without the flag.

```bash
uv run --with "nbconvert==7.17.1" jupyter nbconvert --to html nb.ipynb \
  --TagRemovePreprocessor.enabled=True \
  --TagRemovePreprocessor.remove_cell_tags='{"remove_cell"}' \
  --TagRemovePreprocessor.remove_input_tags='{"hide_input"}' \
  --TagRemovePreprocessor.remove_all_outputs_tags='{"hide_output"}'
```

Use the `'{"tag"}'` set literal, not a bare word — bare words are fragile under traitlets 5 container parsing. All four traits default empty and the preprocessor early-returns if all four are empty. Set the tags with `nbtool.py meta`.

## Slides

```bash
uv run --with "nbconvert[serve]==7.17.1" jupyter nbconvert nb.ipynb --to slides --post serve
```

`--post serve` needs tornado, which only ships with the `serve` extra — plain `--with nbconvert` crashes.

Cell metadata is `slideshow.slide_type` ∈ `slide`, `subslide`, `fragment`, `skip`, `notes`. Set it in the percent draft (`# %% [markdown] slide=slide`) or with `nbtool.py meta --slide`.

`reveal_url_prefix` defaults to a CDN. `--reveal-prefix reveal.js` points at a local relative subdirectory. Also `reveal_theme` (default `simple`), `reveal_transition`, `reveal_scroll`. Press `s` for speaker notes.

**A fully self-contained deck is not achievable** — even with a local reveal.js, the slides still fetch mathjax, require, and jquery from a CDN, and that is an open upstream issue. For one portable artifact, export the slides to PDF via webpdf instead.

## Custom templates

Templates are *directories* under `<prefix>/share/jupyter/nbconvert/templates/<name>`; `jupyter --paths` lists the search dirs. Select with `--template <name>`; add a search dir with `--TemplateExporter.extra_template_basedirs=<path>` rather than overriding `template_paths`, which replaces all of them.

Minimum viable template — a folder with `conf.json` and `index.html.j2`:

```json
{"base_template": "lab", "mimetypes": {"text/html": true}}
```

```jinja
{% extends 'base.html.j2' %}
{% block input_group %}{% endblock input_group %}
```

Pre-6.0 `.tpl` templates need `--template-file`, not `--template`.

## Gotchas

1. `PandocMissing` on `--to pdf` / `latex` / `rst` — the most common failure.
2. webpdf hangs at 100% CPU when `DISPLAY` is set — `env -u DISPLAY`.
3. `No suitable chromium executable found` — add `--allow-chromium-download`.
4. `Playwright is not installed to support Web PDF conversion` — use `nbconvert[webpdf]`.
5. pandoc > 3.8 breaks markdown tables in PDF, with no warning.
6. `--to notebook --execute` needs a kernel; add `--allow-errors` to survive an exception.
7. `--post serve` crashes without tornado.
