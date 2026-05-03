# Test strategy

Read this when deciding *which level* of test the next TDD cycle should drive at, or when feedback loops are degrading and you need to compose tests across layers.

**Contents**
- [The pyramid and its critics](#the-pyramid-and-its-critics)
- [The testing trophy](#the-testing-trophy)
- [Spotify's honeycomb](#spotifys-honeycomb)
- [Contract testing](#contract-testing)
- [London vs. Detroit schools](#london-vs-detroit-schools)
- [Deciding which level to test next](#deciding-which-level-to-test-next)
- [Feedback loops and TDD speed](#feedback-loops-and-tdd-speed)
- [Strategy-level anti-patterns](#strategy-level-anti-patterns)
- [Sources](#sources)

## The pyramid and its critics

Mike Cohn's testing pyramid (*Succeeding with Agile*, 2009): many unit tests at the base, fewer integration tests in the middle, very few UI/E2E tests at the top. Fowler codified this in [TestPyramid](https://martinfowler.com/bliki/TestPyramid.html) and [Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html).

DHH's 2014 [TDD is Dead. Long live testing.](https://dhh.dk/2014/tdd-is-dead-long-live-testing.html) attacked the heavy-unit-test form the pyramid often produces — controllers wrapped in hexagonal adapters, 60 lines of setup to test 5 lines of logic. The [Fowler/Beck/DHH series](https://martinfowler.com/articles/is-tdd-dead/) ended in qualified consensus: excessive mocking is the disease, not TDD itself. Justin Searls's framing in [Please Don't Mock Me](https://testdouble.com/insights/please-dont-mock-me): "nearly zero teams write expressive tests that establish clear boundaries, run quickly and reliably, and only fail for useful reasons."

The pyramid remains useful as a *cost* model. It breaks down when "unit" gets read as "isolated class with mocked collaborators" — that's the mockist overreach, not the original intent.

## The testing trophy

Kent C. Dodds reframed the hierarchy as a trophy in [Write tests. Not too many. Mostly integration.](https://kentcdodds.com/blog/write-tests):

- **Static analysis** (types, linting) — catches category errors for free
- **Unit tests** — for genuinely isolated logic (pure functions, parsers, algorithms)
- **Integration tests** — the thick middle: components plus their real collaborators, exercised through public interfaces
- **E2E tests** — a few smoke paths through the full stack

Guiding principle: *the more your tests resemble how the software is used, the more confidence they give you.*

## Spotify's honeycomb

Spotify's [Testing of Microservices](https://engineering.atspotify.com/2018/01/testing-of-microservices) describes a honeycomb with three bands:

- **Integration tests** (largest) — verify the service against its interaction points
- **Implementation detail tests** (small) — for genuinely complex internal logic
- **Integrated tests** (ideally zero) — depend on a running external system; failures are ambiguous

The honeycomb argument: in a microservice, the hard part is the interfaces, not internal logic. Excessive unit tests in a small service create friction.

The **ice cream cone** is the antipattern: minimal unit tests, some integration, and a thick layer of manual or UI-driven E2E tests. Symptoms: slow feedback, flaky suites, high maintenance cost, tests that tell you *something* is broken but not *where*.

## Contract testing

Between integration (a service tested against a stub of its dependency) and full E2E sits **contract testing**. [Pact](https://docs.pact.io/) implements consumer-driven contracts: the consumer declares what it expects from a provider; the provider verifies against that contract in its own CI. Neither side needs the other deployed.

Use when two services own separate halves of an API boundary and you can't spin both up simultaneously without unacceptable cost.

## London vs. Detroit schools

**Detroit / Chicago (classicist, inside-out).** Start at the domain core. Build real objects, exercise them through real collaborators. Use test doubles only at true system boundaries (external APIs, clocks, filesystems). Tests assert on state and output. Produces *sociable* tests — they survive internal refactors.

**London (mockist, outside-in).** Start from an acceptance test, drive design inward. Mock immediate collaborators to discover their interfaces. Tests are *solitary* — failures localize precisely. From Freeman & Pryce's [*Growing Object-Oriented Software, Guided by Tests*](http://www.growing-object-oriented-software.com/) (Addison-Wesley, 2009).

**Where they converge.** Both schools agree tests should verify behavior. The London school's mocks are a design tool for discovering interfaces, not a permanent mechanism for coupling tests to call counts. The pathology DHH attacked — mocking internals, asserting on invocations, indirection-for-testability — is a corruption of London style, not its intention.

**For this skill: Detroit by default.** Aligns with `SKILL.md`'s "behavior over implementation" preference and avoids the brittleness tax of mock-heavy suites. Reach for London-style only when designing an unfamiliar object graph top-down, where you genuinely want to discover collaborator interfaces before committing to implementations.

## Deciding which level to test next

**Write an integration test when:**
- The behavior involves multiple collaborators you control.
- You want confidence about how components combine at runtime.
- Refactoring speed matters more than pinpoint failure localization.

**Write a unit test when:**
- The logic is genuinely isolated: a pure function, a parser, a complex algorithm.
- Reaching the logic through a full integration path is expensive or slow.
- You need many edge-case permutations cheaply (parametrize over a pure function).

**Write an E2E test when:**
- The path is a critical user journey that must be verified through the real UI or real API surface.
- No lower-level test can cover the rendering or routing wiring.
- You are writing at most one test per major workflow, not per edge case.

**Write a contract test when:**
- Two services own separate halves of an API boundary.
- You cannot spin up both services in CI without unacceptable cost or flakiness.
- You need to detect breaking changes in a provider before deployment.

**Default: prefer integration.** Step down to unit only when the integration path is expensive or permutations demand it. Step up to E2E only for coverage that has no cheaper substitute.

## Feedback loops and TDD speed

TDD's red-green loop requires fast feedback. When tests take minutes, the loop breaks: you stop running them on every change, batch cycles, and lose the discipline of one-test-at-a-time.

Practical targets:
- Unit tests: under 10 ms each; entire unit suite under 5 s
- Integration tests: under 500 ms each; a feature's suite under 2 min
- E2E tests: minutes are tolerable because they run infrequently, outside the inner loop

Tools:
- **pytest-testmon** — runs only tests affected by changed source files. Big speedup at scale. ([GitHub](https://github.com/tarpas/pytest-testmon))
- **pytest-xdist** — parallel execution across CPUs. Watch out for shared mutable state.
- **Markers** — tag slow tests; run unmarked set during the inner loop, full set in CI.
- **nx affected** (monorepos) — test only packages touched by the diff.

## Strategy-level anti-patterns

**Redundant cross-layer coverage.** An integration test exercises the full checkout flow; a unit test re-verifies the same discount logic in isolation. When the logic changes, both fail. Test each behavior at the level that gives the most meaningful signal; don't replicate.

**"Double-entry bookkeeping" tests.** Mock setup that re-states every call in the production code, longer than the code under test. Adds maintenance cost; breaks on every refactor regardless of whether behavior changed. ([James Mead, 2006](https://jamesmead.org/blog/2006-10-11-developer-tests-and-double-entry-book-keeping))

**Snapshot avalanches.** Hundreds of large snapshots produce suites that fail constantly, require mechanical approval on every incidental change, and give almost no signal. Limit snapshots to small, stable structures.

**Redundant E2E coverage.** E2E tests covering scenarios already exercised by integration tests add CI time without confidence. E2E should confirm wiring (routing, rendering, auth), not re-verify business logic.

## Sources

- [Practical Test Pyramid — Fowler](https://martinfowler.com/articles/practical-test-pyramid.html)
- [Write tests. Not too many. Mostly integration. — Dodds](https://kentcdodds.com/blog/write-tests)
- [Testing of Microservices — Spotify](https://engineering.atspotify.com/2018/01/testing-of-microservices)
- [Is TDD Dead? — Fowler/Beck/Hansson](https://martinfowler.com/articles/is-tdd-dead/)
- [GOOS — Freeman & Pryce](http://www.growing-object-oriented-software.com/)
- [Please Don't Mock Me — Searls](https://testdouble.com/insights/please-dont-mock-me)
- [Pact](https://docs.pact.io/)
- [pytest-testmon](https://github.com/tarpas/pytest-testmon)
