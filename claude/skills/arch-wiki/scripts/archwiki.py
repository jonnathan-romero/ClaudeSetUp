#!/usr/bin/env python3
"""Read the offline ArchWiki (arch-wiki-docs) as plain text.

Renders MediaWiki HTML from /usr/share/doc/arch-wiki/html to readable text and
maintains a plain-text cache so the built-in Grep tool can search the corpus.
Stdlib only -- the target machine has no pandoc/bs4/lxml.

Deviates from the global "no argparse / no print()" Python rules on purpose: this is a
skill helper Claude invokes via Bash, not an IDE-run script, so argv is the interface and
stdout is the product. Matches the existing colors/ and prompt-master/ skill scripts.
"""

import argparse
import html
import logging
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

logger = logging.getLogger(__name__)

WIKI_ROOT = Path("/usr/share/doc/arch-wiki/html")
CACHE_ROOT = Path.home() / ".cache" / "arch-wiki-text"
DEFAULT_LANG = "en"

# Non-English main pages land in en/ under md5-ish names; they are pure noise.
HASH_NAME = re.compile(r"^[0-9a-f]{32}$")

_DROP_TAGS = {"script", "style", "sup"}
# Wrapper elements whose whole subtree is navigation chrome, not article prose.
_DROP_CLASS = re.compile(
    r"mw-editsection|vector-|mw-jump-link|noprint|mw-indicator|catlinks|"
    r"(^|\s)toc(\s|$)|mw-authority-control"
)
_HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}


