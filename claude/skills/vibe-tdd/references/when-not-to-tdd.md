# When not to TDD

Read this when you're unsure whether the current task is a TDD task at all, or when you want to engage seriously with the critique literature so you don't apply TDD where it's a net loss.

The base SKILL.md gives the short skip list. This file expands the rationale and engages the major critiques honestly. The goal isn't to defend TDD — it's to make the skill more credible by acknowledging the strongest objections and what they get right.

## Concrete skip signals

These are not "use judgment" — they're operationally verifiable signals that test-first will cost more than it earns.

- **Spike or throwaway code.** Time-boxed exploration whose purpose is to discard the code once you understand the problem. Writing tests entrenches code that should be thrown away. Signal: you've rewritten or discarded more than 30% of what you wrote in the last hour, or the task is explicitly labelled "spike" / "investigate."
- **Interface genuinely unknown.** *The Pragmatic Programmer* distinguishes tracer bullets (lean but production-bound) from prototypes (disposable, exploratory). TDD assumes you know enough to write a failing test first. If you're still asking "what should this function even return?", a test commits you to the wrong abstraction. Signal: you can't name the unit under test in one noun phrase without hedging.
- **Exploratory data analysis / notebooks.** EDA is iterative and visually driven. Test harnesses impose structure on work whose goal is to *discover* structure. The output is insight, not a deployable module.
- **UI tweaks and cosmetic changes.** Pixel layout, colors, copy. The cost of a fixture that mirrors DOM state or visual structure routinely exceeds the cost of a single manual verification. Signal: change verifies in under ten minutes by eye and contains zero business logic.
- **Performance tuning of already-correct hot paths.** The interface is correct; you're changing implementation for throughput. Tests fast enough for the red-green loop cannot reproduce production load. Use a benchmark harness.
- **One-shot scripts.** Code with no operational lifetime — runs once, produces output, gets archived. Test infrastructure has no return.
- **Characterization phase in legacy code.** Before adding new behavior to legacy code, you need to *understand* what's there. Writing characterization tests is archaeology, not TDD. The red-green-refactor loop starts after the safety net exists. See [legacy-code.md](legacy-code.md).

## The critique literature

These are not fringe positions. They represent serious arguments from experienced practitioners and deserve honest engagement.

### DHH — "TDD is dead. Long live testing." (2014)

David Heinemeier Hansson's [RailsConf 2014 keynote and blog post](https://dhh.dk/2014/tdd-is-dead-long-live-testing.html) made a specific architectural claim: the pressure to keep unit tests fast drives developers to mock collaborators heavily, which produces "a dense jungle of service objects, command patterns, and worse" — architecture that exists to satisfy the test harness rather than the domain. He called this **test-induced design damage** ([follow-up post](https://dhh.dk/2014/test-induced-design-damage.html)).

*What he gets right:* mock-heavy tests do calcify architecture. When every class is wrapped in an interface to enable substitution, you pay that indirection cost everywhere. The cure he proposes — rebalancing toward system tests — is genuinely useful for Rails-style applications where hitting the database is cheap.

*What he overstates:* the design damage comes from over-mocking, not from TDD itself. Testing through stable public interfaces rather than mocking internals is the direct answer to his critique. SKILL.md's "behavior over implementation" preference is exactly this answer.

### Beck / Fowler / Hansson — "Is TDD Dead?" hangout series (2014)

