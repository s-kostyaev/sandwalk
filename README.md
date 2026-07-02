# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The initial end-to-end workflow includes workspace recovery, append-only plans,
leased claims, `ddgr` search, immutable `curl`/Pandoc snapshots, exact excerpts,
reviewed findings, and citation-safe finalization. See [`DESIGN.md`](DESIGN.md)
for the canonical architecture and invariants.

The portable agent skill is installed under
`share/sandwalk/skills/deep-research`.

## Development

Sandwalk uses OCaml, Dune, and the Jane Street library ecosystem.

```console
opam install . --deps-only --with-test
dune build
dune runtest
dune exec sandwalk -- about
```
