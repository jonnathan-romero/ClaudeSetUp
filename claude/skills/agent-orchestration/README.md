# agent-orchestration

A Claude Code skill that decides when and how to use multi-agent
orchestration — single agent vs sub-agents, team size (1/2/3/5/10),
topology (orchestrator-worker, role triad, debate, hierarchical),
per-agent tool scoping, termination and cost bounds.

The skill's central claim is unfashionable: **single-agent is the
default, multi-agent is exceptional**. Anthropic's own multi-agent
research system uses ~15× more tokens than chat, and Anthropic itself
admits "most coding tasks involve fewer truly parallelizable tasks
than research." Reach for multi-agent only when the task shape
genuinely calls for it.

## Dates

- **Created:** 2026-05-02
- **Last modified:** 2026-05-02

## Source research

### Anthropic primary docs

- How we built our multi-agent research system — https://www.anthropic.com/engineering/multi-agent-research-system
- Building Effective Agents — https://www.anthropic.com/research/building-effective-agents
- Effective context engineering for AI agents — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Effective harnesses for long-running agents — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Equipping agents for the real world with Agent Skills — https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Constitutional Classifiers — https://arxiv.org/abs/2501.18837
- Claude Code subagents — https://code.claude.com/docs/en/sub-agents
- Claude Code agent teams — https://code.claude.com/docs/en/agent-teams
- Claude Agent SDK permissions — https://code.claude.com/docs/en/agent-sdk/permissions
- Tool Search Tool — https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool
- Memory tool — https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
- Prompt caching — https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Pricing — https://platform.claude.com/docs/en/about-claude/pricing

### Industry primary

- Cognition — Don't Build Multi-Agents — https://cognition.ai/blog/dont-build-multi-agents
- Cognition — Devin 2 / Devin Review — https://cognition.ai/blog/devin-2
- Cursor 2.0 — https://cursor.com/blog/2-0
- OpenAI Cookbook — Deep Research with Agents SDK — https://developers.openai.com/cookbook/examples/deep_research_api/introduction_to_deep_research_api_agents
- OpenAI Agents SDK handoffs — https://openai.github.io/openai-agents-python/handoffs/
- LangGraph multi-agent — https://docs.langchain.com/oss/python/langgraph/workflows-agents
- CrewAI processes — https://docs.crewai.com/en/learn/sequential-process
- AutoGen GroupChat / Magentic-One — https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/termination.html
- Stripe compliance investigation agents — https://www.zenml.io/llmops-database/ai-powered-compliance-investigation-agents-for-enhanced-due-diligence
- Replit Agent (LangChain Breakout) — https://www.langchain.com/breakoutagents/replit
- Amazon Bedrock multi-agent collaboration — https://aws.amazon.com/blogs/aws/introducing-multi-agent-collaboration-capability-for-amazon-bedrock/

### Academic anchors

- MAST taxonomy — Why Do Multi-Agent LLM Systems Fail? (arXiv:2503.13657)
- Multi-Agent Debate — Du et al. (arXiv:2305.14325)
- Self-Consistency — Wang et al. (arXiv:2203.11171)
- Mixture-of-Agents — Wang et al. (arXiv:2406.04692)
- Panel of LLM Judges (PoLL) — Verga et al. (arXiv:2404.18796)
- Self-Refine — Madaan et al. (arXiv:2303.17651)
- Reflexion — Shinn et al. (arXiv:2303.11366)
- LLMs Cannot Self-Correct Reasoning Yet — Huang et al. (arXiv:2310.01798)
- CriticGPT — McAleese et al. (arXiv:2407.00215)
- Lost in the Middle — Liu et al. (arXiv:2307.03172)
- RULER — Hsieh et al. (arXiv:2404.06654)
- NoLiMa — Modarressi et al. (arXiv:2502.05167)
- Indirect Prompt Injection — Greshake et al. (arXiv:2302.12173)
- AgentDojo — Debenedetti et al. (arXiv:2406.13352)
- CaMeL — Debenedetti et al. (arXiv:2503.18813)
- Talk Isn't Always Cheap — (arXiv:2509.05396)
- Stop Overvaluing Multi-Agent Debate — (arXiv:2502.08788)
- Single-Agent LLMs Outperform Multi-Agent Under Equal Thinking Token Budgets — (arXiv:2604.02460)
- SagaLLM — (arXiv:2503.11951)
- MetaGPT — Hong et al. (arXiv:2308.00352)
- ChatDev — Qian et al. (arXiv:2307.07924)
- GAIA benchmark — (arXiv:2311.12983)
- SWE-bench — (arXiv:2310.06770)

### Commentary

- Simon Willison on prompt injection — https://simonwillison.net/series/prompt-injection/
- Simon Willison — Lethal trifecta — https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/
- Phil Schmid — Single vs Multi-Agent System — https://www.philschmid.de/single-vs-multi-agents
- Marc Brooker — Tail Latency — https://brooker.co.za/blog/2021/04/19/latency.html

## Changelog

- **2026-05-02** — initial version. SKILL.md (307 lines, ~1019-char
  description) + 19 reference files (8174 lines total) + 7 evals
  (5 should-trigger + 2 should-NOT-trigger near-misses). Built from
  20 background research briefs covering single-vs-multi heuristics,
  team size, adversarial patterns, role specialization, topologies,
  context isolation, anti-patterns, task playbook, memory/state,
  model routing, termination, handoff design, evaluation, production
  case studies, tool design / ACI, failure recovery, cost/latency,
  and security.
