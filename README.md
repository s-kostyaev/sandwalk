# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The initial end-to-end workflow includes workspace recovery, append-only plans,
durable exclusive claims, web and local-document search, immutable structured
Markdown or plain-text snapshots, exact excerpts, reviewed findings,
packet-driven continuation, and citation-safe finalization. Local discovery
uses `ugrep+`; the bundled local-file connector preserves ordinary source text
as `text/plain` and delegates rich documents to Docling. The Docling connector
retains Markdown headings and subheadings for `mq`, the original file, and
Docling's structured JSON and quality report.
Remote PDFs use the same normalization path. arXiv snapshots prefer the
structured HTML article for agents while always retaining the matching
versioned PDF for readers, with PDF-to-Docling fallback when HTML fails its
quality gate. YouTube snapshots use real source chapters when present and
otherwise retain a flat timestamped `transcript.txt`; the latter is never
disguised as Markdown. The YouTube adapter requires `yt-dlp` and downloads
captions rather than video or audio. Packet decisions can durably
reject irrelevant or blocked source candidates, and reviewed findings can be
explicitly reopened before drafting. See [`DESIGN.md`](DESIGN.md) for the
canonical architecture and invariants.

The portable agent skill is installed under
`share/sandwalk/skills/deep-research`.

## Runtime Tools

Sandwalk itself is built from the OCaml dependencies in `dune-project`, while
the bundled adapters expect a few command-line tools on `PATH` when their source
type is used:

- [`mq`](https://github.com/muqsitnawaz/mq) for querying structured Markdown
  snapshots before they are published and when agents inspect `text/markdown`
  documents.
- `rg` for local plain-text snapshots and flat transcripts.
- `ugrep+` for local source-root discovery.
- `ddgr` for the bundled web search adapter.
- `pandoc` and `curl` for web page/PDF retrieval and PDF export paths. PDF
  export additionally requires `xelatex` and fontconfig's `fc-match`; the
  exporter selects installed fonts with Russian Cyrillic support.
- `yt-dlp` for YouTube caption snapshots.

Docling-based local and PDF normalization also uses the adapter's pinned
Docling profile through `uv`.

## Development

Sandwalk uses OCaml, Dune, and the Jane Street library ecosystem.

```console
opam install . --deps-only --with-test
dune build
dune runtest
dune exec sandwalk -- about
```
