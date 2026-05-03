# When to mock

**Contents**
- [Designing for mockability](#designing-for-mockability)
- [Python mocking craft](#python-mocking-craft)

Mock at **system boundaries** only:

- External APIs (payment, email, third-party HTTP)
- Databases (sometimes — prefer an in-memory fake or test database)
- Time and randomness
- Filesystem (sometimes — `tmp_path` is usually enough)

Don't mock:

- Your own classes / modules
- Internal collaborators
- Anything you control

The principle: own code is interface to be exercised; foreign code is boundary to be substituted.

## Designing for mockability

At system boundaries, design interfaces that are easy to substitute.

### 1. Use dependency injection

Pass external dependencies in rather than creating them internally:

```python
# Easy to substitute
def process_payment(order: Order, gateway: PaymentGateway) -> PaymentResult:
    return gateway.charge(amount=order.total, currency="usd")

# Hard to substitute
def process_payment(order: Order) -> PaymentResult:
    client = StripeGateway(api_key=os.environ["STRIPE_KEY"])
    return client.charge(amount=order.total, currency="usd")
```

Tests for the first form pass a fake; the second form requires patching `StripeGateway` and the environment.

### 2. Prefer SDK-style interfaces over generic fetchers

Create specific functions for each external operation instead of one generic function with conditional logic:

```python
from typing import Protocol

# GOOD — each method is independently fakeable
class UserApiClient(Protocol):
    def get_user(self, user_id: str) -> dict[str, str]: ...
    def get_orders(self, user_id: str) -> list[dict[str, str]]: ...
    def create_order(self, data: dict[str, str]) -> dict[str, str]: ...

class FakeUserApiClient:
    def get_user(self, user_id: str) -> dict[str, str]:
        return {"id": user_id, "name": "Alice"}

    def get_orders(self, user_id: str) -> list[dict[str, str]]:
        return [{"id": "o1", "total": "50"}]

    def create_order(self, data: dict[str, str]) -> dict[str, str]:
        return {"id": "o2", **data}

# BAD — one generic method forces conditional logic in fakes/mocks
class GenericApiClient(Protocol):
    def fetch(self, endpoint: str, options: dict[str, str] | None = None) -> dict: ...
```

The SDK approach means:

- Each fake returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint

## Python mocking craft

### `unittest.mock.patch` vs. `pytest-mock`

Both wrap the same underlying `MagicMock` machinery. The difference is ergonomic — `mocker` (from `pytest-mock`) reads linearly and cleans up automatically:

```python
# With pytest-mock — preferred in pytest codebases
def test_sends_confirmation_email(mocker: MockerFixture) -> None:
    send = mocker.patch("myapp.email.send_email")
    checkout(cart=filled_cart(), payment=valid_card())
    send.assert_called_once_with(to="user@example.com", subject="Order confirmed")
```

### Use `autospec` to catch typos

A bare `MagicMock()` accepts any attribute access and any call — it never fails on a typo. Always use `autospec=True` (or `create_autospec`) at boundaries:

```python
mocker.patch("myapp.gateways.PaymentGateway", autospec=True)

# vs. without autospec — both lines below pass even though "chrge" doesn't exist
gateway = mocker.MagicMock()
gateway.charge(amount=100)
gateway.chrge(amount=100)   # silent typo; would NOT raise
```

### "Patch where it's used"

The most common patching mistake is patching where the object is *defined* instead of where it's *imported and used*:

```python
# myapp/notifications.py — defines send_confirmation
def send_confirmation(...): ...

# myapp/checkout.py — imports and uses it
from myapp.notifications import send_confirmation

def checkout(...):
    ...
    send_confirmation(...)
```

```python
# WRONG — patches the definition site, but checkout.py already holds its own reference
mocker.patch("myapp.notifications.send_confirmation")

# CORRECT — patches the name at the call site
mocker.patch("myapp.checkout.send_confirmation")
```

Rule: the string passed to `patch()` is `"<module_that_uses_it>.<name>"`.

### Prefer fakes over mocks for stateful interactions

A hand-rolled fake is often more maintainable than a `MagicMock`:

- It enforces the real interface (no typo-silent attributes)
- It survives interface refactors (the fake breaks at import time, not silently at runtime)
- It can carry state, enabling end-to-end behavior tests without a real service

```python
from typing import Protocol

class PaymentGateway(Protocol):
    def charge(self, amount: int, currency: str) -> dict[str, str]: ...

# Production
class StripeGateway:
    def charge(self, amount: int, currency: str) -> dict[str, str]:
        return stripe.charge(amount=amount, currency=currency)

# Fake — no base class, just satisfies the Protocol
class FakeGateway:
    def __init__(self) -> None:
        self.charges: list[dict[str, int | str]] = []

    def charge(self, amount: int, currency: str) -> dict[str, str]:
        self.charges.append({"amount": amount, "currency": currency})
        return {"status": "ok", "charge_id": f"fake_{len(self.charges)}"}
```

Use the fake in tests; assert on its accumulated state when verifying side effects.

### Async mocking

`unittest.mock.AsyncMock` is required for async boundaries — a plain `MagicMock` is not awaitable:

```python
from unittest.mock import AsyncMock

async def test_retries_async_charge(mocker: MockerFixture) -> None:
    charge = mocker.patch("myapp.gateways.stripe_charge", new_callable=AsyncMock)
    charge.side_effect = [NetworkError(), {"status": "ok"}]

    result = await checkout_with_retry(cart=filled_cart())

    assert result.status == "confirmed"
```

For more pytest mocking patterns (`monkeypatch`, `mocker.spy`, etc.), see [pytest-craft.md](pytest-craft.md).
