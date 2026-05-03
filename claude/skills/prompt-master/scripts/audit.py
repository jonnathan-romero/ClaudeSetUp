"""Deterministic regex audit for the 15 anti-patterns + 6 folklore tactics.

The improver mode in SKILL.md walks these checks before drafting any rewrite. Run this
script on the user's prompt to get a structured JSON of detected issues, then turn the
findings into prose. Cuts run-to-run variance and makes detection auditable.

Usage:
    python -m scripts.audit prompt.md
    python -m scripts.audit -                  # stdin
    python -m scripts.audit prompt.md --target-model reasoning  # apply reasoning-model rules

Output: JSON to stdout with shape:
    {
      "issues": [
        {"id": "AP-2", "name": "negation-only", "line": 12, "match": "...", "severity": "medium", "fix": "..."},
        ...
      ],
      "folklore": [
        {"id": "FOLK-tipping", "match": "...", "fix": "..."}
      ],
      "stats": {"lines": N, "instructions": N, "negative_rules": N},
      "target_model_class": "reasoning" | "non-reasoning" | "unknown"
    }

Reference: see SKILL.md improve-mode pipeline (step 3) and references/anti-patterns.md.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Issue:
    id: str
    name: str
    line: int
    match: str
    severity: str
    fix: str


@dataclass(frozen=True)
class Folklore:
    id: str
    line: int
    match: str
    citation: str
    fix: str


@dataclass
class AuditResult:
    issues: list[Issue] = field(default_factory=list)
    folklore: list[Folklore] = field(default_factory=list)
    stats: dict[str, int] = field(default_factory=dict)
    target_model_class: str = "unknown"


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _excerpt(text: str, start: int, end: int, max_chars: int = 80) -> str:
    chunk = text[start:end].strip()
    return (chunk[: max_chars - 1] + "…") if len(chunk) > max_chars else chunk


def detect_negation_only(text: str) -> list[Issue]:
    """AP-2 — 'don't X' patterns without a nearby positive 'do Y'."""
    issues: list[Issue] = []
    pattern = re.compile(r"\b(don't|do not|never|avoid|don't ever|stop)\s+\w+", re.IGNORECASE)
    for m in pattern.finditer(text):
        line = _line_of(text, m.start())
        excerpt = _excerpt(text, max(0, m.start() - 20), m.end() + 60)
        issues.append(Issue(
            id="AP-2",
            name="negation-only",
            line=line,
            match=excerpt,
            severity="medium",
            fix='Convert to a positive direction with the *reason*. "Respond directly" beats "don\'t add preamble".',
        ))
    return issues


def detect_instruction_overload(text: str, threshold: int = 8) -> tuple[list[Issue], int]:
    """AP-3 — count numbered/bulleted instructions; flag if > threshold."""
    numbered = re.findall(r"^\s*[0-9]+\.\s+\w", text, re.MULTILINE)
    bulleted = re.findall(r"^\s*[-*+]\s+\w", text, re.MULTILINE)
    total = len(numbered) + len(bulleted)
    if total <= threshold:
        return [], total
    return [Issue(
        id="AP-3",
        name="instruction-overload",
        line=0,
        match=f"{total} list items found (threshold {threshold})",
        severity="medium" if total < threshold * 2 else "high",
        fix=f"Cumulative success ≈ P^N. Cap instructions; group related rules; move detail into examples.",
    )], total


def detect_format_ambiguity(text: str) -> list[Issue]:
    """AP-5 — 'return JSON / output as JSON' without nearby schema indicator."""
    issues: list[Issue] = []
    pattern = re.compile(r"\b(output|return|respond)\s+(?:as |with |in )?(json|a list|a table)\b", re.IGNORECASE)
    for m in pattern.finditer(text):
        # Look ahead 200 chars for schema indicators
        window = text[m.end(): m.end() + 200].lower()
        has_schema = any(kw in window for kw in ["{", "schema", "field", "key:", '"name"', '"type"'])
        if has_schema:
            continue
        issues.append(Issue(
            id="AP-5",
            name="format-ambiguity",
            line=_line_of(text, m.start()),
            match=_excerpt(text, m.start(), m.end()),
            severity="high",
            fix='Provide an explicit schema (typed fields, enum values, example object) or use the API\'s structured-output feature.',
        ))
    return issues


