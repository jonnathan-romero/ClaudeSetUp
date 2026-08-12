#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["nbformat"]
# ///
"""Build and repair Jupyter notebooks without a jupytext dependency.

Subcommands:
    from-percent  Convert a `# %%` percent-format .py draft into a valid .ipynb.
    meta          Set cell metadata (tags, slideshow) — NotebookEdit cannot reach it.
    validate      Validate a notebook; exit 1 if invalid.
    clean         Strip outputs and execution counts.

`from-percent` reuses the cell ids already present in the output file when
rebuilding, so regenerating a notebook does not churn every id in the diff —
the failure mode that makes bare `jupytext --to ipynb` unusable in a loop.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import nbformat
from nbformat.v4 import new_code_cell, new_markdown_cell, new_notebook, new_raw_cell

MARKER = re.compile(r"^#\s*%%(?P<rest>.*)$")
CELL_TYPE = re.compile(r"\[(?P<type>markdown|md|raw)\]", re.IGNORECASE)
ATTR = re.compile(
    r"(?P<key>[A-Za-z_][\w.-]*)=(?P<val>\[[^\]]*\]|\"[^\"]*\"|'[^']*'|\S+)"
)

# nbconvert and papermill read these off cell.metadata; keep the spellings exact.
SLIDE_TYPES = {"slide", "subslide", "fragment", "notes", "skip", "-"}


def _parse_value(raw: str) -> object:
    """Return a JSON value for a percent-header attribute, falling back to text."""
    raw = raw.strip()
    try:
        return json.loads(raw.replace("'", '"'))
    except json.JSONDecodeError:
        return raw.strip("\"'")


def _strip_comments(lines: list[str]) -> str:
    """Return markdown/raw cell text with the leading `# ` comment prefix removed."""
    out = [
        line[2:] if line.startswith("# ") else line[1:] if line == "#" else line
        for line in lines
    ]
    return "\n".join(out).strip("\n")


def _cell_metadata(attrs: dict[str, object]) -> dict[str, object]:
    """Translate percent-header attributes into nbformat cell metadata."""
    meta: dict[str, object] = {}
    if "tags" in attrs:
        tags = attrs["tags"]
        meta["tags"] = (
            tags if isinstance(tags, list) else [t for t in str(tags).split(",") if t]
        )
    slide = attrs.get("slide") or attrs.get("slide_type")
    if slide:
        if str(slide) not in SLIDE_TYPES:
            sys.exit(
                f"nbtool: unknown slide type {slide!r}; expected one of {sorted(SLIDE_TYPES)}"
            )
        meta["slideshow"] = {"slide_type": str(slide)}
    return meta


def parse_percent(text: str) -> list[dict]:
    """Split percent-format source into cell dicts of type, source, and metadata.

    Text before the first `# %%` marker is discarded, matching jupytext's
    treatment of a file header.
    """
    cells: list[dict] = []
    current: dict | None = None
    body: list[str] = []

    def flush() -> None:
        if current is None:
            return
        raw = body
        source = (
            _strip_comments(raw)
            if current["type"] != "code"
            else "\n".join(raw).strip("\n")
        )
        if source or current["metadata"]:
            cells.append({**current, "source": source})

    for line in text.splitlines():
        match = MARKER.match(line)
        if not match:
            if current is not None:
                body.append(line)
            continue
        flush()
        rest = match.group("rest")
        type_match = CELL_TYPE.search(rest)
        kind = "code"
        if type_match:
            kind = (
                "markdown"
                if type_match.group("type").lower() in {"markdown", "md"}
                else "raw"
            )
            rest = rest[: type_match.start()] + rest[type_match.end() :]
        attrs = {
            m.group("key"): _parse_value(m.group("val")) for m in ATTR.finditer(rest)
        }
        current, body = {"type": kind, "metadata": _cell_metadata(attrs)}, []
    flush()
    return cells


def build(
    cells: list[dict], kernel: str, display: str, existing: Path | None
) -> nbformat.NotebookNode:
    """Assemble a notebook, reusing positional cell ids from an existing file."""
    prior: list[str] = []
    if existing and existing.exists():
        prior = [c.get("id", "") for c in nbformat.read(existing, as_version=4).cells]

    nb = new_notebook()
    makers = {"code": new_code_cell, "markdown": new_markdown_cell, "raw": new_raw_cell}
    for index, spec in enumerate(cells):
        cell = makers[spec["type"]](spec["source"])
        cell.metadata.update(spec["metadata"])
        if index < len(prior) and prior[index]:
            cell.id = prior[index]
        nb.cells.append(cell)

    nb.metadata.kernelspec = {
        "display_name": display,
        "language": "python",
        "name": kernel,
    }
    nb.metadata.language_info = {
        "name": "python",
        "pygments_lexer": "ipython3",
        "file_extension": ".py",
    }
    return nb


def _write_validated(nb: nbformat.NotebookNode, path: Path) -> None:
    """Validate then write. nbformat.write() logs invalid notebooks and saves anyway."""
    try:
        nbformat.validate(nb)
    except nbformat.ValidationError as exc:
        sys.exit(f"nbtool: refusing to write invalid notebook: {exc}")
    nbformat.write(nb, path)


def _resolve_cell(nb: nbformat.NotebookNode, ref: str) -> nbformat.NotebookNode:
    """Return the cell matching a positional index or a cell id."""
    for cell in nb.cells:
        if cell.get("id") == ref:
            return cell
    try:
        return nb.cells[int(ref)]
    except (ValueError, IndexError):
        sys.exit(
            f"nbtool: no cell matching {ref!r} (notebook has {len(nb.cells)} cells)"
        )


def main() -> None:
    parser = argparse.ArgumentParser(prog="nbtool", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    fp = sub.add_parser(
        "from-percent", help="build an .ipynb from a percent-format .py draft"
    )
    fp.add_argument("draft", type=Path)
    fp.add_argument("-o", "--output", type=Path, required=True)
    fp.add_argument("--kernel", default="python3")
    fp.add_argument("--display-name", default="Python 3")

    mt = sub.add_parser("meta", help="set cell tags or slide type")
    mt.add_argument("notebook", type=Path)
    mt.add_argument("--cell", required=True, help="cell index or cell id")
    mt.add_argument("--tags", help="comma-separated, replaces existing tags")
    mt.add_argument("--slide", choices=sorted(SLIDE_TYPES))

    va = sub.add_parser("validate", help="validate a notebook")
    va.add_argument("notebook", type=Path)

    cl = sub.add_parser("clean", help="strip outputs and execution counts")
    cl.add_argument("notebook", type=Path)

    args = parser.parse_args()

    if args.cmd == "from-percent":
        cells = parse_percent(args.draft.read_text(encoding="utf-8"))
        if not cells:
            sys.exit("nbtool: no `# %%` cell markers found in draft")
        _write_validated(
            build(cells, args.kernel, args.display_name, args.output), args.output
        )
        print(f"{args.output}: {len(cells)} cells")
        return

    nb = nbformat.read(args.notebook, as_version=4)

    if args.cmd == "meta":
        cell = _resolve_cell(nb, args.cell)
        if args.tags is not None:
            cell.metadata["tags"] = [t for t in args.tags.split(",") if t]
        if args.slide:
            cell.metadata["slideshow"] = {"slide_type": args.slide}
        _write_validated(nb, args.notebook)
        print(
            f"{args.notebook}: cell {cell.get('id', args.cell)} metadata {dict(cell.metadata)}"
        )

    elif args.cmd == "validate":
        try:
            nbformat.validate(nb)
        except nbformat.ValidationError as exc:
            sys.exit(f"INVALID {args.notebook}: {exc}")
        print(
            f"OK {args.notebook}: nbformat {nb.nbformat}.{nb.nbformat_minor}, {len(nb.cells)} cells"
        )

    elif args.cmd == "clean":
        for cell in nb.cells:
            if cell.cell_type == "code":
                cell.outputs, cell.execution_count = [], None
        _write_validated(nb, args.notebook)
        print(f"{args.notebook}: outputs cleared")


if __name__ == "__main__":
    main()
