# Interface design for testability

Good interfaces make testing natural.

## 1. Accept dependencies, don't create them

```python
# Testable
def process_order(order: Order, payment_gateway: PaymentGateway) -> OrderResult: ...

# Hard to test
def process_order(order: Order) -> OrderResult:
    gateway = StripeGateway(api_key=os.environ["STRIPE_KEY"])
    ...
```

The first form takes the gateway as an argument; tests pass a fake. The second form constructs the gateway inside, requiring environment setup or patching to substitute it.

## 2. Return results, don't produce side effects

```python
# Testable — pure function, easy to assert on
def calculate_discount(cart: Cart) -> Discount: ...

# Hard to test — mutates input, no return value
def apply_discount(cart: Cart) -> None:
    cart.total -= compute_discount_amount(cart)
```

Pure functions are testable by inspection. Side-effecting functions force tests to verify state changes through whatever interface exposes them, which often forces awkward setups.

## 3. Use `Protocol` for structural typing at boundaries

`typing.Protocol` (PEP 544) lets a fake satisfy an interface without inheriting from a base class. Production and test implementations are interchangeable:

```python
from typing import Protocol

class UserRepo(Protocol):
    def save(self, user: User) -> None: ...
    def get(self, user_id: str) -> User: ...

class PostgresUserRepo:
    def __init__(self, conn): ...
    def save(self, user: User) -> None: ...
    def get(self, user_id: str) -> User: ...

class InMemoryUserRepo:
    def __init__(self) -> None:
        self._store: dict[str, User] = {}
    def save(self, user: User) -> None:
        self._store[user.id] = user
    def get(self, user_id: str) -> User:
        return self._store[user_id]

# Both satisfy UserRepo without explicit inheritance
def register(name: str, repo: UserRepo) -> User: ...
```

Protocols also work as type-only contracts — you can check structural conformance with `mypy` / `pyright` without changing the runtime class hierarchy.

## 4. Small surface area

- Fewer methods → fewer tests needed
- Fewer parameters → simpler test setup
- Fewer overloads → fewer paths to verify

When an interface grows, ask: can this be split? Can defaults push complexity inside? See [deep-modules.md](deep-modules.md) for the principle that drives this — simple interfaces with rich implementations beat the inverse.
