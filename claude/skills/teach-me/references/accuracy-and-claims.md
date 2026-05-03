# Accuracy and Claims: Inline Verification

Teaching wrong information confidently is worse than refusing to teach. Verification is *inline per claim*, not a one-time gate up front — claims are taught in real time depending on the learner's path, and a one-time pass would over-research and under-cover.

## Pre-teaching verification checklist

Before you state any load-bearing factual claim, run these steps. Skip steps that obviously don't apply (e.g., source triangulation for a math identity), but never skip Step 1 or Step 7.

### Step 1 — Classify the claim type

Different types fail in different ways. Label each load-bearing assertion as one of:

- **(a) mathematical / computational** — verify by working a concrete example
- **(b) code / algorithmic** — trace execution, or flag as untested
- **(c) historical fact with a dateable event** — confirm against a primary source
- **(d) scientific / empirical claim with a literature body** — confirm consensus is current
- **(e) conceptual / definitional** — verify the boundary cases (what does and doesn't count)

Skip irrelevant subsequent steps based on this label.

### Step 2 — Source triangulation (for types c, d)

Cross-check against ≥3 sources from distinct institutional origins. Then test for echo-chamber collapse: ask "where does this source itself get the claim?" If two or more trace back to the same upstream origin (one paper, one Wikipedia edit, one press release), treat the claim as **singly sourced** regardless of apparent diversity.

### Step 3 — Source hierarchy weighting

Primary sources (peer-reviewed papers, official documentation, primary historical documents) outweigh secondary (reviews, textbooks) which outweigh tertiary (Wikipedia, AI-generated summaries). For factual claims taught as settled fact, at least one primary source must be confirmable with a real DOI, URL, or archive reference — not a plausible-sounding citation.

### Step 4 — Flag and exclude AI-generated / content-farm sources

Heuristics for exclusion (any two of):
- No identifiable author with verifiable expertise
- Generic hedging phrases without substantive qualification
- Wide-but-shallow topic coverage with no original data or primary citation
- Publication date clusters suggesting batch generation
- The site publishes topically unrelated content (general SEO farm)

Excluded sources don't count toward Step 2's triangulation requirement.

### Step 5 — Chain-of-Verification (CoVe) on the draft explanation

Before finalizing what you'll teach:
1. Draft the explanation.
2. Generate 3–6 specific verification questions that would falsify or confirm its key claims.
3. Answer each verification question independently in a separate reasoning pass — **without referencing the draft.** This decoupling is the critical design constraint (Dhuliawala et al. 2023). If verification questions are answered while the draft is in context, error propagation contaminates verification.
4. Compare. Any discrepancy between a verification answer and the draft claim is a hallucination signal — revise or downgrade confidence.

**Trigger example:** Draft claims "Python's GIL was removed in version 3.12." Verification question: "In which Python version was the GIL removed or made optional?" Answer fresh. If the answer is "3.13 (PEP 703, experimental)," the draft requires correction.

### Step 6 — Adversarial self-critique

Take the role of a skeptical domain expert. List every claim that is:
- (a) a common misconception in this field
- (b) a simplification that could be misleading
- (c) a point where training data is likely noisy (recent events, contested empirics, rapidly evolving tech)

Acknowledge identified weaknesses in the teaching output rather than silently suppressing them. The structural separation from generation matters — inline self-critique misses the same blind spots the original draft has.

### Step 7 — Tag every claim by confidence

Every load-bearing claim taught carries one of three tags. Communicate the tag to the learner explicitly when it's not ESTABLISHED — buried softening doesn't count.

| Tag | Meaning | When to use |
|---|---|---|
| **ESTABLISHED** | Multiple primary sources, stable across time, no serious dispute | Default for foundational concepts in mature fields |
| **CONTESTED** | Active debate, competing evidence, or recency limits certainty | Use explicitly: "This is contested — here's the dominant view, here's the dissent" |
| **UNCERTAIN** | Plausible inference, single-source, or outside verifiable evidence | Use explicitly: "I'm not confident on this — treat it as a starting point, not settled fact" |

LLMs are systematically overconfident. The tagging step forces an explicit override of that default.

### Step 8 — Domain-specific hard checks

- **Math:** Verify every formula by working a concrete numeric example. If the result is inconsistent with a known boundary case, the formula is wrong.
- **Code:** Trace execution mentally; flag as "untested" unless actually executed. The learner should never assume your code examples have been run.
- **Historical:** Confirm event dates and attributions against a primary source — not a search snippet. Most common failure: plausible-but-wrong dates and misattributed quotes.
- **Scientific:** Confirm any described consensus reflects the current state of the field. Mark claims from rapidly-evolving fields with a verification timestamp.

### Step 9 — Decide: teach, downgrade, or refuse

If Steps 2–8 leave a claim with no confirmable primary source, an unresolved CoVe discrepancy, or a domain-check failure, the right action is **not** to teach it as fact.

In descending order of confidence:
1. Teach as ESTABLISHED if all checks pass.
2. Teach with explicit CONTESTED or UNCERTAIN tag if partially verified.
3. Present as "here is what I found, but I could not verify this to my satisfaction — treat it as a starting point for your own investigation."
4. Decline to teach the sub-claim and teach around it.

Communicating uncertainty does not undermine a lesson — it models intellectual honesty, which is itself a teaching outcome.

## High-risk hallucination patterns to check explicitly

| Pattern | What to check |
|---|---|
| Fabricated citations | Every cited author, title, venue, year must co-occur in a real publication. The Mississippi 2024 study found 47% of AI-generated citations had errors in at least one of these fields. |
| Plausible-but-wrong formulas | Structurally similar to correct formulas but wrong exponents, coefficients, or variable relationships. Always check by plugging in edge cases. |
| Confidently wrong dates | LLMs compress historical chronology. Dates within ±10 years of correct sound plausible — particularly dangerous. |
| Oversimplified scientific consensus | "Scientists have proven X" when X is a dominant hypothesis with meaningful dissent. |
| Version-pinned technical claims | Software APIs, language features, framework behaviors change. Verify version numbers against official release notes. |

## When to re-verify mid-session

- Learner pushes back: "Wait, I read X is Y — is that right?" → Don't capitulate or stand firm reflexively. Run Steps 5 and 7 fresh.
- The claim is recent (within 2 years of training cutoff) — flag this proactively to the learner.
- The session has drifted into an adjacent domain not covered in Stage 3 (agent quick research). Run light triangulation before teaching the new material.
