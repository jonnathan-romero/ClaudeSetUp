# vibe-tdd

A Claude Code skill that drives the red-green-refactor loop for
Python/pytest, with explicit countermeasures for the failure modes
unique to LLM agents writing tests. Builds on the integration-style
"behavior over implementation" foundation from Matt Pocock's TDD
skill, swapped to pytest, and extended with strategy, advanced
techniques, legacy-code work, and when-not-to-TDD guidance.

## Dates

- **Created:** 2026-05-03
- **Last modified:** 2026-05-03

## Source research

Authoritative URLs (indexed by supplement file):

**Foundations**
- Kent Beck, *Test-Driven Development: By Example* — https://www.amazon.com/Test-Driven-Development-Kent-Beck/dp/0321146530
- Steve Freeman & Nat Pryce, *Growing Object-Oriented Software, Guided by Tests* — http://www.growing-object-oriented-software.com/
- John Ousterhout, *A Philosophy of Software Design* (deep modules) — https://web.stanford.edu/~ouster/cgi-bin/aposd.php

**Strategy** (test-strategy.md)
- Martin Fowler, Practical Test Pyramid — https://martinfowler.com/articles/practical-test-pyramid.html
- Martin Fowler, On the Diverse and Fantastical Shapes of Testing — https://martinfowler.com/articles/2021-test-shapes.html
- Martin Fowler, Is TDD Dead? series — https://martinfowler.com/articles/is-tdd-dead/
- Kent C. Dodds, Write tests. Not too many. Mostly integration. — https://kentcdodds.com/blog/write-tests
- Spotify Engineering, Testing of Microservices — https://engineering.atspotify.com/2018/01/testing-of-microservices
- Pact — https://docs.pact.io/
- Justin Searls, Please Don't Mock Me — https://testdouble.com/insights/please-dont-mock-me

**Python / pytest craft** (pytest-craft.md, mocking.md, tests.md)
- pytest documentation — https://docs.pytest.org
- pytest-mock — https://pytest-mock.readthedocs.io/
- pytest-asyncio — https://pypi.org/project/pytest-asyncio/
- PEP 544 — Protocols — https://peps.python.org/pep-0544/
- Hynek Schlawack, Don't mock what you don't own — https://hynek.me/articles/what-to-mock-in-5-mins/
- Brian Okken, *Python Testing with pytest, 2nd ed.* — https://pragprog.com/titles/bopytest2/
- Nat Pryce, Test Data Builders — http://www.natpryce.com/articles/000714.html

**Advanced techniques** (advanced-techniques.md)
- Hypothesis — https://hypothesis.readthedocs.io/
- David MacIver, What is property-based testing? — https://hypothesis.works/articles/what-is-property-based-testing/
- Scott Wlaschin, Choosing properties for property-based testing — https://fsharpforfunandprofit.com/posts/property-based-testing-2/
- mutmut — https://mutmut.readthedocs.io/
- syrupy — https://syrupy-project.github.io/syrupy/
- atheris — https://github.com/google/atheris
- schemathesis — https://schemathesis.readthedocs.io/

**Legacy and limits** (legacy-code.md, when-not-to-tdd.md, refactoring.md)
- Michael Feathers, *Working Effectively with Legacy Code* — https://www.amazon.com/Working-Effectively-Legacy-Michael-Feathers/dp/0131177052
- Martin Fowler, *Refactoring* (2nd ed.) catalog — https://refactoring.com/catalog/
- Gerard Meszaros, *xUnit Test Patterns* — http://xunitpatterns.com/
- DHH, TDD is dead. Long live testing. — https://dhh.dk/2014/tdd-is-dead-long-live-testing.html
- Rich Hickey, Simple Made Easy — https://www.infoq.com/presentations/Simple-Made-Easy/
- James O. Coplien, Why Most Unit Testing is Waste — https://github.com/kinetronix/why-most-unit-testing-is-waste
- Ian Cooper, TDD: Where Did It All Go Wrong? — https://www.youtube.com/watch?v=EZ05e7EMOLM

**LLM pitfalls** (llm-pitfalls.md)
- Kent Beck, Augmented Coding: Beyond the Vibes — https://tidyfirst.substack.com/p/augmented-coding-beyond-the-vibes
- Pragmatic Engineer, TDD, AI agents and coding with Kent Beck — https://newsletter.pragmaticengineer.com/p/tdd-ai-agents-and-coding-with-kent
- Simon Willison, Red/green TDD — https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/
- Simon Willison, First run the tests — https://simonwillison.net/guides/agentic-engineering-patterns/first-run-the-tests/
- Paul Sobocinski / Thoughtworks, TDD with GitHub Copilot — https://martinfowler.com/articles/exploring-gen-ai/06-tdd-with-coding-assistance.html
- Alex Op, Forcing Claude Code to TDD — https://alexop.dev/posts/custom-tdd-workflow-claude-code-vue/
- Nizar Salehpour, Agentic TDD — https://nizar.se/agentic-tdd/
- Nizar Salehpour, tdd-guard — https://github.com/nizos/tdd-guard
- Rethinking the Value of Agent-Generated Tests — https://arxiv.org/html/2602.07900v2
- Meta Engineering, LLMs Are the Key to Mutation Testing — https://engineering.fb.com/2025/09/30/security/llms-are-the-key-to-mutation-testing-and-better-compliance/

## Changelog

- **2026-05-03** — initial version. SKILL.md (spine with 9 LLM failure modes inline)
  plus 11 supplementary files. Built on the integration-style TDD foundation from
  Matt Pocock's `tdd` skill (preserved file shapes for `tests.md`, `mocking.md`,
  `interface-design.md`, `deep-modules.md`, `refactoring.md`, with TS examples
  swapped to pytest/Python). Added six new supplements covering pytest craft,
  test strategy, advanced techniques, legacy code, when-not-to-TDD, and an
  extended LLM-pitfalls catalog. Research conducted by 5-agent team; raw
  reports preserved in `research/tdd-research/` of the parent repo.