class _Renderer(HTMLParser):
    """Turn a MediaWiki article body into markdown-ish plain text."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._out: list[str] = []
        self._drop_depth = 0
        self._drop_tag: str | None = None
        self._drop_nest = 0
        self._in_pre = 0
        self._lists: list[str] = []

    def _emit(self, text: str) -> None:
        if not self._drop_depth:
            self._out.append(text)

    def _nl(self, count: int = 1) -> None:
        self._emit("\n" * count)

    def handle_starttag(self, tag, attrs):
        if self._drop_depth:
            if tag == self._drop_tag:
                self._drop_nest += 1
            return

        attr = dict(attrs)
        css = attr.get("class", "")
        if tag in _DROP_TAGS or (css and _DROP_CLASS.search(css)):
            self._drop_depth = 1
            self._drop_tag = tag
            self._drop_nest = 1
            return

        if tag == "pre":
            self._in_pre += 1
            self._nl(2)
            self._emit("```\n")
        elif tag in _HEADINGS:
            self._nl(2)
            self._emit("#" * int(tag[1]) + " ")
        elif tag in ("ul", "ol"):
            self._lists.append(tag)
            self._nl()
        elif tag == "li":
            self._nl()
            self._emit("  " * max(0, len(self._lists) - 1) + "- ")
        elif tag == "dt":
            self._nl()
        elif tag == "dd":
            self._nl()
            self._emit("    ")
        elif tag in ("p", "table", "blockquote"):
            self._nl(2)
        elif tag in ("div", "tr"):
            self._nl()
        elif tag == "br":
            self._nl()
        elif tag in ("td", "th"):
            self._emit(" | ")

    def handle_endtag(self, tag):
        if self._drop_depth:
            if tag == self._drop_tag:
                self._drop_nest -= 1
                if self._drop_nest <= 0:
                    self._drop_depth = 0
                    self._drop_tag = None
            return

        if tag == "pre":
            self._in_pre = max(0, self._in_pre - 1)
            self._emit("\n```")
            self._nl(2)
        elif tag in _HEADINGS:
            self._nl(2)
        elif tag in ("ul", "ol"):
            if self._lists:
                self._lists.pop()
            self._nl()
        elif tag in ("p", "table", "blockquote"):
            self._nl(2)

    def handle_data(self, data):
        if self._drop_depth:
            return
        if self._in_pre:
            self._emit(data)
            return
        collapsed = re.sub(r"\s+", " ", data)
        if not collapsed.strip():
            if self._out and not self._out[-1].endswith((" ", "\n")):
                self._emit(" ")
            return
        self._emit(collapsed)

    def text(self) -> str:
        body = "".join(self._out)
        body = re.sub(r"[ \t]+\n", "\n", body)
        body = re.sub(r"\n{3,}", "\n\n", body)
        body = re.sub(r"[ \t]{2,}", " ", body)
        return body.strip() + "\n"


def _slice_body(raw: str) -> str:
    """Narrow raw page HTML down to the article body."""
    start = raw.find('id="mw-content-text"')
    if start == -1:
        start = 0
    else:
        start = raw.rfind("<div", 0, start)
        start = max(start, 0)
    for marker in ('id="catlinks"', "printfooter"):
        end = raw.find(marker, start)
        if end != -1:
            return raw[start:end]
    return raw[start:]


def page_title(raw: str) -> str:
    match = re.search(r"<title>(.*?)</title>", raw, re.S)
    if not match:
        return ""
    return html.unescape(match.group(1)).replace(" - ArchWiki", "").strip()


def render(path: Path) -> str:
    """Render one wiki HTML file to plain text with a leading `# Title` line."""
    raw = path.read_text(encoding="utf-8", errors="replace")
    renderer = _Renderer()
    renderer.feed(_slice_body(raw))
    title = page_title(raw) or path.stem.replace("_", " ")
    return f"# {title}\n\n{renderer.text()}"


def _article_files(lang: str) -> list[Path]:
    root = WIKI_ROOT / lang
    if not root.is_dir():
        raise SystemExit(f"no such language directory: {root}")
    return sorted(p for p in root.rglob("*.html") if not HASH_NAME.match(p.stem))


def _installed_version() -> str:
    try:
        out = subprocess.run(
            ["pacman", "-Q", "arch-wiki-docs"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        return out.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


# -- page resolution -----------------------------------------------------


def _normalize(name: str) -> str:
    return name.strip().strip("/").replace(" ", "_").removesuffix(".html").lower()


def resolve(name: str, lang: str = DEFAULT_LANG) -> tuple[Path | None, list[Path]]:
    """Resolve a page name to a file. Returns (exact_match, candidates)."""
    files = _article_files(lang)
    root = WIKI_ROOT / lang
    wanted = _normalize(name)

    by_rel = {str(f.relative_to(root)).removesuffix(".html").lower(): f for f in files}
    if wanted in by_rel:
        return by_rel[wanted], []

    stem_hits = [f for f in files if f.stem.lower() == wanted]
    if len(stem_hits) == 1:
        return stem_hits[0], []

    substring = [f for f in files if wanted in str(f.relative_to(root)).lower()]
    if len(substring) == 1:
        return substring[0], []
    return None, stem_hits + [f for f in substring if f not in stem_hits]


def _rel(path: Path, lang: str) -> str:
    return str(path.relative_to(WIKI_ROOT / lang)).removesuffix(".html")


# -- sections ------------------------------------------------------------


def split_sections(text: str) -> list[tuple[int, str, str]]:
    """Split rendered text into (level, heading, body) triples."""
    parts: list[tuple[int, str, str]] = []
    pattern = re.compile(r"^(#{1,6}) +(.*)$", re.M)
    matches = list(pattern.finditer(text))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        parts.append((len(m.group(1)), m.group(2).strip(), text[m.end() : end].strip()))
    return parts


# -- commands ------------------------------------------------------------


def cmd_build(args) -> int:
    lang = args.lang
    dest = CACHE_ROOT / lang
    stamp = CACHE_ROOT / f".version-{lang}"
    version = _installed_version()

    if dest.is_dir() and not args.force:
        if stamp.is_file() and stamp.read_text().strip() == version:
            pages = len(list(dest.rglob("*.txt")))
            print(f"cache is current ({version}, {pages} pages)")
            print(f"GREP THIS PATH: {dest}")
            return 0

    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)

    files = _article_files(lang)
    written = failed = 0
    for src in files:
        out = dest / src.relative_to(WIKI_ROOT / lang).with_suffix(".txt")
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            out.write_text(render(src), encoding="utf-8")
            written += 1
        except Exception:
            logger.warning("failed to render %s", src, exc_info=True)
            failed += 1

    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    stamp.write_text(version + "\n")
    print(f"built {written} pages" + (f" ({failed} failed)" if failed else ""))
    print(f"GREP THIS PATH: {dest}")
    return 0


def cmd_find(args) -> int:
    lang = args.lang
    root = WIKI_ROOT / lang
    wanted = _normalize(args.name)
    hits = [
        f for f in _article_files(lang) if wanted in str(f.relative_to(root)).lower()
    ]
    if not hits:
        print(f"no page matching {args.name!r}")
        return 1
    for f in hits[: args.limit]:
        print(_rel(f, lang))
    if len(hits) > args.limit:
        print(f"... {len(hits) - args.limit} more")
    return 0


def cmd_toc(args) -> int:
    path, candidates = resolve(args.page, args.lang)
    if path is None:
        return _report_ambiguous(args.page, candidates, args.lang)
    text = render(path)
    print(f"{_rel(path, args.lang)}  ({len(text)} chars)")
    for level, heading, body in split_sections(text):
        if level == 1:
            continue
        print(f"{'  ' * (level - 2)}{heading}  [{len(body)} chars]")
    return 0


def cmd_show(args) -> int:
    path, candidates = resolve(args.page, args.lang)
    if path is None:
        return _report_ambiguous(args.page, candidates, args.lang)
    text = render(path)

    if not args.section:
        print(text)
        return 0

    sections = split_sections(text)
    wanted = args.section.strip().lower()
    matches = [s for s in sections if s[1].lower() == wanted]
    if not matches:
        matches = [s for s in sections if wanted in s[1].lower()]
    if not matches:
        print(f"no section matching {args.section!r} in {_rel(path, args.lang)}")
        print("sections:", ", ".join(s[1] for s in sections if s[0] > 1))
        return 1

    level, heading, _ = matches[0]
    start = next(i for i, s in enumerate(sections) if s[1] == heading and s[0] == level)
    out = [f"{'#' * level} {heading}", "", sections[start][2]]
    for sub_level, sub_heading, sub_body in sections[start + 1 :]:
        if sub_level <= level:
            break
        out += ["", f"{'#' * sub_level} {sub_heading}", "", sub_body]
    print(f"[{_rel(path, args.lang)}]")
    print("\n".join(out))
    return 0


def _report_ambiguous(name: str, candidates: list[Path], lang: str) -> int:
    if not candidates:
        print(f"no page matching {name!r} -- try: archwiki.py find {name}")
        return 1
    print(f"{name!r} is ambiguous, {len(candidates)} candidates:")
    for f in candidates[:20]:
        print(" ", _rel(f, lang))
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read the offline ArchWiki as plain text."
    )
    parser.add_argument(
        "--lang", default=DEFAULT_LANG, help="wiki language dir (default: en)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("build", help="build/refresh the plain-text cache for Grep")
    p.add_argument("--force", action="store_true", help="rebuild even if current")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("find", help="find page names matching a substring")
    p.add_argument("name")
    p.add_argument("--limit", type=int, default=40)
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("toc", help="list a page's sections with their sizes")
    p.add_argument("page")
    p.set_defaults(func=cmd_toc)

    p = sub.add_parser("show", help="print a page, or one section of it")
    p.add_argument("page")
    p.add_argument("section", nargs="?", help="section heading (substring match)")
    p.set_defaults(func=cmd_show)

    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s: %(message)s")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
