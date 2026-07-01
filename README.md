# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The project is in its initial design and scaffolding stage. See
[`DESIGN.md`](DESIGN.md) for the current architecture.

## Development

Sandwalk uses OCaml, Dune, and the Jane Street library ecosystem.

```console
opam install . --deps-only --with-test
dune build
dune runtest
```
