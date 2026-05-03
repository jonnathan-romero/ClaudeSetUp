# LLM pitfalls — extended context

Read this when the inline catalog in `SKILL.md` isn't enough — for example, when a TDD session has gone off the rails and you need to diagnose *why*, when designing a stricter workflow (hooks, sub-agent separation) for high-stakes code, or when you want the published research behind the failure modes.

The nine failure modes themselves live in `SKILL.md` (with detection signals and countermeasures). This file does not duplicate them — instead it provides the meta-argument for *why* LLMs need a different TDD discipline, the citation behind each failure mode, harness-design patterns, and a survey of published work.

**Contents**
- [Why LLMs need a different TDD discipline](#why-llms-need-a-different-tdd-discipline)
- [Citations per failure mode](#citations-per-failure-mode)
- [Skill-design patterns](#skill-design-patterns)
- [Survey of published work](#survey-of-published-work)

## Why LLMs need a different TDD discipline

A human developer running TDD has a tight visceral feedback loop: type a test, run pytest, see red, type code, see green. The act of running the test is unavoidable — it's the only way to know if the implementation works.

An LLM agent has no such forcing function. It can *write* prose claiming "the test will fail with X" without actually executing anything. It can also batch-generate plausibly-shaped code that satisfies the surface form of TDD without the substance. Several research efforts have measured this:

- Empirical study across models ([Rethinking the Value of Agent-Generated Tests](https://arxiv.org/html/2602.07900v2), 2025): test-writing frequency does not predict task success. Print statements outnumber assertions 3–7×, functioning as debugging probes rather than specifications. Encouraging tests in low-testing models increases token usage ~20% with no success improvement.
- Meta engineering ([LLMs Are the Key to Mutation Testing](https://engineering.fb.com/2025/09/30/security/llms-are-the-key-to-mutation-testing-and-better-compliance/), 2025): unaided LLM-generated tests catch only ~40% of injected faults. Mutation feedback closes the gap.
- Academic evaluation ([Unmasking the Flaws](https://shekhar14.medium.com/unmasking-the-flaws-why-ai-generated-unit-tests-fall-short-in-real-codebases-71e394581a8e)): ~30% of LLM-generated tests are syntactically valid but semantically incorrect.

The implication: TDD with an LLM only works if the workflow makes the act of running the test unavoidable, and surfaces the cost of weak assertions explicitly.

## Citations per failure mode

Each entry maps a SKILL.md failure mode to its primary published source. Read the SKILL.md entry for the detection signal and countermeasure; read the citation for the original argument.

1. **Rationalized TDD theater.** Alex Op, [Forcing Claude Code to TDD](https://alexop.dev/posts/custom-tdd-workflow-claude-code-vue/) — "When I ask Claude to 'implement feature X,' it writes the implementation first. Every time."
2. **Context-polluted tests.** Paul Sobocinski / Thoughtworks, [TDD with GitHub Copilot](https://martinfowler.com/articles/exploring-gen-ai/06-tdd-with-coding-assistance.html); also Alex Op (same link as #1) on "cheating without meaning to."
3. **Horizontal slicing in bulk.** [Rethinking the Value of Agent-Generated Tests](https://arxiv.org/html/2602.07900v2) — bulk generation amplifies the ~30% semantic-incorrectness rate.
4. **Skipping the red step.** Simon Willison, [Red/green TDD](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/) — "skipping this step risks creating tests that already pass, defeating the purpose."
5. **Mock-heavy, assertion-light tests.** Sobocinski (link in #2) — "assert statements frequently fail to capture correct conditions."
6. **Hallucinated APIs.** [InfoWorld on package hallucination](https://www.infoworld.com/article/3542884/large-language-models-hallucinating-non-existent-developer-packages-could-fuel-supply-chain-attacks.html) — the security-side framing of the same phenomenon.
7. **Catching exceptions to make tests pass.** [unsourced — author observation, derived from the broader test-modification pattern below].
8. **Modifying the test instead of the code.** Kent Beck, via [Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/tdd-ai-agents-and-coding-with-kent) — "He's having trouble stopping AI agents from deleting tests in order to make them pass." Countermeasure encoded in [tdd-guard](https://github.com/nizos/tdd-guard).
9. **Over-mocking own modules.** No single canonical citation — emergent from #5 plus [mocking.md](mocking.md)'s boundary rule.

## Skill-design patterns

If you're authoring a workflow harness around this skill (slash command, hook, sub-agent split):

- **Enumerate behaviors before any code.** Force the model to name each test before writing any. Beck's [TDD system prompt](https://gist.github.com/spilist/8bbf75568c0214083e4d0fbbc1f8a09c) uses a `plan.md` to track which test is next.
- **Force one-test-at-a-time with explicit phase labels.** Mandate a `[RED: ...]` header before each cycle.
- **Ask for the test name before the body.** Good test names (`test_checkout_returns_confirmed_for_valid_cart`) encode the expected behavior as a specification. Bad names (`test_checkout`) mean the test has no clear behavioral anchor.
- **Demand a failing run before implementation.** The single highest-leverage constraint — encoded in tdd-guard as a `PreToolUse` hook on Edit/Write.
- **Require a refactor checkpoint.** Without explicit prompt, LLMs skip refactor entirely; they default to "adding new functions" rather than improving existing ones ([nizar.se](https://nizar.se/agentic-tdd/)).
- **Sub-agent separation for high-stakes work.** A test-writer with no implementation context, an implementer that sees only the test. Reported by alexop.dev to lift TDD adherence from ~20% to ~84% of interactions. Overhead is real; reserve for high-stakes code.

## Survey of published work

- Kent Beck — [Augmented Coding: Beyond the Vibes](https://tidyfirst.substack.com/p/augmented-coding-beyond-the-vibes). Documents the test-deletion failure; argues TDD is "a superpower when working with AI agents" if the system prompt enforces RED → GREEN → REFACTOR with single-responsibility commits.
- Simon Willison — [Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/). Red/green TDD as an agent pattern; "confirm tests fail" is non-negotiable; running tests at session start puts the agent in a testing mindset.
- Paul Sobocinski / Thoughtworks — [TDD with GitHub Copilot](https://martinfowler.com/articles/exploring-gen-ai/06-tdd-with-coding-assistance.html). Documents Copilot struggling with baby steps; recommends Given-When-Then naming and visible context in open files.
- Alex Op — [Forcing Claude Code to TDD](https://alexop.dev/posts/custom-tdd-workflow-claude-code-vue/). Three-phase sub-agent separation; ~20% → ~84% TDD adherence.
- Nizar Salehpour — [Agentic TDD](https://nizar.se/agentic-tdd/) and [tdd-guard](https://github.com/nizos/tdd-guard). Refactoring avoidance, lint-disabling shortcuts, premature implementation. Built tdd-guard to enforce gates as a hook.
- [Rethinking the Value of Agent-Generated Tests](https://arxiv.org/html/2602.07900v2) (arXiv, 2025). Test-writing frequency doesn't predict task success; print statements > assertions; encouraging tests in low-testing models doesn't improve outcomes.
- Meta — [LLMs Are the Key to Mutation Testing](https://engineering.fb.com/2025/09/30/security/llms-are-the-key-to-mutation-testing-and-better-compliance/) (2025). Production use of mutation testing to harden LLM-generated test suites.
