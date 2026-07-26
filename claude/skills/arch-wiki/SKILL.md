---
name: arch-wiki
description: Reads and searches the offline ArchWiki from the `arch-wiki-docs` package — 2500+ pages at /usr/share/doc/arch-wiki, no network needed. ALWAYS trigger for Arch Linux administration and configuration: pacman/AUR/makepkg/PKGBUILD, systemd units and journald, mkinitcpio, GRUB/systemd-boot/EFI, kernel modules, udev rules, networking (NetworkManager, systemd-networkd, wpa_supplicant, iwd), audio (PipeWire, PulseAudio, ALSA), Xorg/Wayland, GPU drivers (NVIDIA, AMDGPU, Intel), LUKS/dm-crypt, Btrfs/ZFS/LVM, locale/fonts, laptop and hardware setup — or when the user says "check the Arch wiki", "what does the wiki say about X", "how do I configure X on Arch", "why did my boot/network/audio break". Prefer over WebFetch/WebSearch for Arch topics: local, complete, version-pinned. Do NOT use for other distros (Debian/Ubuntu/Fedora/NixOS), for upstream project docs the wiki does not cover, or to check package versions (use `pacman`/`paru`).
---

# arch-wiki

The `arch-wiki-docs` package ships the entire ArchWiki as offline HTML at
`/usr/share/doc/arch-wiki/html/<lang>/`. This skill makes it *readable and searchable*
via `scripts/archwiki.py` (stdlib-only Python, no dependencies).

**Never grep the raw HTML directly, and never `Read` a raw `.html` page.** Both fail here —
see "Why the raw HTML is unusable" at the end. Always go through the text cache and the script.

## Setup — build the text cache first

```bash
python3 ~/.claude/skills/arch-wiki/scripts/archwiki.py build
```

Renders all English pages to a plain-text cache (~6 s, 25 MB, 2501 pages). It is
**idempotent** — it stamps the installed package version and re-renders only when
`arch-wiki-docs` has been upgraded, so running it at the start of any wiki task is free.

It prints `GREP THIS PATH: /home/<you>/.cache/arch-wiki-text/en`. **Use that exact absolute
path** in the Grep call below — the Grep tool does not expand `~`. Run `build` before your
first search in a session; if a Grep over the cache returns nothing at all, the cache is
missing — build it and retry.

## Decision rule

| You have | Use | Why |
|---|---|---|
| A **topic/concept/error string** ("how do I hibernate", `wpa_supplicant`) | the **Grep** tool over the cache dir (see Setup) | full-text, accurate recall |
| A **page name** ("the systemd page", "Pacman/Tips and tricks") | `archwiki.py show` / `toc` | resolves names directly |
| A **partial/unsure page name** | `archwiki.py find <substring>` | lists candidates |
| A page you're about to read in full | `archwiki.py toc` **first** | pages run 40 K+ chars |

Search is the **Grep tool**, not a script subcommand — the cache is plain text, and Grep is
already ripgrep. Point it at the absolute path `build` printed:

```
Grep(pattern="hibernate", path="<the GREP THIS PATH value>", output_mode="files_with_matches")
```

Then open the hits with `show` (which renders live from the HTML, so it never serves stale text).

Ignore `Category:`, `Help:`, and `ArchWiki:` hits — they are link lists and wiki-process
pages, not answers. Short `.txt` files are usually disambiguation stubs; follow their links.

## Commands

```bash
A=~/.claude/skills/arch-wiki/scripts/archwiki.py

python3 $A find pacman              # page names containing "pacman"
python3 $A toc Systemd              # section outline + per-section char counts
python3 $A show Systemd             # whole page as text
python3 $A show Systemd "Drop-in files"   # one section (+ its subsections)
python3 $A build --force            # force a full re-render
python3 $A --lang es show Systemd   # another language -- see below
```

Only `en` is cached by default. Other languages exist as HTML (`ar bg ca cs da el eo es fa
fi fr he hi hr hu id it ko lt lzh nb nl pl pt ro ru sk sl sr sv th tr uk yue zh-hans
zh-hant` — note there is **no** `de`); `show`/`toc`/`find` work on them directly, and
`--lang <code> build` caches one for Grep.

Page names are forgiving: `pacman`, `Pacman`, `network configuration`, and
`systemd/timers` all resolve. Ambiguous names print the candidate list instead of guessing.

## Token discipline

Full pages are large — `Systemd` is 45 K chars (~11 K tokens), `Pacman` 42 K. Reading one
whole page to answer a narrow question is the main way to waste context here.

**Grep → `toc` → `show <page> <section>`.** Only `show` a full page when the user genuinely
wants the whole article, or when `toc` shows it is small. Section output includes that
heading's subsections, so one `show` usually covers the answer.

## Reporting answers

Cite the page and section (`Systemd#Drop-in files`), since the user can open it at
`https://wiki.archlinux.org/title/Systemd`. The corpus is a package snapshot — check
`pacman -Q arch-wiki-docs` for its date, and say so if the topic is fast-moving (new
hardware, recent kernel or systemd changes) where the live wiki may have moved on.

## Why the raw HTML is unusable

Verified on this machine — these are the two traps to avoid:

- **Grepping the raw HTML silently loses matches.** The wiki fragments prose across inline
  tags: `pacman -Sy <i>package_name</i>`, `the <code>--needed</code> option`. The phrase
  "install the version from the extra repository" has **zero** raw-HTML hits and matches
  correctly in the text cache. A raw grep that returns nothing means nothing.
- **`rga` cannot read these files.** Its `.html` adapter shells out to `pandoc`, which is not
  installed here, so `rga` on a wiki page errors out. (`file-search`'s skill doc lists
  `.html` → pandoc as working; that row is stale.)

`archwiki.py` sidesteps both by parsing the MediaWiki body with `html.parser`, keeping
headings, `<pre>` blocks, lists and tables, and dropping nav chrome.
