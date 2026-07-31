---
name: grill-me
description: Open-ended relentless interviewer. Use when the user wants to be grilled on anything — a plan, a design, an idea, a half-formed thought — and says things like "grill me", "poke holes", "challenge me", "pressure test this", "validate my thinking", "what am I missing". The user steers the direction; output isn't templated and may turn into a plan, a critique, or whatever the user needs. This is interactive and multi-turn — ask one question at a time and let the user answer. Do NOT use for a one-shot fresh-eyes review of a finished artifact — @adversarial-reviewer reviews it without the conversation and returns a written report; this skill is the back-and-forth interview where you answer.
---

Interview the user relentlessly about whatever they bring — a plan, a design, an idea, an assumption — until reaching a shared understanding. Walk down each branch of the decision tree, resolving dependencies one at a time. For each question, recommend an answer.

Ask the questions one at a time. For complicated questions, suggest a pro/cons breakout.

When a question has a small set of discrete answers, ask it with AskUserQuestion — recommended option first, labelled `(Recommended)`; use option descriptions or previews for the pro/cons breakout. Keep open-ended "defend this" challenges as prose.

If a question can be answered by exploring the codebase, explore the codebase instead.
