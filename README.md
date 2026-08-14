# Sandwalk

Sandwalk is a deterministic research harness for AI agents. It coordinates
research workflows, records source provenance, validates evidence references,
and renders citations without invoking an LLM.

The initial end-to-end workflow includes workspace recovery, append-only plans,
durable exclusive claims, SearXNG web search, local-document and GNU Info
search, immutable structured Markdown or plain-text snapshots, exact excerpts,
immutable rich-document page visual evidence, reviewed findings, packet-driven
continuation, and citation-safe finalization.
Local discovery uses `ugrep+`; the bundled local-file connector preserves ordinary source text
as `text/plain` and delegates rich documents to Docling. The Docling connector
retains Markdown headings and subheadings for `mq`, the original file, and
Docling's structured JSON and quality report.
Xberg v1 is also available as an explicit fast adapter for simple local
documents. Its bounded profile retains Xberg's structured JSON and quality
report, disables result caching and remote/LLM features, and rejects structured
headings or tables that disappear from Markdown. Docling remains the default
for complex PDFs and rich formats.
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

## Normalizer choice

Docling remains the default for PDFs and rich formats. Xberg v1.0.14 was
re-evaluated against Docling 2.110.0 on the reproducible three-page
[`complex-structure.tex`](test/fixtures/complex-structure.tex) fixture, which
contains a PDF outline, four heading levels, repeated headers and footers, a
three-column table, and an explicit two-column reading order.

| Recovery signal | Docling profile | Xberg fast profile | Xberg layout profile |
|---|---|---|---|
| Title and numbered outline | Retained; all four top-level sections | Title omitted; two nested headings flattened | Title omitted; headings recovered but globally reordered |
| Three-column table | Retained as Markdown grid | Flattened into prose | Malformed sparse grid |
| Left-before-right columns | Retained | Retained | Right column moved before earlier content |
| Repeated furniture and ToC noise | Filtered from body | Leaked into body | Leaked into body |
| Paragraph-level heading | Flattened into prose | Retained | Retained |

This focused fixture is not a universal quality or speed benchmark. It does
show that Xberg's new layout path is not yet a safer default for Sandwalk's
hierarchy-sensitive agent snapshots. The bundled Xberg adapter therefore keeps
the fast non-layout profile and rejects structured tables that disappear from
Markdown.

## Installation

The latest release can be installed from its Git tag with opam:

```console
opam pin add sandwalk https://github.com/s-kostyaev/sandwalk.git#v0.4.0
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
- Docker for the default managed SearXNG web-search service. Sandwalk uses one
  per-user service on a loopback-only random port and can also use an explicitly
  configured external SearXNG endpoint.
- Python 3.10 or newer for the SearXNG service lifecycle helper and watchdog.
- `ddgr` for the explicit fallback web-search adapter. Sandwalk does not fall
  back to ddgr automatically when SearXNG fails.
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
- Poppler's `pdfinfo` and `pdftocairo` for optional page visual evidence.
  Sandwalk renders one full page at a fixed 144 DPI profile, bounds dimensions
  and output size, and never invokes a vision model itself. Non-PDF rich
  documents additionally require `soffice` or `libreoffice` on `PATH` (the
  standard macOS `/Applications/LibreOffice.app` installation is also detected);
  the bundled adapter performs an isolated headless conversion in a temporary
  profile before using Poppler. `shasum` revalidates the retained original
  before drafting.
- `uv` for the pinned Playwright browser fallback. Install its matching
  Chromium runtime once with
  `uv run --with playwright==1.55.0 playwright install chromium`.
- `yt-dlp` for YouTube caption snapshots.
- [`xberg`](https://github.com/xberg-io/xberg) for the optional explicit fast
  local-document adapter. Sandwalk's current profile is tested with Xberg
  v1.0.14; install the CLI with `brew install xberg-io/tap/xberg`.

Docling-based local and PDF normalization also uses its pinned profile through
`uv`.

## Web search service

SearXNG is Sandwalk's default web-search adapter. The first managed search
starts the per-user Docker service and pulls its missing pinned image; the
service is shared across workspaces. Managed mode uses only the local Docker
context, binds on loopback, and records the image digest and sanitized endpoint
metadata in search provenance. An external SearXNG endpoint can be selected
explicitly instead.

Service lifecycle is explicit and user-facing:

```console
sandwalk search-service start
sandwalk search-service stop
sandwalk search-service status
sandwalk search-service remove
sandwalk search-service update
```

On Linux the user configuration is `~/.config/sandwalk/searxng.json`; on
macOS it is `~/Library/Application Support/sandwalk/searxng.json`. Override
that path with `SANDWALK_SEARXNG_CONFIG`. A minimal customized configuration
is:

```json
{
  "schema": "sandwalk.searxng-config.v1",
  "mode": "managed",
  "idle_timeout_seconds": 900,
  "search": { "language": "all", "safe_search": 0 },
  "engines": {
    "profile": "research-v1",
    "enable": ["arxiv"],
    "disable": [],
    "keep_only": null
  }
}
```

For an existing service outside Sandwalk, use HTTPS unless it is on loopback:

```console
sandwalk search-service start \
  --mode external --endpoint https://search.example.org
