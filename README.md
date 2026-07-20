# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The initial end-to-end workflow includes workspace recovery, append-only plans,
durable exclusive claims, web, local-document, and GNU Info search, immutable
structured Markdown or plain-text snapshots, exact excerpts, reviewed findings,
packet-driven continuation, and citation-safe finalization. Local discovery
uses `ugrep+`; the bundled local-file connector preserves ordinary source text
as `text/plain` and delegates rich documents to Docling. The Docling connector
retains Markdown headings and subheadings for `mq`, the original file, and
Docling's structured JSON and quality report.
Remote PDFs use the same normalization path. arXiv snapshots prefer the
structured HTML article for agents while always retaining the matching
versioned PDF for readers, with PDF-to-Docling fallback when HTML fails its
quality gate. The default web dispatcher makes one bounded Playwright fallback
for JavaScript application shells, bot challenges, and non-PDF transport
failures; browser challenge, login, paywall, and HTTP-error pages are rejected.
YouTube snapshots use real source chapters when present and
otherwise retain a flat timestamped `transcript.txt`; the latter is never
disguised as Markdown. The YouTube adapter requires `yt-dlp` and downloads
captions rather than video or audio. Packet decisions can durably
reject irrelevant or blocked source candidates, and reviewed findings can be
explicitly reopened before drafting. See [`DESIGN.md`](DESIGN.md) for the
canonical architecture and invariants.

The portable agent skill is installed under
`share/sandwalk/skills/deep-research`.

## Installation

The latest release can be installed from its Git tag with opam:

```console
opam pin add sandwalk https://github.com/s-kostyaev/sandwalk.git#v0.2.0
```

Install only the runtime tools needed by the source and export adapters you
use. The browser fallback additionally needs its matching Chromium runtime:

```console
uv run --with playwright==1.55.0 playwright install chromium
```

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
- [`texiq`](https://github.com/s-kostyaev/texiq) for local GNU Info and active
  Emacs Info manuals. Search with `--adapter sandwalk-search-texiq`; matching
  `info://texiq/` hits select `sandwalk-fetch-texiq` automatically.
- [`qmd`](https://github.com/tobi/qmd) for an optional, fully local semantic
  discovery index. Build normalized document or node-per-document Info corpora
  with `sandwalk index build`, then search them with `--source-index`; Sandwalk
  issues one structured `vec:` query with `--no-rerank`, avoiding QMD's query
  expansion and reranking models, and verifies exact retained source artifacts
  again during fetch. Install the tested CLI with
  `npm install -g @tobilu/qmd@2.5.3`; it requires Node.js 22 or newer. The
  default multilingual Qwen3 embedding model is downloaded to QMD's local
  model cache on first use and occupies approximately 610 MiB. QMD selects
  Metal/CUDA/Vulkan automatically; use `qmd doctor` to verify acceleration.
  Set `QMD_FORCE_CPU=1` only when acceleration is genuinely unavailable or
  prohibited by the execution sandbox; CPU queries can be substantially
  slower.
- `pandoc` and `curl` for web page/PDF retrieval and PDF export paths. PDF
  export additionally requires `xelatex` and fontconfig's `fc-match`; the
  exporter selects installed fonts with Russian Cyrillic support.
- `uv` for the pinned Playwright browser fallback. Install its matching
  Chromium runtime once with
  `uv run --with playwright==1.55.0 playwright install chromium`.
- `yt-dlp` for YouTube caption snapshots.

Docling-based local and PDF normalization also uses its pinned profile through
`uv`.

## Development

Sandwalk uses OCaml, Dune, and the Jane Street library ecosystem.

```console
opam install . --deps-only --with-test
dune build @install
dune runtest
dune exec sandwalk -- about
```