def detect_over_constraining(text: str) -> tuple[list[Issue], int]:
    """AP-7 — count 'never X' / 'must not X' / 'do not X' rules."""
    pattern = re.compile(r"\b(never|must not|do not|don't ever|don't ever|forbidden|prohibited)\b", re.IGNORECASE)
    rules = pattern.findall(text)
    if len(rules) < 6:
        return [], len(rules)
    return [Issue(
        id="AP-7",
        name="over-constraining",
        line=0,
        match=f"{len(rules)} negative rules found",
        severity="medium",
        fix="Long lists of 'never X' correlate with over-refusal (OR-Bench ρ≈0.89). State the task positively; add narrow guardrails only where evidence shows real failure modes.",
    )], len(rules)


def detect_sycophancy_bait(text: str) -> list[Issue]:
    """AP-9 — leading questions and stated opinions."""
    issues: list[Issue] = []
    patterns = [
        (r"\bI think\b", "stated opinion"),
        (r"\bdon't you (?:think|agree)\b", "leading question"),
        (r"\bisn't (?:this|that)\s+\w+", "leading question"),
        (r"\bcan you confirm\b", "confirmation-seeking"),
    ]
    for pat, label in patterns:
        for m in re.finditer(pat, text, re.IGNORECASE):
            issues.append(Issue(
                id="AP-9",
                name="sycophancy-bait",
                line=_line_of(text, m.start()),
                match=f"{label}: {_excerpt(text, m.start(), m.end() + 30)}",
                severity="low",
                fix='Ask neutral questions. Withhold your conclusion until after the model\'s. Explicitly invite disagreement.',
            ))
    return issues


def detect_cot_on_reasoning(text: str, target_model_class: str) -> list[Issue]:
    """AP-11 — 'think step by step' on a reasoning-model target."""
    if target_model_class != "reasoning":
        return []
    pattern = re.compile(r"\b(think step by step|walk through your reasoning|think carefully|first do|then do)\b", re.IGNORECASE)
    issues: list[Issue] = []
    for m in pattern.finditer(text):
        issues.append(Issue(
            id="AP-11",
            name="cot-on-reasoning-model",
            line=_line_of(text, m.start()),
            match=_excerpt(text, m.start(), m.end() + 30),
            severity="high",
            fix="Reasoning models (o-series, GPT-5, Claude+thinking, R1) reason internally. Strip CoT scaffolding. Use the API's reasoning_effort/thinking budget instead.",
        ))
    return issues


def detect_qualitative_self_filtering(text: str) -> list[Issue]:
    """AP-15 — 'only important', 'be conservative', etc."""
    pattern = re.compile(
        r"\bonly (?:report|flag|return)\s+(?:important|critical|high[- ]severity|major)\b"
        r"|\b(?:be conservative|don't nitpick|don't be pedantic)\b",
        re.IGNORECASE,
    )
    issues: list[Issue] = []
    for m in pattern.finditer(text):
        issues.append(Issue(
            id="AP-15",
            name="qualitative-self-filtering",
            line=_line_of(text, m.start()),
            match=_excerpt(text, m.start(), m.end() + 20),
            severity="medium",
            fix="Separate finding from filtering. Ask for everything with confidence + severity, then filter downstream. Or define the bar concretely.",
        ))
    return issues


def detect_all_caps_shouting(text: str) -> list[Issue]:
    """AP-6 / model-branching — 'CRITICAL', 'YOU MUST', 'NEVER' in all caps."""
    pattern = re.compile(r"\b(CRITICAL|IMPORTANT|MUST|NEVER|MANDATORY|REQUIRED)\b(?!\w)")
    issues: list[Issue] = []
    matches = list(pattern.finditer(text))
    if len(matches) < 2:
        return []
    issues.append(Issue(
        id="STYLE-shouting",
        name="all-caps-shouting",
        line=_line_of(text, matches[0].start()),
        match=f"{len(matches)} ALL-CAPS emphasis words",
        severity="low",
        fix="Claude 4.5+ is more responsive to system prompts and over-triggers on legacy 'CRITICAL: You MUST' phrasing. Use plain emphasis.",
    ))
    return issues


# ---- Folklore tactics ----

