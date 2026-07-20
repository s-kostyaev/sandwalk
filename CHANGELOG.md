# Changelog

## Unreleased

## 0.2.0 — 2026-07-20

### Local sources

- Add bundled `texiq` search and fetch adapters for exact GNU Info node
  snapshots, including active Emacs Info manuals and automatic
  `info://texiq/` fetch dispatch.
- Add reusable, fully local semantic indexes for normalized documents and GNU
  Info nodes through the optional QMD runtime. Sandwalk records the exact
  embedding model and implementation version, performs structured vector-only
  search without query expansion or reranking, and resolves each hit back to a
  verified immutable source artifact before it can become evidence.

## 0.1.0 — 2026-07-12

Initial public release of Sandwalk's deterministic research harness.

### Research workflow

- Durable SQLite workspaces with migrations, audit logging, recovery packets,
  append-only plans, exclusive claims, checkpoints, reviewed findings, and
  citation-safe finalization.
- Packet-driven continuation with bounded agent context, integrity checks,
  durable source rejection, and finding repair.
- Local workspace discovery and explicit recovery without relying on chat
  history or an implicit latest workspace.

### Sources

- Versioned search and fetch protocols for web and local sources.
- Immutable structured snapshots for Markdown, plain text, PDFs, rich local
  documents, arXiv articles, and YouTube captions.
- Docling-backed OCR and hierarchy recovery, exact-version arXiv PDFs, and
  timestamped YouTube transcript evidence.
- A bounded Playwright fallback for JavaScript application shells and bot
  challenges, with login, paywall, challenge, and HTTP-error rejection.

### Output

- Stable citation rendering and reviewed report assembly.
- PDF export with Cyrillic-capable font selection, internal citation links,
  wide-table scaling, and automatic landscape pages where needed.
