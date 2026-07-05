# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The initial end-to-end workflow includes workspace recovery, append-only plans,
durable exclusive claims, web and local-document search, immutable structured
Markdown snapshots, exact excerpts, reviewed findings, packet-driven
continuation, and citation-safe finalization. Local discovery uses `ugrep+`;
the bundled default Docling connector retains Markdown headings and subheadings
for `mq`, the original file, and Docling's structured JSON and quality report.
Remote PDFs use the same normalization path. arXiv snapshots prefer the
structured HTML article for agents while always retaining the matching
versioned PDF for readers, with PDF-to-Docling fallback when HTML fails its
quality gate. Packet decisions can durably
reject irrelevant or blocked source candidates, and reviewed findings can be
explicitly reopened before drafting. See [`DESIGN.md`](DESIGN.md) for the
canonical architecture and invariants.

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
