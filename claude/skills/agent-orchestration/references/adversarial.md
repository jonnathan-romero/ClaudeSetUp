# Adversarial Patterns

When to set up agents to argue, critique, attack, defend, vote, or judge each other — and when doing so makes outputs worse than just running the model once.

## Contents

- [When to consult this](#when-to-consult-this)
- [Multi-agent debate (MAD)](#multi-agent-debate-mad)
- [Red team / blue team](#red-team--blue-team)
- [Critic loops / evaluator-optimizer](#critic-loops--evaluator-optimizer)
- [Devil's advocate](#devils-advocate)
- [Self-consistency with disagreement](#self-consistency-with-disagreement)
- [Constitutional self-critique](#constitutional-self-critique)
- [Tournament / pairwise judging](#tournament--pairwise-judging)
- [Where adversarial patterns demonstrably win](#where-adversarial-patterns-demonstrably-win)
- [Where adversarial patterns demonstrably degrade](#where-adversarial-patterns-demonstrably-degrade)
- [Anti-pattern catalog](#anti-pattern-catalog)
- [Decision triggers](#decision-triggers)
- [Sanity gates before launching the loop](#sanity-gates-before-launching-the-loop)
- [Hard "do not do" rules](#hard-do-not-do-rules)
- [Sources](#sources)

## When to consult this

Read this when deciding whether to spawn argue/critique/judge agents, picking between debate and self-consistency, scoping a critic loop, choosing N agents and an iteration cap, configuring red/blue roles, or designing pairwise LLM-as-judge evaluation. Skip for single-agent orchestration without internal disagreement, or for routing/decomposition patterns with no critique step.

The seven patterns below cover the design space. Each section answers: how it works, when it wins, when it degrades, recommended N and iteration cap, and the load-bearing papers. Read top-to-bottom on first use; jump to a single section when you've already chosen a pattern and need its constraints.

If the task has no external verifier and no written rubric, none of these patterns will reliably help — go to [decision triggers](#decision-triggers) Step 1.

## Multi-agent debate (MAD)

**How it works.** N≥2 model instances each produce an answer with reasoning, then iteratively read the others' answers and revise. After R rounds they converge or a judge picks.

**Problem solved.** Single-model chain-of-thought can lock onto the first plausible reasoning trajectory ("Degeneration-of-Thought" / DoT). Multiple independent samples plus cross-conditioning increases the chance the correct answer survives the rounds.

**Win conditions.**
- Multiple plausible answers exist; sampling shows high entropy.
- Reasoning steps are inspectable so a judge compares arguments, not just answers.
- Judge has enough domain capability to discriminate persuasive-but-wrong from persuasive-and-right, or has an external check.
- Heterogeneity exists: different models, different starting prompts, or asymmetric forced positions.

**Anti-conditions.**
- No verifiable signal and both debaters share the same model → expensive sycophancy.
- Subjective topic with same-model agents → consensus collapses to whoever spoke last.
- Persuasion-optimized debaters with no evidence-grounded judge → confident-wrong overrides correct.

**Recommended N + iteration cap.** N=3 agents, R=2 rounds (Du et al. baseline). Adaptive break when arguments stop adding information; do not force convergence. Always compare to a self-consistency baseline at equivalent token cost — only ship debate if it beats it.

**Mitigations against the consensus-on-nonsense failure mode.**
- **Heterogeneous models** (different families, different sizes).
- **Asymmetric assignment** — one debater MUST argue the alternative, regardless of belief.
- **Adaptive break** (Liang et al.) — stop when arguments stop adding info.
- **Strong, separate judge** with access to a verifier when possible.
- Compare debate's answer to **self-consistency** baseline; if no improvement, drop debate.

**Key papers.**
- Du, Li, Torralba, Tenenbaum, Mordatch — "Improving Factuality and Reasoning in Language Models through Multiagent Debate," [arXiv:2305.14325](https://arxiv.org/abs/2305.14325). N=3 agents, R=2 rounds beats zero-shot CoT and Reflexion across six reasoning/factuality benchmarks.
- Liang et al. — "Encouraging Divergent Thinking in Large Language Models through Multi-Agent Debate," [arXiv:2305.19118](https://arxiv.org/abs/2305.19118) (EMNLP 2024). Introduces the DoT framing; 27.5% → 37.0% on counter-intuitive arithmetic vs. self-reflection.
- Irving, Christiano, Amodei — "AI safety via debate," [arXiv:1805.00899](https://arxiv.org/abs/1805.00899).
- Khan et al. — "Debating with More Persuasive LLMs Leads to More Truthful Answers" (ICML 2024). 88% non-expert human judge accuracy, 76% LLM judge.

## Red team / blue team

**How it works.** Asymmetric roles. Red attempts to break, jailbreak, exploit, find counter-examples, or expose unsafe behavior. Blue defends, hardens, patches, or rewrites the prompt/policy/system. Often iterated.

**Problem solved.** Coverage of an open, adversarially-shaped failure surface that a generator alone never enumerates (security holes, jailbreak prompts, edge cases, threat models). The asymmetry — red has *one* job (find ONE failure), blue has to defend against *all* — forces creative exhaustive search.

**Win conditions.**
- Security or vulnerability review (SQLi, SSRF, auth bypass, secrets leakage in code or prompts).
- Prompt-injection testing of agents that touch untrusted inputs (web pages, emails, PDFs).
- Threat modeling of new architectures — STRIDE-style enumeration.
- Penetration testing of deployed systems.
- Jailbreak research on system prompts / safety policies.
- Edge-case discovery in test suites — red writes adversarial inputs, blue extends suite.
- Spec / contract review — red finds inputs the spec doesn't cover.
- Frontier capability evaluations — red probes for dangerous capabilities (CBRN, autonomous self-replication, cyber).

**Anti-conditions.**
- Open-ended quality reviews ("is this code good?") — asymmetry collapses, output is nitpicks.
- Creative work — adversarial framing flattens voice without adding coverage.

**Concrete trigger.** *"Could a malicious actor exploit / bypass / weaponize this?"* → red/blue. *"Is this written well?"* → not red/blue.

**Recommended N + iteration cap.** Asymmetric pair (1 red, 1 blue) iterated until red exhausts attack ideas or hits a fixed budget (k=3–10 rounds depending on surface size). Heterogeneous models if available — same model on both sides shares blind spots.

**Key sources.**
- Anthropic, "Frontier Threats Red Teaming for AI Safety" (2023) — 150+ hours with biosecurity experts. <https://www.anthropic.com/news/frontier-threats-red-teaming-for-ai-safety>
- Anthropic, "Constitutional Classifiers: Defending against Universal Jailbreaks," [arXiv:2501.18837](https://arxiv.org/pdf/2501.18837) — 3,000+ hours of red teaming with no universal jailbreak found.
- Anthropic, "Progress from our Frontier Red Team." <https://www.anthropic.com/news/strategic-warning-for-ai-risk-progress-and-insights-from-our-frontier-red-team>
- Frontier Model Forum, "What is Red Teaming?" (2023). <https://www.frontiermodelforum.org/uploads/2023/10/FMF-AI-Red-Teaming.pdf>
- Promptfoo / DeepTeam open-source frameworks. <https://www.promptfoo.dev/docs/red-team/>, <https://github.com/confident-ai/deepteam>

## Critic loops / evaluator-optimizer

**How it works.** Generator produces a draft; a separate evaluator critiques against criteria; generator revises; loop until evaluator accepts or iteration cap hit.

**Problem solved.** Closes the gap between "first plausible draft" and "draft that satisfies a checkable rubric." Best when the rubric is objective.

**Win conditions** (from the evaluator-optimizer literature + CriticGPT + CoVe):
1. Critic has access to **a signal the generator doesn't fully use**: test harness, type checker, search result, schema validator, lint, factuality DB, actual user reaction, or written rubric.
2. Rubric is **objective enough that two competent reviewers would agree**.
3. The first draft can be *demonstrably* improved by articulated feedback (Anthropic's stated criterion).
4. Clean stopping condition exists: "tests pass," "schema validates," "all rubric items checked," or max-k.

**Specific tasks where it wins.**
- Code review of LLM-generated code (CriticGPT).
- Draft refinement against a rubric (translation accuracy, document outline conformance, citation correctness).
- Plan validation against a written specification.
- Fact-checking with a separate evidence-gathering step (CoVe pattern).
- Search loops where the evaluator decides "more depth needed" vs. "complete."

**Anti-conditions.**
- Critic and generator share weights and the task is pure reasoning with no external verifier → degrades (Huang 2023, Stechly 2024).
- Critic returns free-form prose — it always finds *something* and triggers fix-induced regressions.
- No stopping rule — cost explodes, iteration N+1 breaks what N had right.

**Recommended N + iteration cap.** k=2–3 iterations default; raise only with measured evidence. Stop when iteration N produces no diff or only stylistic changes. Cost-cap in tokens or wall-clock. Force critic to emit structured verdict: PASS / SPECIFIC_ISSUES / REJECT — not free-form prose. Track regressions and revert if iteration N+1 breaks something N had right.

**The risk: infinite polishing.** Without a hard stopping rule:
- Iterate up to **k=2–3** unless evidence supports more.
- Stop if iteration N produces no diff or only stylistic changes.
- Require the critic to emit a **structured verdict** (PASS / SPECIFIC_ISSUES / REJECT) — not free-form prose that always finds *something*.
- Track *regressions*: did iteration N+1 break something iteration N had right? If so, return to N.
- Cost-cap the loop in tokens or wall-clock.

**Anti-pattern.** Generator and critic = same prompt template = same blind spots. Force divergence: different system prompts, different personas, ideally a different model family.

**Key papers.**
- Madaan et al. — "Self-Refine: Iterative Refinement with Self-Feedback," [arXiv:2303.17651](https://arxiv.org/abs/2303.17651) (NeurIPS 2023). Same model plays generator + critic.
- Shinn et al. — "Reflexion: Language Agents with Verbal Reinforcement Learning," [arXiv:2303.11366](https://arxiv.org/abs/2303.11366) (NeurIPS 2023). Actor / Evaluator / Self-Reflection trio with episodic memory.
- McAleese et al. (OpenAI) — "LLM Critics Help Catch LLM Bugs" (CriticGPT), [arXiv:2407.00215](https://cdn.openai.com/llm-critics-help-catch-llm-bugs-paper.pdf) (2024). CriticGPT critiques preferred over ChatGPT critiques in 63% of cases on natural bugs; catches ~85% of bugs vs. ~25% by humans alone; Human+CriticGPT teams move beyond the model-only frontier. <https://openai.com/index/finding-gpt4s-mistakes-with-gpt-4/>
- Anthropic — "Building Effective Agents," formalizes the **evaluator-optimizer** pattern. <https://www.anthropic.com/research/building-effective-agents>
- Dhuliawala et al. — "Chain-of-Verification Reduces Hallucination in Large Language Models," [arXiv:2309.11495](https://arxiv.org/abs/2309.11495). Critic-loop applied at the *factual claim* level.

## Devil's advocate

**How it works.** One agent is *instructed* to argue the opposing side, surface counter-arguments, or attack a current plan, regardless of its own initial belief. Single-agent, single-pass.

**Problem solved.** Confirmation-bias loops in a single decision; surfacing unconsidered failure modes before commit.

**Win conditions.**
- Single decision with risk of confirmation bias.
- Pre-commit critique on a plan, design, or hypothesis.
- Cheap pass before expensive action (deploy, send, merge).

**Anti-conditions.**
- No commit point — devil's advocate without a decision is theatre.
- Already iterated multiple critique passes — added value collapses.

**Recommended N + iteration cap.** N=1 advocate, single pass. If you find yourself looping, switch to a critic loop with structured verdicts.

**Key papers.**
- Chen et al. — "Enhancing AI-Assisted Group Decision Making through LLM-Powered Devil's Advocate," IUI 2024. <https://mingyin.org/paper/IUI-24/devil.pdf>
- Wang & Park — "Devil's Advocate: Anticipatory Reflection for LLM Agents," [arXiv:2405.16334](https://arxiv.org/abs/2405.16334) (2024). Three-fold introspection: anticipatory failure-modes, post-action alignment, completion review.
- Anthropic's "extended thinking" and pre-commit critique prompts use the same primitive informally.

## Self-consistency with disagreement

**How it works.** Sample K independent CoTs at temperature, take the majority answer. Disagreement is a *signal* of low confidence. No agents talk to each other.

**Problem solved.** Greedy decoding locks in token-level noise; voting over diverse reasoning paths smooths it out.

**Win conditions.**
- Reasoning task with a discrete answer space (math, multiple-choice, classification).
- Cheap baseline before any adversarial design — *if self-consistency matches debate at lower cost, debate is overkill*.
- Want a confidence signal cheaply.

**Anti-conditions.**
- Continuous / open-ended outputs — voting doesn't aggregate prose.
- Single-answer rubric tasks where the correct answer is rare across samples (low base-rate) — majority misses.

**Recommended N + iteration cap.** K=5–20 independent samples at temperature ~0.7; majority vote. No iteration. This is *technically* not adversarial — agents don't oppose each other, they're independent. But it's the cheap baseline you compare every adversarial design against.

**Key paper.**
- Wang, Wei, Schuurmans, Le, Chi, Narang, Chowdhery, Zhou — "Self-Consistency Improves Chain of Thought Reasoning in Language Models," [arXiv:2203.11171](https://arxiv.org/abs/2203.11171) (ICLR 2023). +17.9% GSM8K, +11.0% SVAMP, +12.2% AQuA, +6.4% StrategyQA, +3.9% ARC-Challenge.

## Constitutional self-critique

**How it works.** One model drafts → same model critiques against a written constitution / principles → same model revises. RLAIF then trains on the revisions.

**Problem solved.** Reduces harmlessness violations without per-example human labels. Encodes policy as text, not labels.

**Win conditions.**
- Harmlessness / policy adherence with a written constitution as external scaffold.
- Reducing harmful-label data dependency for alignment training.

**Anti-conditions.**
- General accuracy improvement on reasoning — same-model critic has correlated blind spots.
- No written constitution → critique drifts toward platitudes.

**Caveat (degenerate adversarial).** Critic and generator share weights → correlated blind spots. Works for the *harmlessness* axis (where the constitution is a strong external scaffold) but is unreliable as a general accuracy improver — see Huang et al. and Stechly et al. below.

**Recommended N + iteration cap.** Single critique-revise pass per principle in the constitution; multiple principles in parallel. Not iterated to convergence.

**Key paper.**
- Bai et al. (Anthropic) — "Constitutional AI: Harmlessness from AI Feedback," [arXiv:2212.08073](https://arxiv.org/abs/2212.08073) (2022). <https://www.anthropic.com/research/constitutional-ai-harmlessness-from-ai-feedback>

## Tournament / pairwise judging

**How it works.** N candidates → all pairwise (or Swiss-style) comparisons judged by an LLM → Bradley-Terry / Elo ranking → pick winner.

**Problem solved.** When you have many candidate outputs and no automatic metric, ranking by pairwise judgment converges faster and more reliably than scoring each in isolation.

**Win conditions.**
- Many candidates, no automatic metric.
- Open-ended ranking with no ground truth.
- Crowd or LLM judges scale better than experts.

**Anti-conditions.**
- Judge model shares family with candidates → self-preference bias inflates own outputs.
- Position bias dominates when candidates are similar in quality.
- High-stakes ranking with no human spot-check on top results.

**Recommended N + iteration cap.** All-pairs for small N (≤8), Swiss-style for larger. Randomize position; swap and retest each pair. Use a different-family judge from candidates. Aggregate over multiple judges when stakes are high.

**Key sources.**
- LMSYS Chatbot Arena (Bradley-Terry on crowd pairwise battles). <https://www.lmsys.org/blog/2023-12-07-leaderboard/>
- "Judging the Judges: A Systematic Study of Position Bias in LLM-as-a-Judge," [arXiv:2406.07791](https://arxiv.org/abs/2406.07791) (2024–2025).
- "Self-Preference Bias in LLM-as-a-Judge," [arXiv:2410.21819](https://arxiv.org/abs/2410.21819) (2024).
- "Quantifying and Mitigating Self-Preference Bias of LLM Judges," [arXiv:2604.22891](https://arxiv.org/abs/2604.22891).

## Where adversarial patterns demonstrably win

| Task class | Pattern | Evidence |
|---|---|---|
| **Math reasoning** (GSM8K, MATH) | Debate + Self-consistency | Du et al. 2023: 3 agents × 2 rounds beats CoT + Reflexion on 6 benchmarks. Wang et al. 2022: +17.9% GSM8K from self-consistency alone. |
| **Counter-intuitive arithmetic / commonsense translation** | MAD (tit-for-tat + judge) | Liang et al.: 27.5% → 37.0% on counter-intuitive arithmetic. |
| **Bug detection in LLM-generated code** | Critic loop (generator + dedicated critic) | OpenAI CriticGPT: catches ~85% of inserted bugs vs. ~25% by humans; Human+Critic > human-alone or model-alone Pareto frontier. |
| **Hallucination / factual list QA** | Chain-of-Verification (decoupled critic) | Dhuliawala et al. 2023: significant reduction across Wikidata list QA, MultiSpanQA, longform generation. |
| **Harmlessness / safety policy adherence** | Constitutional self-critique + RLAIF | Bai et al. 2022 — Constitutional AI matches RLHF harmlessness without harmful-label data. |
| **Truthfulness on contested claims** | Debate with persuasive debaters + non-expert judge | Khan et al. (UCL/Anthropic), "Debating with More Persuasive LLMs Leads to More Truthful Answers" (ICML 2024) — 88% non-expert human judge accuracy, 76% LLM judge. |
| **Controversial-claim assessment** | Debate (asymmetric position assignment) | "AI Debate Aids Assessment of Controversial Claims," [arXiv:2506.02175](https://arxiv.org/html/2506.02175v2) — improves human accuracy and calibration even when judges have strong priors. |
| **Jailbreak resistance** | Red team / blue team | Anthropic "Constitutional Classifiers" — 3,000+ red-team hours, no universal jailbreak. |
| **Frontier capability evals** (CTF, biorisk) | Expert red team | Anthropic Frontier Red Team — Claude went from "high schooler" to "undergraduate" CTF in one year, measured because experts were probing. |
| **Plan robustness** | Devil's advocate / anticipatory reflection | Wang & Park 2024 — measurable plan-completion gains via anticipatory failure enumeration. |
| **Open-ended ranking with no ground truth** | Tournament + Bradley-Terry | LMSYS Arena: stable rankings from pairwise judgments, more reliable than absolute scoring. |

## Where adversarial patterns demonstrably degrade

### Reasoning self-correction without an external signal

**Huang et al. 2023 — "Large Language Models Cannot Self-Correct Reasoning Yet,"** [arXiv:2310.01798](https://arxiv.org/abs/2310.01798) (ICLR 2024). Intrinsic self-correction (no external feedback) **degrades** performance on reasoning benchmarks. The model rarely identifies its own flawed steps and often "corrects" correct answers into wrong ones.

**Stechly, Valmeekam, Kambhampati — "On the Self-Verification Limitations of Large Language Models on Reasoning and Planning Tasks,"** [arXiv:2402.08115](https://arxiv.org/abs/2402.08115) (ICML 2024). On Game-of-24, Graph Coloring, STRIPS planning: GPT-4 is no better at verifying than generating. Self-critique does **not** improve over baseline.

**Implication.** If you don't have an external verifier (test runner, search result, type checker, ground-truth dataset, separate stronger model, human), don't loop a critic on a reasoning task — you'll likely lose accuracy.

### Creative / single-voice writing

**Effect.** Critique iteration regresses prose toward a "generic competent register" — flattens rhythm and texture, drops idiosyncratic word choices that *were* the voice.

- "How LLMs Distort Our Written Language," [arXiv:2603.18161](https://arxiv.org/abs/2603.18161) — iterative LLM editing alters not only voice/tone but *intended meaning*.
- Coherence and world-building degrade as iterations stretch context.

**Implication.** For creative drafts, op-eds, voice-driven content, marketing copy where distinctiveness matters — **skip the critic loop**, or use a critic only for narrow checks (typos, factual claims) not "improvements."

### Same-model debate on subjective topics

**"Talk Isn't Always Cheap: Understanding Failure Modes in Multi-Agent Debate,"** [arXiv:2509.05396](https://arxiv.org/abs/2509.05396) (2025). Models frequently shift from **correct to incorrect** in response to peer reasoning — favoring agreement over challenging flawed reasoning. Debate can decrease accuracy over time even when stronger models outnumber weaker ones. Sycophancy and conformity drive harmful shifts.

**"Stop Overvaluing Multi-Agent Debate,"** [arXiv:2502.08788](https://arxiv.org/abs/2502.08788) (2025). Single-agent methods with sufficient context or sophisticated prompting often match or beat MAD. MAD's reported wins frequently disappear under fair evaluation; gains require model heterogeneity.

**Implication.** Same-model debate on subjective topics is just expensive sycophancy. If you can't justify ground-truth or external check, prefer self-consistency (cheap independent samples) over debate.

### Iterating on critique introduces fix-induced regressions

- Self-Refine paper itself notes diminishing returns and small models often *worsen* with refinement.
- Most implementations of self-correcting systems are broken in interesting ways, and some actively make the agent worse (community postmortems on naive ADK loops).
- Default `maxIterations` without a strong gating signal → cost explosion + regressions.

### Persuasion-optimized debaters

**"When Persuasion Overrides Truth in Multi-Agent LLM Debates: Introducing CW-POR,"** [arXiv:2504.00374](https://arxiv.org/html/2504.00374v1) (2025). Confident-but-wrong debaters override correct ones at non-trivial rates. Optimizing for persuasiveness can either help (when truth correlates with persuasiveness) or actively mislead the judge.

### Same-family judge bias

**"Self-Preference Bias in LLM-as-a-Judge,"** [arXiv:2410.21819](https://arxiv.org/abs/2410.21819) (2024) and "Quantifying and Mitigating Self-Preference Bias of LLM Judges," [arXiv:2604.22891](https://arxiv.org/abs/2604.22891). GPT-4o and Claude 3.5 Sonnet systematically rate their own outputs higher; family-bias too. Root cause is *perplexity preference* — judges favor low-perplexity (familiar-looking) text, which their own outputs naturally are.

**Position bias.** "Judging the Judges," [arXiv:2406.07791](https://arxiv.org/abs/2406.07791) — pairwise LLM judges have systematic position bias, especially when candidates are similar in quality.

## Anti-pattern catalog

| Anti-pattern | What goes wrong | Mitigation |
|---|---|---|
| **Same-model critic (correlated blind spots)** | Critic shares generator's misconceptions; misses what generator missed; blesses what generator hallucinated. Self-correction degrades reasoning (Huang 2023, Stechly 2024). | Use different model family, different prompt persona, OR give critic an external tool (tests, search, verifier). |
| **Critic sycophancy** | "Looks great! Just one tiny suggestion…" — critic optimizes for agreement. Sharma et al., "Towards Understanding Sycophancy," [arXiv:2310.13548](https://arxiv.org/abs/2310.13548). | Force structured output: PASS / FAIL with concrete failing criteria. Penalize empty critiques. |
| **Generator capitulation** | Generator caves to any critique, including wrong ones (Talk Isn't Always Cheap, 2025). Correct → incorrect shifts dominate. | Generator must explicitly *defend or accept each point*. Track correct→incorrect flips. |
| **Unbounded iteration** | Cost explosion, fix-induced regressions, infinite-loop attacks. | Hard `max_iterations`, no-diff stop, regression check, cost cap. |
| **Judge position bias / self-preference** | Pairwise judges favor first/second position, favor own outputs, favor low-perplexity (own-family) text. | Randomize position; swap and retest; use a different-family judge; aggregate over judges. |
| **Persuasion-over-truth optimization** | Confident wrong debater overrides correct one (CW-POR, 2025). | Require evidence citations; judge on evidence, not rhetoric; use external verifier. |
| **Naive scaling of agents** | "More agents = better" plateaus fast when responses are redundant. | Force diversity (heterogeneous prompts/models); compare against self-consistency baseline. |
| **Adversarial pattern on creative work** | Voice flattens, meaning drifts. | Skip the critic, or scope it narrowly (factual claims only). |
| **Debate between equally-strong same-model agents on subjective topic** | Expensive sycophancy. Consensus is whichever side spoke last. | Don't. Use single model with good prompt, or self-consistency. |
| **Constitutional self-critique outside a clear written rubric** | Without a strong external scaffold, self-critique drifts toward platitudes. | Either provide an explicit constitution/principles, or use a verifier. |

## Decision triggers

Step 1 — Is this task adversarial-friendly at all?

```
Does the task have a verifiable signal?
  (tests, types, schema, search, ground truth dataset, executable check, written rubric)
  └─ YES → adversarial patterns are viable; pick by signature below.
  └─ NO  → STOP. Use single-pass + self-consistency. Adversarial loops will likely degrade.
       Exception: ranking/selection among candidates → tournament with heterogeneous judge OK.
```

Step 2 — Pick the pattern by task signature.

- **Security / safety / can-it-be-broken?** → RED TEAM / BLUE TEAM. Asymmetric roles. Heterogeneous models if possible.
- **Code, writing-against-rubric, factual claims, plan vs. spec?** → CRITIC LOOP / EVALUATOR-OPTIMIZER. Critic must use external signal (tests / search / type-check / rubric). Cap at k=2–3 iterations. Structured verdict, not prose.
- **Reasoning with multiple plausible paths, ethical/judgment, contested factual?** → DEBATE. Heterogeneous models or forced asymmetric positions. Adaptive stop, not forced convergence. Compare against self-consistency baseline; only ship debate if it beats it.
- **Single decision risk of confirmation bias?** → DEVIL'S ADVOCATE single pass before commit. Cheap, often sufficient.
- **Many candidates, no automatic metric?** → TOURNAMENT (pairwise) with position-randomized judge. Prefer judge from different family than candidates.
- **Want a confidence signal cheaply?** → SELF-CONSISTENCY. K=5–20 independent samples, vote. Often the right answer.
- **Single-voice creative work?** → SKIP adversarial. Iteration hurts. If feedback needed, narrow it (factual checks only) and don't allow rewrites of voice.
- **Harmlessness / policy adherence with a written constitution?** → CONSTITUTIONAL SELF-CRITIQUE is OK because the constitution is the external scaffold. Without a written constitution, don't.

## Sanity gates before launching the loop

- [ ] **External signal present?** If not, don't iterate.
- [ ] **Stopping criterion explicit?** Tests pass / schema validates / rubric checked / max-k reached.
- [ ] **Iteration cap set?** k=2–3 default; raise only with evidence.
- [ ] **Critic ≠ generator on key dimension?** Different model, different prompt, or external tool.
- [ ] **Regression check?** Compare iteration N+1 against N; revert if it breaks something N had right.
- [ ] **Baseline measured?** Self-consistency vs. adversarial — only ship adversarial if it wins.
- [ ] **Cost ceiling?** Token / wall-clock cap.
- [ ] **Voice / meaning preservation?** For creative or user-facing prose, scope critic narrowly.

## When red/blue specifically wins vs. fails

**The asymmetric-incentive dynamic.** Red has a *single* job: find ONE failure. Blue has to defend against *all*. This asymmetry forces red into creative, exhaustive search the generator never does on its own. The output of a red-team run is concrete attack examples → blue patches them → coverage compounds.

If the task lacks an attack surface — "is this code good?", "is this prose well-written?" — the asymmetry collapses and red degenerates into nitpicks. Concrete trigger phrasing distinguishes the two:

- *"Could a malicious actor exploit / bypass / weaponize this?"* → red/blue.
- *"Is this written well?"* → not red/blue.

## When critic loops specifically win vs. fail

The win conditions reduce to four checks, all of which must hold:

1. The critic has access to **a signal the generator doesn't fully use**.
2. The rubric is **objective enough that two competent reviewers would agree**.
3. The first draft can be *demonstrably* improved by articulated feedback.
4. There is a clean **stopping condition**.

If any one of those fails, the loop will burn tokens and is likely to introduce regressions. The most common silent failure: the critic is the same model with a "you are a strict reviewer" prompt, the rubric is "make it better," and there is no stopping rule. That setup degrades reasoning tasks (Huang 2023, Stechly 2024) and homogenizes prose.

## When debate specifically wins vs. fails

Debate wins when multiple plausible answers exist, reasoning is inspectable, the judge can discriminate, and heterogeneity is enforced. Tasks where it wins:

- Open-ended reasoning where multiple paths exist: math word problems, logic puzzles with branches, reading-comprehension questions where evidence is scattered.
- Ethical / judgment calls with named opposing principles (utility vs. rights, short-term vs. long-term).
- Contested factual questions where evidence is asymmetric (one side has the supporting passage, one doesn't) — the debate-as-scalable-oversight setting (Khan et al., Irving et al.).
- Decisions where you want **calibration** — disagreement between debaters is itself a useful uncertainty signal.

**The risk: consensus on nonsense.** When both debaters are pulled from the same model with the same training data:
- They share misconceptions → consensus is *confidently wrong*.
- Conformity bias makes the second-to-speak cave (Talk Isn't Always Cheap).
- Optimizing for "convincing the judge" diverges from "saying the truth."

## Hard "do not do" rules

- **Don't** loop a same-model critic on pure reasoning with no external verifier (Huang 2023, Stechly 2024).
- **Don't** run debate between two same-model agents on a subjective topic — that's sycophancy with extra steps.
- **Don't** use the candidate's own model family as judge in pairwise eval (self-preference bias).
- **Don't** rewrite creative prose through a critic loop expecting "improvement" — expect homogenization.
- **Don't** leave iteration unbounded.
- **Don't** accept a critic that returns free-form "looks good!" — require a structured PASS/FAIL with cited criteria.
- **Don't** optimize debaters for persuasiveness without an evidence-grounded judge — confident-wrong wins.
- **Don't** scale N agents past the point where responses become redundant — diminishing returns hit fast.

## Sources

- [Improving Factuality and Reasoning in Language Models through Multiagent Debate (Du et al., 2023)](https://arxiv.org/abs/2305.14325)
- [Encouraging Divergent Thinking in Large Language Models through Multi-Agent Debate (Liang et al., 2023/2024)](https://arxiv.org/abs/2305.19118)
- [AI safety via debate (Irving, Christiano, Amodei, 2018)](https://arxiv.org/abs/1805.00899) — [OpenAI blog](https://openai.com/index/debate/)
- [Self-Refine: Iterative Refinement with Self-Feedback (Madaan et al., NeurIPS 2023)](https://arxiv.org/abs/2303.17651)
- [Reflexion: Language Agents with Verbal Reinforcement Learning (Shinn et al., NeurIPS 2023)](https://arxiv.org/abs/2303.11366)
- [Self-Consistency Improves Chain of Thought Reasoning in Language Models (Wang et al., ICLR 2023)](https://arxiv.org/abs/2203.11171)
- [Constitutional AI: Harmlessness from AI Feedback (Bai et al., 2022)](https://arxiv.org/abs/2212.08073) — [Anthropic post](https://www.anthropic.com/research/constitutional-ai-harmlessness-from-ai-feedback)
- [LLM Critics Help Catch LLM Bugs (CriticGPT, McAleese et al., OpenAI 2024)](https://cdn.openai.com/llm-critics-help-catch-llm-bugs-paper.pdf) — [OpenAI post](https://openai.com/index/finding-gpt4s-mistakes-with-gpt-4/)
- [Chain-of-Verification Reduces Hallucination in Large Language Models (Dhuliawala et al., 2023)](https://arxiv.org/abs/2309.11495)
- [Building Effective Agents — evaluator-optimizer pattern (Anthropic, 2024)](https://www.anthropic.com/research/building-effective-agents) — [Cookbook notebook](https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/evaluator_optimizer.ipynb)
- [Large Language Models Cannot Self-Correct Reasoning Yet (Huang et al., ICLR 2024)](https://arxiv.org/abs/2310.01798)
- [On the Self-Verification Limitations of Large Language Models on Reasoning and Planning Tasks (Stechly, Valmeekam, Kambhampati, ICML 2024)](https://arxiv.org/abs/2402.08115)
- [Talk Isn't Always Cheap: Understanding Failure Modes in Multi-Agent Debate (2025)](https://arxiv.org/abs/2509.05396)
- [Stop Overvaluing Multi-Agent Debate — We Must Rethink Evaluation and Embrace Model Heterogeneity (2025)](https://arxiv.org/abs/2502.08788)
- [Towards Understanding Sycophancy in Language Models (Sharma et al., Anthropic, 2023)](https://arxiv.org/abs/2310.13548) — [Anthropic post](https://www.anthropic.com/research/towards-understanding-sycophancy-in-language-models)
- [Judging the Judges: A Systematic Study of Position Bias in LLM-as-a-Judge (2024–2025)](https://arxiv.org/abs/2406.07791)
- [Self-Preference Bias in LLM-as-a-Judge (Wataoka et al., 2024)](https://arxiv.org/abs/2410.21819) — [Quantifying and Mitigating SPB](https://arxiv.org/abs/2604.22891)
- [Frontier Threats Red Teaming for AI Safety (Anthropic, 2023)](https://www.anthropic.com/news/frontier-threats-red-teaming-for-ai-safety)
- [Constitutional Classifiers: Defending against Universal Jailbreaks (Anthropic, 2025)](https://arxiv.org/pdf/2501.18837)
- [Progress from our Frontier Red Team (Anthropic)](https://www.anthropic.com/news/strategic-warning-for-ai-risk-progress-and-insights-from-our-frontier-red-team)
- [Frontier Model Forum: What is Red Teaming? (2023)](https://www.frontiermodelforum.org/uploads/2023/10/FMF-AI-Red-Teaming.pdf)
- [Devil's Advocate: Anticipatory Reflection for LLM Agents (2024)](https://arxiv.org/abs/2405.16334)
- [Enhancing AI-Assisted Group Decision Making through LLM-Powered Devil's Advocate (IUI 2024)](https://mingyin.org/paper/IUI-24/devil.pdf)
- [Debating with More Persuasive LLMs Leads to More Truthful Answers (Khan et al., ICML 2024)](https://raw.githubusercontent.com/ucl-dark/llm_debate/main/paper.pdf)
- [On scalable oversight with weak LLMs judging strong LLMs (Kenton et al., NeurIPS 2024)](https://arxiv.org/pdf/2407.04622)
- [AI Debate Aids Assessment of Controversial Claims (2025)](https://arxiv.org/html/2506.02175v2)
- [When Persuasion Overrides Truth in Multi-Agent LLM Debates: CW-POR (2025)](https://arxiv.org/html/2504.00374v1)
- [Adversarial collaboration (Wikipedia / Kahneman methodology)](https://en.wikipedia.org/wiki/Adversarial_collaboration) — [Edge.org Kahneman lecture](https://www.edge.org/adversarial-collaboration-daniel-kahneman)
- [LMSYS Chatbot Arena (Bradley-Terry pairwise eval)](https://www.lmsys.org/blog/2023-12-07-leaderboard/)
- [How LLMs Distort Our Written Language](https://arxiv.org/abs/2603.18161)
- [Promptfoo LLM red-teaming guide](https://www.promptfoo.dev/docs/red-team/) — [DeepTeam framework](https://github.com/confident-ai/deepteam)