The [six-part video series](https://martinfowler.com/articles/is-tdd-dead/) produced more light than the original blog post. The unresolved core tension: Hansson believes TDD creates design pressure toward excessive indirection; Beck and Fowler contend the indirection comes from poor design choices. Neither side convinced the other. What emerged as consensus: self-testing code is valuable regardless of methodology; TDD works better in some contexts than others; developers should experiment rather than dogmatize.

### Rich Hickey — "Simple Made Easy" (Strange Loop 2011)

Hickey's [talk](https://www.infoq.com/presentations/Simple-Made-Easy/) is not primarily about TDD but contains a structural critique: "Every bug passes the type checker and passes all tests." His point: tests are a safety net, not a design tool. They confirm what you built; they cannot make a complex system simple.

*What he gets right:* TDD does not prevent architectural complexity. A heavily tested ball of mud is still a ball of mud. Implication for this skill: TDD works best on genuinely simple interfaces, and test coverage is not a substitute for thinking clearly about design.

### James O. Coplien — "Why Most Unit Testing is Waste" (2013)

Coplien's [paper](https://github.com/kinetronix/why-most-unit-testing-is-waste) originated from a client whose test code dwarfed production code and whose maintenance cost was consuming the team. His central claim: most unit tests mirror implementation rather than verify behavior, and they are disabled or deleted whenever the implementation changes — making them liabilities rather than assets.

His prescription is narrower than the title suggests: keep tests for stable, high-value behavioral contracts; delete tests that break on every refactor. He is not against testing — he is against treating test count as a quality metric.

*What he gets right:* test maintenance is a real cost. Tests that break on every refactor are technical debt. The "delete brittle tests" prescription is consistent with SKILL.md's "test would survive an internal refactor" checklist item.

### Ian Cooper — "TDD: Where Did It All Go Wrong?" (Devternity 2017)

Cooper's [talk](https://www.youtube.com/watch?v=EZ05e7EMOLM) is the most constructive corrective because it argues *from* Kent Beck's original intent. His claim: the industry misread "unit" to mean "class," which produced the toxic practice of one-test-per-class and mocking every collaborator. Beck's actual definition of "unit test" is "a test that runs in isolation from *other tests*," not "a test that covers exactly one class."

The trigger for adding a new test should be a new *behavior*, not a new method. A module's public API is the test boundary; multiple classes collaborating to implement a behavior are fine to exercise from a single test. Cooper traces the historical mutation that produced the brittle practice most people associate with TDD.

*Bottom line for this skill:* Cooper's reading of Beck reinforces SKILL.md's emphasis on testing behavior through public interfaces. He is the corrective to the bad practice, not an argument against the skill.

## Test smells (canonical names)

From Gerard Meszaros, [*xUnit Test Patterns*](http://xunitpatterns.com/) (Addison-Wesley, 2007):

- **Mystery Guest.** Test depends on external state (a file, a database row, an env var) invisible inside the test method. Reader can't understand the test without hunting for the fixture.
- **Eager Test.** A single method verifies multiple unrelated behaviors. One assertion failure hides the rest.
- **Assertion Roulette.** Multiple assertions with no failure messages — when it fails, you can't tell which assertion fired. Fix: one logical assertion per test, or descriptive `msg=` parameters.
- **Conditional Test Logic.** `if` or `try/except` inside the test body. The test exercises different paths on different runs; impossible to reason about what it actually verifies.
- **Test Code Duplication.** Copy-pasted setup and assertions across methods. A single fixture change requires editing many tests.
- **Fragile Fixture.** A shared fixture mutated by one test silently corrupts later tests. Common with class-level `setUp` accumulating mutable state.
- **Slow Tests.** Individual seconds compound to minutes at suite level, breaking the fast-feedback loop. Causes: real I/O, DB writes, network, `time.sleep()`. Use fakes and in-memory stores.
- **Flaky Tests.** Pass and fail non-deterministically. Root causes (rough descending frequency): async/timing races, shared mutable state between tests, ordering dependencies, network calls, unseeded randomness, real-clock reads, unordered iteration. A flaky test is worse than no test — it trains the team to ignore failures.

## Sources

- DHH, [TDD is dead. Long live testing.](https://dhh.dk/2014/tdd-is-dead-long-live-testing.html)
- DHH, [Test-induced design damage](https://dhh.dk/2014/test-induced-design-damage.html)
- Martin Fowler, [Is TDD Dead?](https://martinfowler.com/articles/is-tdd-dead/)
- Rich Hickey, [Simple Made Easy](https://www.infoq.com/presentations/Simple-Made-Easy/)
- James O. Coplien, [Why Most Unit Testing is Waste](https://github.com/kinetronix/why-most-unit-testing-is-waste)
- Ian Cooper, [TDD: Where Did It All Go Wrong?](https://www.youtube.com/watch?v=EZ05e7EMOLM)
- Gerard Meszaros, [*xUnit Test Patterns*](http://xunitpatterns.com/)
