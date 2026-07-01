# AGENTS.md

## Start here

Read `DESIGN.md` before changing architecture, public commands, identifiers,
state transitions, persistence, adapters, logging, hints, or skill behavior.
It is the canonical design document.

The current implementation is only a scaffold. Continue with the "Initial
vertical slice" described at the end of `DESIGN.md`. Do not implement network
adapters before workspace state, migrations, audit logging, claims, and recovery
are working.

## Build and test

```console
opam install . --deps-only --with-test
dune build @install
dune runtest
dune exec sandwalk -- about
```

Run `dune build @install` and `dune runtest` before handing off changes.

## Source map

- `lib/core/`: pure domain types, FSM, and invariants.
- `lib/protocol/`: versioned JSON protocols and agent response envelopes.
- `lib/store/`: SQLite migrations and transactions.
- `lib/runtime/`: Async processes, timeouts, locks, and filesystem operations.
- `bin/`: public command-line interface.

`lib/store/` and `lib/runtime/` are planned but do not exist yet.

## Engineering constraints

- Use the Jane Street ecosystem: Core, Core_unix, Async, Async_unix, and
  `ppx_jane`.
- Keep `sandwalk_core` independent of Async, SQLite, clocks, randomness, and
  the filesystem.
- Inject clocks and identifier generators.
- Represent domain failures as typed errors. Render concise messages only at
  the CLI boundary.
- Keep agent-facing JSON bounded and include at most one `next` command.
- Never invoke an LLM from Sandwalk.
- Keep external adapter communication on the versioned JSON protocol.
- Do not edit `sandwalk.opam`; Dune generates it from `dune-project`.
- Add expect tests for public command output and property tests for invariants.

## Documentation

Update `DESIGN.md` when an architectural decision changes. Avoid duplicating its
content in additional design documents.
