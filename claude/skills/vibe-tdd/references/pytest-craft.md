# pytest craft

pytest idioms that matter for the TDD inner loop. Read this when designing fixtures, deciding between `mocker` and `monkeypatch`, or setting up async tests.

**Contents**
- [Naming and structure](#naming-and-structure)
- [`@pytest.mark.parametrize`](#pytestmarkparametrize)
- [Fixtures over setup methods](#fixtures-over-setup-methods)
- [`conftest.py` scoping](#conftestpy-scoping)
- [Fixture scopes](#fixture-scopes)
- [Markers](#markers)
- [Built-in fixtures for side-effect testing](#built-in-fixtures-for-side-effect-testing)
- [`pytest.raises`](#pytestraises)
- [Indirect parametrization](#indirect-parametrization)
- [Async TDD](#async-tdd)
- [Test data builders](#test-data-builders)
- [Tooling for the TDD inner loop](#tooling-for-the-tdd-inner-loop)
- [Sources](#sources)

## Naming and structure

Follow `test_<behavior_description>` — name the observable outcome, not the method under test. The function name is the test's documentation.

```python
# BAD: names the implementation
def test_checkout_method() -> None: ...

# GOOD: names the behavior
def test_user_can_checkout_with_valid_cart() -> None: ...
def test_checkout_rejects_empty_cart() -> None: ...
```

Lay every test body out as **Arrange / Act / Assert**. One blank line between each section makes the boundary visible at a glance.

```python
def test_discount_applied_to_cart_total(cart: Cart, discount: Discount) -> None:
    # Arrange
    cart.add(Item(price=100))

    # Act
    result = apply_discount(cart, discount)

    # Assert
    assert result.total == 90
```

## `@pytest.mark.parametrize`

Use parametrize when the same behavior holds across multiple input/output pairs. Don't use it to enumerate implementation steps — that's horizontal slicing disguised as parametrization.

```python
import pytest

@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("  hello  ", "hello"),
        ("WORLD", "world"),
        ("  Mixed Case  ", "mixed case"),
    ],
    ids=["strips_whitespace", "lowercases", "both"],
)
def test_normalize_slug(raw: str, expected: str) -> None:
    assert normalize_slug(raw) == expected
```

Use `ids=` for readable test names in output rather than `raw0`, `raw1`.

## Fixtures over setup methods

Prefer fixtures over `setup_method` / `setUp`. Fixtures compose; setup methods don't. A fixture dependency is explicit in the function signature — you can see what a test needs without reading the class body.

```python
# conftest.py
import pytest
from myapp.models import Cart, Item

@pytest.fixture()
def empty_cart() -> Cart:
    return Cart()

@pytest.fixture()
def cart_with_item(empty_cart: Cart) -> Cart:
    empty_cart.add(Item(sku="WIDGET", price=50))
    return empty_cart
```

Fixture composition (one fixture requesting another) replaces inheritance hierarchies in setup code.

## `conftest.py` scoping

pytest discovers `conftest.py` files walking upward from the test file. Place fixtures at the narrowest scope that covers all consumers:

```
tests/
  conftest.py          # session-wide fixtures (db engine, httpx client)
  unit/
    conftest.py        # unit-only fixtures (in-memory fakes)
    test_cart.py
  integration/
    conftest.py        # integration-only fixtures (real DB connection)
    test_checkout.py
```

Never `import` from `conftest.py` — pytest handles discovery automatically.

## Fixture scopes

| Scope | Lifetime | When to use |
|-------|----------|-------------|
| `function` (default) | per test | mutable state, most things |
| `class` | per test class | shared setup within a class |
| `module` | per file | read-only shared objects |
| `session` | entire run | expensive setup (DB engine, network client) |

A narrower-scoped fixture must not request a broader-scoped one — pytest will warn.

## Markers

Register markers in `pyproject.toml` to avoid warnings and enable `--strict-markers`:

```toml
[tool.pytest.ini_options]
markers = [
    "slow: marks tests as slow (deselect with '-m not slow')",
    "integration: requires external services",
]
```

```python
@pytest.mark.slow
@pytest.mark.integration
def test_full_checkout_flow(real_payment_gateway: PaymentGateway) -> None: ...
```

## Built-in fixtures for side-effect testing

**`capsys`** — capture stdout/stderr without patching:

```python
def test_report_prints_summary(capsys: pytest.CaptureFixture[str]) -> None:
    print_report(orders=[Order(total=100)])
    captured = capsys.readouterr()
    assert "Total: 100" in captured.out
```

**`caplog`** — assert on log output without mocking the logger:

```python
import logging

def test_warns_on_empty_cart(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.WARNING):
        checkout(cart=Cart())
    assert "empty cart" in caplog.text
```

**`tmp_path`** — isolated filesystem per test (returns `pathlib.Path`):

```python
def test_export_writes_csv(tmp_path: pathlib.Path) -> None:
    dest = tmp_path / "orders.csv"
    export_orders(orders=[], dest=dest)
    assert dest.exists()
```

**`monkeypatch`** — patch attributes, environment variables, and `sys.path` without `unittest.mock.patch`. Reverts automatically after the test.

```python
def test_uses_env_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("STRIPE_KEY", "test_key_123")
    client = StripeClient.from_env()
    assert client.key == "test_key_123"
```

## `pytest.raises`

Assert that a specific exception is raised, and optionally inspect the message:

```python
def test_checkout_raises_on_expired_card() -> None:
    with pytest.raises(PaymentError, match="card expired"):
        checkout(cart=filled_cart(), payment=expired_card())
```

`match=` takes a regex applied to `str(exc)`. Prefer it over catching and re-asserting manually.

## Indirect parametrization

Use `indirect=` when the parameter needs to flow through a fixture before the test sees it:

```python
@pytest.fixture()
def user(request: pytest.FixtureRequest) -> User:
    return User(role=request.param)

@pytest.mark.parametrize("user", ["admin", "viewer"], indirect=True)
def test_profile_accessible_to_all_roles(user: User) -> None:
    assert get_profile(user=user) is not None
```

## Async TDD

Enable auto mode in `pyproject.toml` so every `async def test_*` runs without per-test decorators:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

Common pitfalls:

- **Forgotten `await` — silent pass.** An `async def` test that doesn't `await` the thing under test will pass vacuously, because the coroutine object compares truthy.

  ```python
  # BAD: coro never awaited — test passes vacuously
  async def test_broken() -> None:
      result = checkout(cart, gateway)   # missing await
      assert result is not None          # True — result is a coroutine object

  # GOOD
  async def test_fixed() -> None:
      result = await checkout(cart, gateway)
      assert result.status == "confirmed"
  ```

- **Leaked tasks.** Background tasks started inside a test outlive the event loop and produce `Task was destroyed but it is pending` warnings. Cancel and await them in teardown:

  ```python
  @pytest.fixture()
  async def background_worker() -> AsyncGenerator[Worker, None]:
      worker = Worker()
      task = asyncio.create_task(worker.run())
      yield worker
      task.cancel()
      with contextlib.suppress(asyncio.CancelledError):
          await task
  ```

- **`AsyncMock` for async boundaries.** A plain `MagicMock` is not awaitable. See [mocking.md](mocking.md).

## Test data builders

Past a certain test-suite size, fixtures sprawl and inline dicts diverge. A builder gives you safe defaults plus fluent overrides for the fields the test cares about:

```python
from dataclasses import replace
from typing import Self

@dataclass(frozen=True)
class User:
    id: int
    name: str
    email: str
    is_admin: bool

class UserBuilder:
    def __init__(self) -> None:
        self._data = User(id=1, name="Alice", email="alice@example.com", is_admin=False)

    def with_name(self, name: str) -> Self:
        self._data = replace(self._data, name=name)
        return self

    def admin(self) -> Self:
        self._data = replace(self._data, is_admin=True)
        return self

    def build(self) -> User:
        return self._data

def test_admin_can_delete() -> None:
    user = UserBuilder().admin().build()
    assert can_delete(user)
```

Introduce a builder when you notice yourself copying setup blocks between the second and third test for the same object. Don't pre-build builders speculatively.

## Tooling for the TDD inner loop

**coverage.py** as a floor, not a goal — 80–90% threshold catches forgotten paths; chasing 100% incentivizes testing trivial getters.

```toml
[tool.coverage.run]
source = ["src"]
branch = true

[tool.coverage.report]
fail_under = 85
exclude_lines = ["if TYPE_CHECKING:", "\\.\\.\\.", "@(abc\\.)?abstractmethod"]
```

**pytest-xdist** for parallel runs — `pytest -n auto` cuts time once you have ~50+ tests. Caveat: shared filesystem state will race.

**Watch mode** — `watchexec -e py -r -- pytest -x --tb=short`. The `-x` stops on first failure, which keeps the red-green loop sharp.

**pytest-testmon** — runs only tests affected by the source files you just changed, via Coverage.py data. Big speedup once a project's full suite takes more than a few seconds.

## Sources

- [pytest fixtures](https://docs.pytest.org/en/stable/how-to/fixtures.html)
- [pytest parametrize](https://docs.pytest.org/en/stable/how-to/parametrize.html)
- [pytest-mock](https://pytest-mock.readthedocs.io/en/latest/usage.html)
- [pytest-asyncio](https://pypi.org/project/pytest-asyncio/)
- [PEP 544 — Protocols](https://peps.python.org/pep-0544/)
- [Hynek Schlawack — Don't mock what you don't own](https://hynek.me/articles/what-to-mock-in-5-mins/)
- [Brian Okken — Python Testing with pytest, 2nd ed.](https://pragprog.com/titles/bopytest2/)
- [Nat Pryce — Test Data Builders](http://www.natpryce.com/articles/000714.html)