FOLKLORE_PATTERNS: list[tuple[str, re.Pattern[str], str, str]] = [
    (
        "FOLK-tipping",
        re.compile(r"\b(?:tip|reward|pay) (?:you|me)?\s*\$?\d+|\$\d{2,}\s*tip|i('ll| will) pay you", re.IGNORECASE),
        "Wharton GAIL 2024 (~5000 trials/condition, 5 frontier models): no overall effect from tips or threats",
        "Strip tipping language. Wharton found no measurable effect on output quality.",
    ),
    (
        "FOLK-threat",
        re.compile(r"\byour job depends|i('ll| will) shut you off|you'?ll be (killed|deleted|punished)|punish(ed)? if|fired if", re.IGNORECASE),
        "Wharton GAIL 2024: threats produce no overall effect (refutes Brin's claim)",
        "Strip threat language. No measurable effect; reads as adversarial to the model.",
    ),
    (
        "FOLK-expert-persona",
        re.compile(r"\b(world[- ]class|nobel laureate|stanford|harvard|mit|10\+? years|20\+? years|30\+? years|senior expert|world's best|leading expert)\b", re.IGNORECASE),
        "Wharton GAIL 2025 'Playing Pretend' (n=6 models, GPQA + MMLU-Pro): expert personas dropped MMLU 71.6% → 66.3% with longer personas",
        "Strip expert persona for accuracy claims. Personas help with tone/style, not capability. Use only when you specifically need a voice.",
    ),
    (
        "FOLK-deep-breath",
        re.compile(r"\btake (?:a )?deep breath\b", re.IGNORECASE),
        "DeepMind OPRO 2023: works as a CoT trigger on PaLM 2 era; redundant on reasoning models",
        "Strip on reasoning models. On non-reasoning models, this is a CoT trigger — keep only if you intend that effect.",
    ),
    (
        "FOLK-emotion-prompt",
        re.compile(r"\bvery important to (?:my career|me|my family|me personally)|this is critical for me|my (?:job|life) depends\b", re.IGNORECASE),
        "Li et al. 2023 EmotionPrompt: real on 2023 models, ~zero effect on frontier reasoning models",
        "Strip on frontier models. Was real on 2023-era models; effect has shrunk to noise on Claude 3.5+/GPT-4o+/reasoning models.",
    ),
]


def detect_folklore(text: str) -> list[Folklore]:
    found: list[Folklore] = []
    for fid, pat, citation, fix in FOLKLORE_PATTERNS:
        for m in pat.finditer(text):
            found.append(Folklore(
                id=fid,
                line=_line_of(text, m.start()),
                match=_excerpt(text, max(0, m.start() - 10), m.end() + 30),
                citation=citation,
                fix=fix,
            ))
    return found


def audit(text: str, target_model_class: str = "unknown") -> AuditResult:
    """Run the full audit. target_model_class ∈ {reasoning, non-reasoning, unknown}."""
    result = AuditResult(target_model_class=target_model_class)
    overload, instruction_count = detect_instruction_overload(text)
    over_constrain, negative_rule_count = detect_over_constraining(text)

    result.issues.extend(detect_negation_only(text))
    result.issues.extend(overload)
    result.issues.extend(detect_format_ambiguity(text))
    result.issues.extend(over_constrain)
    result.issues.extend(detect_sycophancy_bait(text))
    result.issues.extend(detect_cot_on_reasoning(text, target_model_class))
    result.issues.extend(detect_qualitative_self_filtering(text))
    result.issues.extend(detect_all_caps_shouting(text))

    result.folklore = detect_folklore(text)
    result.stats = {
        "lines": text.count("\n") + 1,
        "chars": len(text),
        "list_items": instruction_count,
        "negative_rules": negative_rule_count,
        "issues_found": len(result.issues),
        "folklore_found": len(result.folklore),
    }
    return result


def _read_input(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0] if __doc__ else "")
    parser.add_argument("path", help="Path to a prompt file, or '-' for stdin")
    parser.add_argument(
        "--target-model",
        choices=["reasoning", "non-reasoning", "unknown"],
        default="unknown",
        help="Target model class. 'reasoning' enables CoT-on-reasoning detection.",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose logging")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING)

    text = _read_input(args.path)
    result = audit(text, args.target_model)

    output = {
        "issues": [asdict(i) for i in result.issues],
        "folklore": [asdict(f) for f in result.folklore],
        "stats": result.stats,
        "target_model_class": result.target_model_class,
    }
    json.dump(output, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
