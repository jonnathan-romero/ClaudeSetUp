# Where should this rule live?

The five Claude Code primitives, in order of decreasing automaticity:

| Primitive     | Invocation               | Visible to Claude? | Best for                                |
| ------------- | ------------------------ | ------------------ | --------------------------------------- |
| Hook          | event-triggered (system) | no                 | guardrails, must-fire enforcement       |
| CLAUDE.md     | always-on (advisory)     | yes                | project facts, rules                    |
| Skill         | model-invoked            | yes                | playbooks, multi-step workflows         |
| Slash command | user-invoked             | yes                | atomic actions you want timing on       |
| Subagent      | model-invoked            | yes (isolated)     | long delegated tasks, separate context  |

## Walk the tree

Ask the user one question: **what's the behavior or rule about?**

### 1. Must this fire deterministically, every time?

If yes — and Claude not seeing it is fine — it's a **hook**.

> Examples: run prettier on file save, block git push if tests fail,
> log all bash invocations.

Configure in `settings.json`. Hooks are invisible to Claude — they
just happen.

### 2. Is it a one-line rule about facts, conventions, or style?

If yes — and it's always true for this project — it's **CLAUDE.md**.

> Examples: "we use uv, never pip", "tests live in tests/", "the
> primary key on users is uuid".

Keep total file under 200 lines.

### 3. Is it a multi-step procedure with branches?

If yes — and you don't want it loaded every session — it's a **Skill**.

> Examples: "review a PR" (read diff → check style → check tests →
> post comment), "deploy to staging" (build → push → verify), "audit
> a CLAUDE.md" (this skill).

Skills load only when their description matches. Bulk content lives
in `references/`.

→ To author it, hand off to the `skill-best-practices` skill.

### 4. Is it an atomic action the user wants explicit control over?

If yes — and timing matters — it's a **slash command**.

> Examples: `/deploy`, `/clear-cache`, `/regenerate-fixtures`.

Slash commands fire only when typed. Best when the action has side
effects you don't want the model deciding to take.

### 5. Is it a long task that would bloat the main context?

If yes — and it's self-contained — it's a **subagent**.

> Examples: explore an unfamiliar codebase, run a 10-step refactor
> plan, do deep research and return a summary.

Subagents have isolated context windows. They return a summary; their
exploration debris doesn't pollute your session.

→ To author it, hand off to the `agent-best-practices` skill.

## Common confusions

- **"Run X every time" is a hook, not a CLAUDE.md rule.** CLAUDE.md is
  advisory; only hooks enforce.
- **"Help me do X" is a Skill, not CLAUDE.md.** Procedures don't
  belong in always-on memory.
- **"X happens at deploy" is a hook OR a slash command, not CLAUDE.md.**
  If automatic → hook. If user-invoked → slash command.
- **"How do I X in this codebase" is CLAUDE.md (a fact) OR a Skill
  (a procedure), depending on length.** One sentence → CLAUDE.md. A
  workflow → Skill.

## Default for personal preferences

If the rule is personal (not team-shared), put it in
`~/.claude/CLAUDE.md`, not the project file. Project CLAUDE.md is
git-tracked and team-shared.

## References

- https://code.claude.com/docs/en/skills.md
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/sub-agents.md