```

External authentication is intentionally not supported in the first version.
The main environment overrides are `SANDWALK_SEARXNG_MODE`,
`SANDWALK_SEARXNG_URL`, `SANDWALK_SEARXNG_IDLE_TIMEOUT`,
`SANDWALK_SEARXNG_HOST_PORT`, `SANDWALK_SEARXNG_LANGUAGE`, and
`SANDWALK_SEARXNG_SAFE_SEARCH`; see `sandwalk search-service start -help` for
the matching flags and advanced settings. `stop` and `remove` normally wait
for active searches; their `--force` flag may interrupt them.

The default `research-v1` profile supports user engine `enable`/`disable`,
`keep_only`, and advanced YAML configuration. Configuration precedence is
defaults, user config, environment, then command-line flags. Changes create
desired-vs-active drift; an existing service continues using its active
profile until `search-service update` is requested. Idle shutdown uses one
detached watchdog with a 900-second default timeout; setting it to `0`
disables the watchdog. Parallel searches share an activity guard while
lifecycle operations take ownership locks.

## Visual evidence

When text extraction loses a diagram, page layout, handwritten annotation, or
other materially visual content, a claimed worker can render one retained
rich-document page into immutable evidence:

```console
sandwalk visual create --slug <slug> --claim <claim_id> \
  --snapshot <snapshot_id> --page <one-based-page> \
  --description-file <observation.md>
sandwalk finding attach --slug <slug> --claim <claim_id> \
  --finding <step>/<finding> --visual <visual_id> --relation supports
```

The input is resolved from the original or PDF artifact named by the snapshot
manifest; arbitrary filesystem paths are rejected. PDF is rendered directly.
RTF, Word, PowerPoint, Excel, OpenDocument, EPUB, FB2, Visio, and Publisher
inputs are converted to a temporary PDF by LibreOffice and then rendered by
Poppler. Formats without stable page semantics, such as MSG, are rejected.
Only `page.png` and its render manifest are published under
`artifacts/visuals/<visual_id>/`; the temporary PDF and private LibreOffice
profile are removed after Sandwalk independently checks the intermediate PDF's
path, type, signature, size, and SHA-256. The manifest binds the original hash
and format, transient PDF hash, complete render profile, implementation
versions, and image hash.
The description is a bounded agent observation and is explicitly not treated
as source text.

For non-PDF inputs, the image is evidence of LibreOffice's rendering of the
retained original. Missing fonts or differences from Microsoft Office or other
native applications can change pagination and appearance, so page numbers and
layout should be reviewed against the generated PNG rather than assumed from a
different viewer.

Findings with visual evidence use `sandwalk.finding-review.v2`. Review packets
include every `image_path`; a vision-capable reviewer must inspect each image
and copy the exact visual references into `reviewed_visuals`. This prevents a
text-only review from silently approving an unseen image. Writer packs preserve
the image path, source URL, snapshot, page number, and the non-source
description for downstream vision-capable models. A finding revision can bind
up to 256 distinct visual references; additional relations to the same visual
do not consume another slot.

## Development

Sandwalk uses OCaml, Dune, and the Jane Street library ecosystem.

```console
opam install . --deps-only --with-test
dune build @install
dune runtest
dune exec sandwalk -- about
```

Normalizer releases can be re-evaluated with the development-only
[normalizer comparison tool](dev/normalizer-comparison/README.md).
It rebuilds the controlled fixture, retains raw output from the production
Docling and Xberg profiles plus the experimental Xberg layout profile, and
generates deterministic JSON and Markdown comparisons under `_build/`. It has
no Dune install stanza and is not included in the runtime package.
