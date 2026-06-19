#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Register xlsx/pptx custom adapters in the ripgrep-all config.

Points rga at the sibling `office_extract.py` so `rga` can search inside
spreadsheets and slide decks. Idempotent: re-running replaces the two adapters
by name and leaves any other custom adapters untouched.

Run directly, or let `install.sh` invoke it after deploying the skill.
"""

import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="[setup-office-search] %(message)s")
logger = logging.getLogger(__name__)

EXTRACTOR = Path(__file__).resolve().parent / "office_extract.py"
CONFIG_DIR = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "ripgrep-all"
)
CONFIG_PATH = CONFIG_DIR / "config.jsonc"

SKELETON = {"$schema": "./config.v1.schema.json", "custom_adapters": []}


def adapter(ext: str) -> dict:
    """Build a custom-adapter entry that pipes a file through the extractor."""
    return {
        "name": ext,
        "version": 1,
        "description": f"Extract text from .{ext} via office_extract.py",
        "extensions": [ext],
        "binary": str(EXTRACTOR),
        "args": [ext],
    }


def load_config() -> dict | None:
    """Read the existing JSONC config, or None if it can't be parsed safely.

    Returning None (rather than a fresh skeleton) lets the caller bail instead
    of overwriting a config it couldn't read and silently dropping the user's
    other custom adapters.
    """
    if not CONFIG_PATH.exists():
        return dict(SKELETON)
    raw = CONFIG_PATH.read_text()
    # rga's config is JSONC: strip `//` line comments and trailing commas so
    # the stdlib json parser accepts the common cases.
    stripped = re.sub(r"^\s*//.*$", "", raw, flags=re.MULTILINE)
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        return None


def main() -> int:
    config = load_config()
    if config is None:
        logger.error(
            "could not parse %s — leaving it untouched. Fix or remove it, then re-run.",
            CONFIG_PATH,
        )
        return 1
    others = [
        a
        for a in config.get("custom_adapters", [])
        if a.get("name") not in ("xlsx", "pptx")
    ]
    config["custom_adapters"] = others + [adapter("xlsx"), adapter("pptx")]

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    logger.info("registered xlsx/pptx adapters in %s", CONFIG_PATH)

    # Warm uv's cache so the first real search doesn't pay the dependency install.
    subprocess.run([str(EXTRACTOR), "xlsx"], input=b"", capture_output=True)
    logger.info("extractor dependencies ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
