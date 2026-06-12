# Operations: step kinds, split, promote, re-plan

## Contents

- [Step kinds: build vs research](#step-kinds)
- [SPLIT — a step is really two steps](#split)
- [PROMOTE — a step is really a whole plan](#promote)
- [Re-plan after a research step](#re-plan)

---

## Step kinds

Every step is one of two kinds. Mark it on the step line: `- kind: build` or `- kind: research`.

- **build** — produces code or artifacts. Normal forward work.
- **research / spike** — produces a **decision or finding**, not a deliverable. May write throwaway code. Its job is to discharge a deferred decision: turn an unknown into a written conclusion that the downstream steps can rely on. A research step is **not done** until its conclusion is captured in the plan (and, unless trivial, written to `.research/NN-*.md`).

Research steps are how progressive planning stays honest: instead of guessing a far-term decision early, you schedule a step to **learn** it at the last responsible moment, then let the finding reshape what comes after.

---

## SPLIT

**Trigger:** a step won't finish in one session, but each half clearly would. It was misclassified as one step when it was really two. Stays in the same plan; no new tier.

Use a letter suffix so later steps don't renumber.

**Before:**
```markdown
## Phases & Steps
- [ ] Step 4 — wire up auth middleware · kind: build · in-progress
- [ ] Step 5 — add rate limiting · kind: build
```

**After SPLIT:**
```markdown
## Phases & Steps
- [x] Step 4a — auth middleware: token validation · kind: build · done
    Outcome: validates bearer tokens against the session store; rejects expired
- [ ] Step 4b — auth middleware: session refresh · kind: build · in-progress
- [ ] Step 5 — add rate limiting · kind: build
```

Same file, same plan. The finished portion is marked done with its Outcome; the remainder carries on. Step 5 is untouched.

---

## PROMOTE

**Trigger:** a step isn't a step at all — it's a chunk big enough to be its own child plan (multiple sessions, its own phases, its own seams).

Steps to perform:

1. Remove the step from the current plan's step list; leave a resolved pointer in its place (`- [x] Step N → promoted to Plan NN` — counts as resolved, not pending, for status).
2. Create the new child plan from the child template, with its own Goal, Phases & Steps, and Seams. **Number it one greater than the highest existing `NN` in `.plan/`** — run `ls .plan/` first to find it, don't assume "current + 1". Numbers are unique IDs, not execution order, so a mid-arc promotion may land at the end of the numbering; that's fine — the master Plans table records the real order.
3. **If `master-plan.md` does not exist yet, create it now** — you provably have >1 plan (the master plan creation rule). Add a row for the new plan to its Plans table.

**Before** (`02-api-plan.md`, no master plan yet):
```markdown
- [ ] Step 4 — build the whole auth system · kind: build · in-progress
```

**After PROMOTE** (`02` updated; new `03-auth-plan.md` created; `master-plan.md` born):
```markdown
# 02-api-plan.md
- [x] Step 4 → promoted to Plan 03 (auth)
```
```markdown
# master-plan.md  (newly created)
## Plans
| # | Plan | Status | Delivers |
|---|------|--------|----------|
| 02 | api | 🔨 in-progress | endpoints |
| 03 | auth | ⬜ not-started | authn/authz system |
```

---

## Deciding SPLIT vs PROMOTE

> Does it fit in one session **after splitting**? → **SPLIT.**
> Does it need its own phases / seams / multiple sessions? → **PROMOTE.**

The skill **proposes** on a signal (a step accreting sub-tasks, a step in-progress past its one session, research that revealed hidden scope) and the user confirms — or the user triggers either directly. Never auto-nest a sub-step tier; reshape instead.

---

## Promote a flat plan file to a folder

Distinct from PROMOTE above (which turns a *step* into a *plan*). This is when a single child plan file needs scratch/notes alongside it — convert `NN-name-plan.md` into a folder.

1. `mkdir .plan/NN-name/`
2. **Move** the plan file in unchanged → `git mv .plan/NN-name-plan.md .plan/NN-name/NN-name-plan.md` (or a plain `mv`). This is a relocation, **not** a content edit, so it does **not** go through the diff-review script.
3. Nothing else needs editing: links within `.plan/` reference the filename, which is unchanged. Add scratch files (`notes.md`, `spike-results.md`, …) inside the folder.

---

## Re-plan

After a **research** step finishes, ask whether its conclusion changes the downstream steps. If it does, rewrite those steps to reflect the finding (this is the whole point of a research step — it is allowed, even expected, to reshape what comes after). If it doesn't, leave them. This is a judgment call, not a mandatory ceremony — re-plan when it makes sense.

Filling a step's `Outcome` on completion is append-only narration (write-through, no diff), but any **re-plan edits to existing step text are substantive** → route those through the diff-review script. The conclusion must land in the plan **before** the next step starts, or it is lost at the next context reset.
