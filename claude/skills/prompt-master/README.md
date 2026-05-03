# prompt-master

A Claude Code skill for writing, editing, reviewing, and improving prompts of every kind — Claude/GPT/Gemini user prompts, system prompts, agent system prompts in `.claude/agents/`, SKILL.md frontmatter descriptions, subagent definitions, tool descriptions, RAG/extraction templates, voice/realtime instructions, and any LLM template string.

## Dates

- **Created:** 2026-05-02
- **Last modified:** 2026-05-02

## Source research

Foundational evidence is captured in `research/` — 15 raw research streams plus a synthesis brief. Authoritative URLs cited across the references include:

- Anthropic prompt engineering (consolidated) — https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Anthropic prompting tools (generator + improver) — https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-tools
- Anthropic context engineering — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic writing tools for agents — https://www.anthropic.com/engineering/writing-tools-for-agents
- Anthropic extended thinking — https://platform.claude.com/docs/en/docs/build-with-claude/extended-thinking
- Anthropic prompt caching — https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Anthropic structured outputs — https://claude.com/blog/structured-outputs-on-the-claude-developer-platform
- Anthropic Claude Code subagents — https://code.claude.com/docs/en/sub-agents
- Anthropic skill authoring best practices — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- OpenAI GPT-4.1 prompting guide — https://cookbook.openai.com/examples/gpt4-1_prompting_guide
- OpenAI reasoning best practices — https://developers.openai.com/api/docs/guides/reasoning-best-practices
- OpenAI GPT-5 prompting guide — https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide
- DeepSeek-R1 prompting (Together docs) — https://docs.together.ai/docs/prompting-deepseek-r1
- Gemini thinking — https://ai.google.dev/gemini-api/docs/thinking
- OWASP LLM01:2025 prompt injection — https://genai.owasp.org/llmrisk/llm01-prompt-injection/

Key empirical references (cited inline across `references/`):

- Wei et al. 2022, Chain-of-Thought — https://arxiv.org/abs/2201.11903
- Liu et al. 2023, Lost in the Middle — https://arxiv.org/abs/2307.03172
- Liu et al. 2024, Mind Your Step — https://arxiv.org/abs/2410.21333
- Sprague et al. 2024, To CoT or not to CoT? — https://arxiv.org/abs/2409.12183
- Huang et al. 2023, LLMs Cannot Self-Correct Reasoning Yet — https://arxiv.org/abs/2310.01798
- Stechly et al. 2024, Self-Verification Limits — https://arxiv.org/abs/2402.08115
- Sharma et al. 2023, Sycophancy — https://arxiv.org/abs/2310.13548
- Greshake et al. 2023, Indirect Prompt Injection — https://arxiv.org/abs/2302.12173
- Wharton GAIL 2024 — Threaten or tip — https://gail.wharton.upenn.edu/research-and-insights/techreport-threaten-or-tip/
- Wharton GAIL 2025 — Playing Pretend (expert personas) — https://arxiv.org/abs/2512.05858

Folklore audit covers: tipping, threats, expert personas for accuracy, EmotionPrompt, "take a deep breath" — what replicates and what doesn't on frontier models.

## Three modes

- **Generate** — blank goal → first-draft prompt + 3 test inputs + judge rubric.
- **Improve** — paste an existing prompt → annotated rewrite + unified diff + folklore audit, all tagged to anti-pattern numbers.
- **Decompose** — break down / adapt / simplify / split a complex prompt into a runnable sequence.

Output style toggles between full (issues table + diff + tests) and terse (`🎯 Target / 💡 optimization / [prompt block]`).


## Changelog

- **2026-05-02** — iter-2 release. Three modes (generate, improve, decompose), 13 reference files, `scripts/audit.py` deterministic detector, terse output toggle, 8 behavior evals + 20 trigger evals. Backed by 15 raw research reports synthesized into evidence-grounded operational rules.
