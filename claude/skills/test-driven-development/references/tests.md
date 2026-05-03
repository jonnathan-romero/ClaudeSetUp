# Good and bad tests

## Good tests

**Integration-style.** Test through real interfaces, not mocks of internal parts.

```python
# GOOD: tests observable behavior
async def test_user_can_checkout_with_valid_cart(
    fake_gateway: FakeGateway,
) -> None:
    cart = Cart()
    cart.add(product)

    result = await checkout(cart=cart, payment_method=fake_gateway)

    assert result.status == "confirmed"
```

Characteristics:

- Tests behavior users / callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Bad tests

**Implementation-detail tests.** Coupled to internal structure.

```python
# BAD: tests implementation details
async def test_checkout_calls_payment_service_process(
    mocker: MockerFixture,
) -> None:
    mock_payment = mocker.patch("myapp.checkout.payment_service")
    await checkout(cart=cart, payment=payment)
    mock_payment.process.assert_called_once_with(cart.total)
```

Red flags:

- Mocking internal collaborators
- Testing private methods (`_helper`, `__internal`)
- Asserting on call counts / order
- Test breaks when refactoring without behavior change
- Test name describes HOW, not WHAT
- Verifying through external means instead of the interface

```python
# BAD: bypasses the interface to verify state directly
async def test_create_user_saves_to_database(db: AsyncSession) -> None:
    await create_user(name="Alice")
    row = await db.execute(select(UserRow).where(UserRow.name == "Alice"))
    assert row.scalar_one_or_none() is not None

# GOOD: verifies through the interface
async def test_create_user_makes_user_retrievable(
    repo: InMemoryUserRepo,
) -> None:
    user = await create_user(name="Alice", repo=repo)
    retrieved = await get_user(user_id=user.id, repo=repo)
    assert retrieved.name == "Alice"
```

The GOOD version above relies on an in-memory fake (`InMemoryUserRepo`) rather than the real database. That's a design choice — the test exercises the same public path the production code uses, and the fake is interchangeable with the real implementation. See [mocking.md](mocking.md) and [interface-design.md](interface-design.md) for how to set this up with `typing.Protocol`.

## One logical assertion per test

A test should have one reason to fail. Multiple `assert` statements are fine when they describe a single behavior:

```python
# OK — these assertions together describe the single behavior "confirmed checkout"
def test_checkout_confirms_with_charge_and_receipt(fake_gateway: FakeGateway) -> None:
    result = checkout(cart=filled_cart(), gateway=fake_gateway)

    assert result.status == "confirmed"
    assert result.receipt_id is not None
    assert len(fake_gateway.charges) == 1
```

But a test that verifies *unrelated* behaviors in a single body is a smell — split it. If one assertion fails, the others won't run, and you lose information.

## Test names as specification

Test function names should read as a sentence about the system:

```python
# GOOD
def test_checkout_rejects_empty_cart() -> None: ...
def test_discount_applied_to_cart_total() -> None: ...
def test_admin_can_delete_any_post() -> None: ...

# BAD
def test_checkout_method() -> None: ...
def test_user_1() -> None: ...
def test_handles_edge_case() -> None: ...
```

The first form makes the test suite a readable specification of the system's capabilities. The second form makes you read the body to know what's tested.
