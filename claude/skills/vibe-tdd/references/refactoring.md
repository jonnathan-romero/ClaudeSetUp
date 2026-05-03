# Refactor candidates

After a TDD cycle, look for:

- **Duplication** → extract function or class
- **Long methods** → break into private helpers (keep tests on the public interface)
- **Shallow modules** → combine or deepen
- **Feature envy** → move logic to where the data lives
- **Primitive obsession** → introduce value objects (or `dataclass`-based wrappers)
- **Existing code** the new code reveals as problematic

## Fowler catalog (top 10 for TDD)

From Martin Fowler's [*Refactoring* (2nd ed.) catalog](https://refactoring.com/catalog/) — these are the refactorings that come up most in a green-phase cleanup:

| Refactoring | One-line definition |
|---|---|
| [Extract Function](https://refactoring.com/catalog/extractFunction.html) | Pull a code fragment into a named function to make intent explicit. |
| [Inline Function](https://refactoring.com/catalog/inlineFunction.html) | Replace a call to a trivially thin function with its body, removing indirection. |
| [Extract Variable](https://refactoring.com/catalog/extractVariable.html) | Assign a complex expression to a named variable to document its purpose. |
| [Change Function Declaration](https://refactoring.com/catalog/changeFunctionDeclaration.html) | Rename a function or restructure its parameters to communicate intent. |
| [Replace Temp with Query](https://refactoring.com/catalog/replaceTempWithQuery.html) | Replace a local variable with a method call so the derived value is computable anywhere. |
| [Combine Functions into Class](https://refactoring.com/catalog/combineFunctionsIntoClass.html) | Group functions that share data into a class to make the shared context explicit. |
| [Extract Class](https://refactoring.com/catalog/extractClass.html) | Split a class carrying multiple responsibilities into focused, single-purpose classes. |
| [Move Function](https://refactoring.com/catalog/moveFunction.html) | Relocate a function to the module where its data and collaborators live. |
| [Replace Conditional with Polymorphism](https://refactoring.com/catalog/replaceConditionalWithPolymorphism.html) | Replace `if/elif` type-switching with subclasses or a dispatch table. |
| [Decompose Conditional](https://refactoring.com/catalog/decomposeConditional.html) | Extract condition and branch bodies into named functions to expose the *why*, not just the *what*. |

## Discipline during refactor

- Run the suite after each step. A "small" rename can break an import elsewhere.
- Refactor on green. Never refactor while a test is red — finish the cycle first.
- One refactor per commit (or per stop point). Mixing rename + extract + behavioral change makes review impossible.
- If a refactor reveals a missing test, don't add it during the refactor. Note it, finish the refactor, then start a new RED → GREEN cycle for the missing test.
