# Deep modules

From John Ousterhout's *A Philosophy of Software Design*:

**Deep module** = small interface + lots of implementation

```
┌─────────────────────┐
│   Small interface   │  ← Few methods, simple params
├─────────────────────┤
│                     │
│                     │
│  Deep implementation│  ← Complex logic hidden
│                     │
│                     │
└─────────────────────┘
```

**Shallow module** = large interface + little implementation (avoid)

```
┌─────────────────────────────────┐
│       Large interface           │  ← Many methods, complex params
├─────────────────────────────────┤
│  Thin implementation            │  ← Just passes through
└─────────────────────────────────┘
```

When designing interfaces, ask:

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more complexity inside?

Deep modules are easier to test because they expose less surface area. Each test exercises a chunk of meaningful behavior through one well-named call. Shallow modules force tests that mirror their structure — many small tests, none of which verify a real capability on their own.
