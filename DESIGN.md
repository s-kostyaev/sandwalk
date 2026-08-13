# Sandwalk design

Status: draft v0.1

## Purpose

Sandwalk is a deterministic command-line harness for research performed by AI
agents. It owns workflow state, source provenance, evidence relationships,
validation gates, recovery data, and final citation rendering. It never invokes
an LLM.

Sandwalk ships an agent-agnostic deep-research skill. The skill teaches agents
the workflow while Sandwalk enforces it mechanically.

## Goals

- Prevent reports from citing sources that Sandwalk did not retrieve.
- Preserve an auditable path from a finding to exact source excerpts.
- Support one agent or several parallel agents without changing the workflow.
- Allow a failed agent session to be replaced without depending on its chat
  transcript.
- Keep agent responses small and provide at most one recommended next command.
- Keep source artifacts available as ordinary files for `mq`, `grep`, and
  partial reads.
- Keep the core independent of any agent product or tool-call protocol.

## Non-goals

- Sandwalk does not decide whether a claim is true.
- Sandwalk does not judge whether evidence semantically supports a claim.
- Sandwalk does not spawn agents or depend on a particular subagent API.
- Sandwalk does not hide the filesystem behind a proprietary content API.
- Sandwalk does not require search, fetch, OCR, or document-conversion adapters
  to be implemented in OCaml.

## Terminology and public identifiers

A slug identifies one research workspace. There is no public run identifier.
Independent research attempts use different slugs.

Slugs are canonical path components: 1–63 lowercase ASCII letters or digits,
with single hyphens allowed only between alphanumeric groups.

Public opaque references exist only when possession proves provenance:

- `hit_...`: a result returned by a search adapter.
- `snap_...`: an immutable retrieved and normalized document snapshot.
- `excerpt_...`: an exact, validated fragment of one snapshot.
- `visual_...`: an immutable rendered PDF page used as visual evidence.
- `claim_...`: an exclusive capability for an agent working on one plan step.

Plan steps and findings use human-readable keys. Logical sources, evidence
bundles, reviews, queue rows, and event identifiers remain internal.

Initial plan-step keys use the same canonical path-safe form as slugs. Step
titles are trimmed, non-empty text of at most 200 bytes.

## Workspace

The workspace root is:

```text
<directory-prefix>/<slug>/
├── database/
│   └── sandwalk.sqlite3
├── artifacts/
│   ├── snapshots/
│   ├── excerpts/
│   ├── visuals/
│   ├── resume/
│   │   └── workspace.md
│   ├── work/
│   │   ├── current.json
│   │   └── current-input.*
│   └── temporary/
├── exports/
│   ├── research-plan.md
│   ├── writer-pack.md
│   ├── report.md
│   ├── sources.md
│   └── report.pdf
└── logs/
    └── events.jsonl
```

The directory prefix is resolved in this order:

1. `--directory-prefix`
2. `SANDWALK_DIRECTORY_PREFIX`
3. configuration
4. a platform-appropriate default

Commands must identify the workspace explicitly by slug or path. Sandwalk must
not select an implicit `latest` workspace.

```console
sandwalk init --slug <slug> [--directory-prefix <path>]
sandwalk list [--directory-prefix <path>]
sandwalk status --slug <slug> [--directory-prefix <path>]
sandwalk resume --slug <slug> [--directory-prefix <path>]
sandwalk continue --slug <slug> [--directory-prefix <path>]
```

SQLite uses WAL mode and a configurable busy timeout. Independent commands use
short transactions. Network and adapter processes must never run inside a
database transaction.

`resume`, `next`, and `continue` are recovery boundaries. They apply pending schema
migrations in a short transaction before reading state, so a replacement agent
never has to infer current semantics from a legacy schema. `status` remains a
read-only observation and may report an older supported schema until recovery
or the next mutation upgrades it.

## Workflow state machine

```text
initialized
  → scoping
  → reconnaissance
  → planning
  → researching
  → evidence-review
  → drafting
  → draft-review
  → finalizing
  → completed
```

Reconnaissance is optional or required according to workspace policy. Before
the plan is sealed, planning may reopen reconnaissance:

```text
reconnaissance → planning → reconnaissance
```

After plan sealing, a new direction is added through a plan extension rather
than by reopening preliminary reconnaissance.

Every state transition is checked in the pure domain library and repeated as a
database constraint where practical.

## Reconnaissance

Reconnaissance supports broad search and retrieval before plan sealing. It
records terms, themes, authoritative domains, and scope boundaries.

```console
sandwalk recon start --slug <slug> --goal-file <path>
sandwalk search --slug <slug> --query <query> [--claim <claim>]
sandwalk search --slug <slug> --query <query> --source-root <path> \
  [--claim <claim>]
sandwalk fetch --slug <slug> <hit-ref>
sandwalk recon add-observation --slug <slug> ...
sandwalk recon finish --slug <slug> --summary-file <path>
sandwalk snapshot promote --slug <slug> --claim <claim> <snapshot>
```

Snapshots discovered during reconnaissance are ordinary immutable snapshots.
They are tagged with their purpose and may later be promoted to a research plan
step without being fetched again. Promotion creates a separate, append-only
ownership association; it does not rewrite snapshot content or provenance.
Repeating promotion to the same step is idempotent, and promotion to a different
step is rejected. Reconnaissance observations are not findings and cannot pass
report validation by themselves.

Searches in `researching` require the active step claim. Adapter execution
occurs before the short persistence transaction.

Fetches in `researching` likewise require the active claim for the step that
owns the hit. The adapter runs outside SQLite, writes into
`artifacts/temporary/`, and must publish a valid manifest and non-empty
Markdown document. Sandwalk then atomically renames that directory to its
immutable `snap_...` path before recording snapshot provenance in one short
transaction.

## Plan

The plan is canonical structured state in SQLite. `exports/research-plan.md` is
an atomically regenerated, read-only projection for humans and agents.

```console
sandwalk plan set-objective --slug <slug> --file <path>
sandwalk plan add-step --slug <slug> --key <key> --title <title> [--optional]
sandwalk plan add-dependency --slug <slug> <step> --on <dependency>
sandwalk plan extend --slug <slug> --key <key> --title <title> \
  --reason-file <path> [--on <dependency>]...
sandwalk plan list --slug <slug>
sandwalk plan validate --slug <slug>
sandwalk plan seal --slug <slug>
```

The initial model is a flat directed acyclic graph. Nested substeps are outside
the first release.

The first plan mutation in a workspace without reconnaissance advances it
through the legal `initialized → scoping → planning` transitions. A mutation
from `scoping` or `reconnaissance` advances to `planning`; later phases reject
direct plan mutation.

Plan validation requires at least one step and records the exact plan revision.
Appending a step increments the revision, making an earlier validation stale.
Repeated validation of an unchanged revision is idempotent.

Plan sealing requires validation of the current revision, records that revision,
and performs the checked `planning → researching` transition. Repeating a seal
of the same revision is idempotent.

After work begins, existing steps are immutable. While the workspace remains in
`researching`, `plan extend` atomically appends exactly one step, its optional
edges to existing steps, and a non-empty reason of at most 64 KiB. The operation
advances, validates, and seals the append-only plan revision in one transaction,
so a new step is never claimable from an intermediate revision. Extension
history is included in `plan list` and the human-readable plan projection.

## Claims and recovery

A plan step is the durable unit of work. A claim is an exclusive, durable
capability to execute it. There is no public work identifier or permanent
worker identifier.

```console
sandwalk step claim --slug <slug> --step <key>
```

Claim identifiers contain the `claim_` prefix and 128 bits of random entropy.
A claim remains active until its step completes or an explicit state transition
suspends it. Wall-clock time never changes claim validity or any domain state.
Timestamps are provenance metadata only.

Schemas 5–20 stored lease deadlines and an `expired` state. Migration 21 maps
legacy `expired` executions to `suspended`. The old lease columns remain inert
for migration compatibility and must never be read to make a domain decision.

```text
pending | suspended | blocked → claimed → completed
```

Every mutating research command associated with a step accepts its claim.
Commands from a claim that is not the step's current active capability are
rejected. Interrupted agents recover the same claim identifier from `resume`;
they do not need to acquire a replacement because time elapsed. A replacement
session starts only after the prior worker has stopped; two live workers must
not share one claim capability.

Agents record semantic checkpoints at meaningful milestones:

```console
sandwalk step checkpoint --slug <slug> --claim <claim> \
  --summary-file <path> --next-file <path>
sandwalk step complete --slug <slug> --claim <claim>
```

Checkpoint files are non-empty and individually limited to 64 KiB. Saving a
checkpoint requires the active claim and records semantic recovery state. It
does not alter claim validity.

Completing a step requires at least one current finding, current semantic
reviews for every finding, and no `unsupported` or `contradicted` verdicts. It
atomically marks the step and claim completed. Completing the last required
step performs the checked `researching → evidence-review` transition; optional
unfinished steps do not block that transition.

A bad semantic review discovered before drafting can be repaired explicitly:

```console
sandwalk finding repair --slug <slug> --finding <step>/<finding> \
  --reason-file <path>
```

Repair is allowed only for a completed step while the workspace is still
`researching` or `evidence-review`, and is rejected if a dependent step already
completed. It suspends all active claims, reopens the target step as
`suspended`, copies the finding statement into a new draft revision without
evidence, and durably rejects the previous revision's excerpts for that step.
The ordinary `continue` loop then reclaims the earliest dependency-ready step
and gathers fresh evidence. The reason and revision boundary are append-only.

Sandwalk always creates a mechanical resume pack from durable state and logs.
An explicit checkpoint adds the agent's current interpretation, hypotheses, and
next intended action.

Before plan steps exist, `resume` atomically regenerates
`artifacts/resume/workspace.md` with workspace-level durable state. Once a step
is selected, the same pack format is enriched with its checkpoint and entities.

A resume pack is bounded Markdown containing:

- the step objective and scope;
- the latest checkpoint;
- durable entities created by previous attempts;
- commands after the checkpoint;
- the last error or blocker;
- unresolved items;
- relevant artifact paths;
- one recommended next action and why it applies;
- one recommended next command.

Large artifacts and complete histories are referenced by path rather than
inlined. The current phase, active claims, and durable entities are
authoritative. Audit entries and prior errors are explicitly labeled as
historical and never override current state.

### Packet-driven continuation

`continue` is the primary continuation boundary for an agent session. It
derives one legal forward action from current durable state and atomically
replaces `artifacts/work/current.json` with a bounded
`sandwalk.work.v1` packet. The packet separates immutable mechanical context
under `fixed` from the semantic fields the agent may fill under `editable`.
It includes exact artifact paths, allowed enum values, and complete nested
review protocols where applicable. Research packets also carry the canonical
research objective and current step title so semantic choices are never made
from an opaque claim identifier.

The agent reads the referenced artifacts, edits only `editable`, and invokes
the single returned command:

```console
sandwalk apply --file <workspace>/artifacts/work/current.json
```

`apply` accepts only the current packet at the path derived from its embedded
workspace identity. An integrity hash covers every field except `editable`, so
changing fixed context invalidates the packet before a child command runs. The
hash remains unchanged when the agent fills `editable`; packet validation
failures distinguish malformed or unsupported packets, modified fixed context,
and an invalid current-packet path, and direct the agent back through
`continue`.
`apply` validates editable values, materializes bounded input files under
`artifacts/work/`, and invokes the ordinary invariant-checking commands with
the fixed identifiers and flags. Candidate rejection is the one direct store
mutation because it is itself the packet decision and is covered by the
`apply` audit event. A successful apply emits only one `continue` command.
Multi-command applications, such as create/attach/seal, are deliberately
crash-recoverable rather than transactionally combined: each child mutation is
durable and a subsequent `continue` derives the legal action from the
resulting intermediate state.

The selected packet is one deterministic valid path, not a declaration that
no alternative exists. Stable selection reduces agent choice load. If source
inspection shows that the selected semantic path is unsuitable, the agent may
perform another legal mutation using the detailed command reference, then
return to `continue`; it must never alter `fixed` to smuggle in a different
identity.

Search packets expose an editable query initialized from the current step title
and bounded research objective. Fetch, excerpt, and evidence packets require an
explicit `accept` or `reject` decision. A rejection includes a bounded reason
and durably classifies the selected `hit`, `snapshot`, or `excerpt` as unusable
for that step. Later guidance excludes rejected candidates and deterministically
selects the next legal hit, snapshot, excerpt, or search action. Agents must
reject bot challenges, access-denied pages, irrelevant results, empty semantic
content, and excerpts that do not address the current step.

## Search and fetch adapters

Sandwalk owns the lifecycle of search hits and snapshots. External adapters own
search, retrieval, OCR, and normalization.

Adapters are executables using a versioned JSON protocol over standard input and
standard output. Shell command templates are not part of the protocol.

A search adapter returns bounded structured results. Sandwalk mints `hit_...`
references and records the query, adapter, result position, source locator,
title, and snippet. The schema-7 `url` column and v1 JSON field retain their
names for compatibility, but accept HTTP(S) URLs, absolute `file://` locators,
bundled `info://texiq/` node locators, and `qmd://` semantic-index entry
locators. Schema 23 adds the requested local source root to search provenance;
for a QMD search this field contains the authorized semantic-index directory.

The default web search connector is the bundled `sandwalk-search-searxng`
adapter. It talks to a user-owned SearXNG service through the same versioned
JSON protocol and never exposes the service's raw response to the agent. The
service may be managed by Sandwalk or supplied as an external endpoint.

The bundled ddgr connector remains available only as an explicit fallback:
callers must select it with `--adapter sandwalk-search-ddgr` (or the
corresponding configuration). A SearXNG failure is an explicit search error;
Sandwalk never silently falls back to ddgr.

Both connectors accept:

```json
{"protocol":"sandwalk.search.v1","query":"typed agents","limit":10}
```

and returns at most 25 bounded results in a
`sandwalk.search-results.v1` envelope. The ddgr connector invokes `ddgr --json`
without a shell command template.

### Managed SearXNG service

The managed service is one per user, shared by all Sandwalk workspaces. It is
backed by Docker and may also be replaced by an explicitly configured external
SearXNG endpoint. Managed mode accepts only the local Docker context; remote
Docker contexts are rejected and must be represented as external endpoints.
External endpoints do not support authentication in the initial protocol;
plain HTTP is accepted only for loopback origins and other endpoints require
HTTPS.
The service binds a dynamically selected port on loopback only. The exact
container image is a pinned release reference (including digest); the digest
is recorded in service state and provenance rather than inferred from a
mutable tag.

The user-facing lifecycle commands are documented in README and detailed CLI
help; they are intentionally not part of the agent skill's command loop.

The first managed `sandwalk search` auto-starts the service and pulls the
missing pinned image. Search does not recreate a running service merely
because user configuration changed. `status` reports desired and active
configuration, image, and configuration hashes; searches continue using the
active profile until an explicit `search-service update` applies the desired
profile. Service identity checks include ownership labels, the exact container
ID, user identity, configuration hash, and a generation value, so stale state
cannot stop an unrelated container.

Managed state is kept in a per-user state directory. Lifecycle operations use
exact ownership checks and an exclusive lifecycle lock. Searches hold a shared
activity guard, so independent searches may run in parallel; stop, remove, and
watchdog shutdown wait for active searches unless an explicit force operation
is requested. Lock acquisition order is always lifecycle before activity.

When idle shutdown is enabled, one detached watchdog process owns a singleton
lock and watches the service lease. Its default idle timeout is 900 seconds;
`0` disables the watchdog. Each completed search extends the lease, and the
watchdog rechecks the lease, generation, and container identity after taking
the exclusive locks before issuing `docker stop`. A failed stop is recorded as
a bounded diagnostic event and is retryable by a later lifecycle command.

Search configuration precedence is, from lowest to highest priority:

```text
defaults → user configuration → environment → command-line flags
```

The default profile is the curated `research-v1` profile. Users may enable or
disable individual engines, use `keep_only` to restrict the
enabled set, and provide advanced SearXNG YAML settings. The curated profile
does not imply a fixed engine list in this document; the installed adapter
version is authoritative. Invalid or conflicting settings fail before a
search is attempted.

Search provenance records the adapter and protocol versions, endpoint origin,
active configuration hash, image digest when managed, and sanitized metadata.
Credentials, environment contents, and other secrets are never recorded.

The bundled `sandwalk-search-texiq` connector is a local, read-only GNU Info
source. It invokes `texiq --emacs` through the same bounded search protocol so
manuals registered only in the active Emacs `Info-directory-list`, including
package manuals, are discoverable alongside the ordinary Info path. An
explicit `--source-root` is prepended as an Info directory when supplied.
Repeated text matches in the same node collapse to one hit. The hit locator
contains the exact absolute main-file path and exact case-sensitive node name
as base64 fields under the `info://texiq/` scheme; the snippet remains discovery
metadata and cannot become evidence.
Catalog-wide Info search receives a 15-minute outer process bound because a
large active Emacs catalog is parsed locally and may exceed the ordinary
30-second search-adapter timeout.

When `--source-root` is present, the default bundled search connector is
`sandwalk-search-ugrep`. It invokes `ugrep+`, not `ug+`, so user or
working-directory `.ugrep` files cannot silently change scripted behavior. It
performs a fixed-string recursive search with stable pathname ordering,
does not follow directory symlinks, returns at most the requested number of
files, and emits canonical percent-encoded `file://` locators. Search snippets
are discovery metadata only and never become evidence.

Sandwalk can build a reusable local semantic discovery index before a research
workspace exists:

```text
sandwalk index build --source-root <path> --index-directory <path>
sandwalk index build --info-manual <scope> --index-directory <path> [--emacs]
```

The command invokes the versioned `sandwalk-index-qmd` adapter. Document ingest
walks one authorized directory without following symlinks and normalizes each
supported regular file through `sandwalk-fetch-file`; therefore plain text and
the rich formats supported by Docling share the same normalization and retained
original rules as an ordinary fetch. Info ingest enumerates the selected
manual's nodes through `texiq` and stores one exact node per entry. Inputs that
cannot be normalized are reported as skipped entries; an empty corpus fails.

An index is built in a sibling staging directory and is published atomically.
Replacing an existing directory is allowed only when its manifest identifies a
Sandwalk semantic index. The index contains a bounded `manifest.json`, immutable
per-entry normalized documents and metadata, a Markdown discovery projection,
and QMD's project-local `.qmd/index.yml` and `.qmd/index.sqlite`. The manifest
binds every entry to its original `file://` or `info://texiq/` locator and to
input, normalized-document, and projection hashes. It records the exact QMD
implementation version and embedding model. The model defaults to a pinned
multilingual Qwen3 embedding model; changing it requires rebuilding the index.

`sandwalk search --source-index <path>` selects `sandwalk-search-qmd` by
default. It runs one typed QMD structured query (`vec: ...`) with
`--no-rerank` against only the corpus declared by the Sandwalk manifest. This
skips QMD query expansion and reranking, so search loads only the configured
embedding model. The adapter converts QMD paths to bounded
`qmd://<index-id>/<entry-id>` locators, and persists the index directory as
search provenance. `--source-index` and `--source-root` are mutually exclusive.
The QMD database and its Markdown projections are discovery caches: snippets,
scores, and projection text can never become evidence directly.

Fetching a `qmd://` hit automatically selects `sandwalk-fetch-qmd`. The fetch
adapter verifies the locator's index identity, entry containment, manifest
membership, and all retained hashes, then publishes the entry's exact
normalized document. Its fetch manifest uses the original source locator as
`final_url`, so snapshot provenance and citations continue to name the source
file or Info node rather than the discovery cache. A changed source or a stale,
modified index is rejected and must be rebuilt.

A fetch adapter receives an output directory controlled by Sandwalk. It writes:

```text
required:
  manifest.json
  one primary text artifact declared by manifest.artifacts.document

optional:
  blocks.jsonl
  original
  images/
```

The primary artifact is a safe relative basename with media type
`text/markdown` or `text/plain`. Structured normalizers publish
`document.md`; genuinely flat sources may publish `transcript.txt`. Sandwalk
does not create aliases, copies, or hardlinks to force a conventional
filename. Schema 24 persists the basename and media type with each snapshot so
continuation and excerpt creation always open the declared artifact. Existing
snapshots migrate to `document.md` and `text/markdown`.

The bundled web connector accepts a `sandwalk.fetch.v1` request. It uses
`curl -L` with a Lynx user-agent and negotiates Markdown, HTML, and PDF. The
transport has explicit connection and total-request bounds; the adapter process
has the same 15-minute outer timeout as a local document fetch because a remote
PDF may require first-use model acquisition and CPU-only OCR.

The default `sandwalk-fetch-web` connector is a bounded dispatcher. It first
runs the curl connector because server-provided Markdown, static HTML, and PDFs
are cheaper and preserve a response closer to the publisher's transport. It
publishes that result directly when the normalized document contains semantic
content. For a non-PDF transport failure, an HTML application shell, or a
recognized bot-challenge document, it makes exactly one fallback attempt with
`sandwalk-fetch-playwright`. PDF and other binary normalization failures never
fall back to a browser. The selected manifest records whether fallback occurred
and its bounded reason. A failed fallback does not publish the curl attempt's
challenge or application shell as a snapshot.

The Playwright connector executes JavaScript in a fresh, non-persistent Chromium
context and serializes the rendered DOM after a bounded load-and-settle profile.
It disables downloads, service workers, browser permissions, dialogs, popups,
local-file navigation, and requests whose host resolves only to loopback,
private, link-local, multicast, or otherwise non-global addresses. It does not
load cookies, credentials, a user profile, stealth plugins, CAPTCHA solvers, or
proxy configuration. Images, media, and fonts are blocked; scripts, styles, and
same-page data requests remain available. The renderer applies request-count,
navigation-time, settle-time, raw-response, and rendered-DOM bounds.

The browser snapshot retains `raw-response.html` when the main response is
bounded HTML, `rendered-dom.html`, sanitized browser metadata, and the normalized
`document.md`. Pandoc converts the rendered DOM with raw HTML disabled and `mq`
remains the final queryability gate. Browser metadata classifies the visible
result as `content`, `empty`, `bot-challenge`, `login-wall`, `paywall`, or
`http-error`.
Only `content` can be published. The manifest records the Playwright and
Chromium versions, viewport, locale, timezone, wait profile, visible-text size,
input and rendered-DOM hashes, normalized-document hash, and sanitized
configuration digest under the
`playwright-rendered-dom-to-gfm-no-raw-html-v1` extraction profile.

A response explicitly labeled `text/markdown` becomes `document.md` directly.
HTML uses the HTML-to-GitHub-flavored Markdown fallback with pandoc's raw-HTML
extension disabled. A response with PDF magic bytes, regardless of a generic or
incorrect content type, is normalized by the same pinned Docling profile as a
local PDF. A response labeled as PDF without PDF magic is rejected instead of
being passed to the HTML reader. Other binary formats remain unsupported until
their normalizer is explicitly configured. The original response and any
Docling structure and quality artifacts are retained. `mq document.md '.tree'`
must succeed before `manifest.json` is published. The manifest identifies the
selected extraction profile as `server-markdown-direct-v1`,
`html-to-gfm-no-raw-html-v1`, or
`standard-native-hierarchy-bookmark-095-v2`.

arXiv is the first site-specific source constructor. For a recognized
`arxiv.org/abs`, `/html`, or `/pdf` locator, the connector:

1. requests the matching arXiv HTML representation;
2. resolves an exact article version from the HTML when the hit was
   unversioned;
3. always downloads and validates the PDF for that exact version;
4. isolates the LaTeXML `ltx_page_content` article in Pandoc's AST, resolves
   relative links, and converts embedded data images into bounded `images/`
   artifacts; and
5. publishes the HTML-derived Markdown only when it has a title-sized heading
   tree, sufficient nonblank content, and passes `mq`.

Pandoc provides the embedded Lua runtime used by the AST filter; Sandwalk does
not depend on a separately installed Lua interpreter. Remote figure images are
kept as absolute links rather than silently downloaded. The mandatory
`source.pdf` artifact is retained for human reading even when HTML supplies
`document.md`. If HTML is unavailable, malformed, or fails the structural
quality gate, the already downloaded PDF is normalized through Docling and
remains available as `source.pdf`. The snapshot manifest records the canonical
versioned abstract URL, HTML and PDF representation URLs, selected
normalization source, both relevant hashes, and the fallback reason. Final
bibliographies therefore cite the stable abstract page rather than an
implementation-specific representation URL.

YouTube is a second site-specific source constructor. Recognized
`youtube.com` and `youtu.be` hits select `sandwalk-fetch-youtube`, which uses
`yt-dlp` to resolve metadata and download exactly one JSON3 caption track
without downloading video or audio. It prefers a manual track in the video's
language, then the original automatic track, and rejects videos without usable
captions. Source-provided chapters become timestamped H2 sections in
`document.md`; timestamps link to the corresponding playback position. If the
source has no chapters, the adapter publishes `transcript.txt` as
`text/plain`, with timestamped bounded paragraphs but no synthetic headings.
The flat transcript is gated with `rg`, while chaptered Markdown is gated with
`mq`. Both retain `captions.json3`, sanitized `metadata.json`, and
`blocks.jsonl` line-to-playback mappings. Sandwalk does not invent fixed-time
chapters, invoke an embedding model, or transcribe audio.

`blocks.jsonl` maps Markdown ranges to original document locators such as PDF
pages and bounding boxes.

The bundled `sandwalk-fetch-texiq` connector is selected automatically for an
`info://texiq/` hit. It resolves the locator's exact source path and node name,
uses `texiq` to extract only that node, and publishes it as a queryable
`text/plain` `document.txt`. The snapshot retains the selected main Info file
and `texiq`'s versioned node metadata. It hashes the main file before and after
extraction and rejects a concurrent change, so the published node text and
recorded input provenance cannot silently cross source revisions. It never
contacts the network or invokes an LLM.

The bundled default local-file fetch connector is `sandwalk-fetch-file`.
`fetch` selects it for a `file://` hit. The request repeats the source root
recorded with the search. The adapter canonicalizes both paths, rejects
non-regular files and symlink/path traversal outside that root, and classifies
the retained source before publication. Known rich document formats such as PDF,
RTF, Office, OpenDocument, EPUB, and message files are delegated to
`sandwalk-fetch-docling` before any byte-level text check, so ASCII-looking
container formats are never silently treated as plain text. MIME-confirmed
ordinary text and source files are copied to a `document` primary artifact that
preserves the source extension when one exists, declared as `text/plain`,
gated with `rg`, and retain the original file under
`original/`. Rich local documents copy the source under its original basename
into the controlled snapshot directory before extraction so normalization and
hashing observe one input. Adapters pass that retained artifact directly to
their normalizer; they do not create hardlink aliases merely to recover a
filename extension. Remote PDF fallbacks likewise normalize the retained
`source.pdf` directly. Local adapters and the bundled web
dispatcher receive a 15-minute process timeout because first-use model
acquisition and CPU-only OCR may exceed the transport's two-minute request
bound.

The Docling connector runs a pinned `docling==2.110.0` standard pipeline through
`uv`. It explicitly disables remote services and code, formula, picture,
description, and chart enrichments. OCR and accurate table reconstruction
remain enabled. PDF parsed pages are retained while Docling's native heading
hierarchy pass uses bookmarks, numbering, and font style with a strict `0.95`
bookmark threshold. The stricter threshold avoids the implementation's `0.92`
substring-match shortcut while tolerating small OCR differences. The first
recognized heading becomes the Markdown H1; naturally unstructured input gets
one filename H1.

The snapshot retains `original`, hierarchical `document.md`, Docling's lossless
`document.json`, and `quality.json`. Quality metrics include heading levels and
density, maximum heading length, undecoded formula count, and top-level PDF
bookmark coverage. When Docling entirely misses a top-level bookmark, the
adapter restores that authoritative heading immediately before the first
matched descendant bookmark, or before the next matched top-level bookmark as a
fallback, and records the restoration in `quality.json`. It never synthesizes
lower-level headings. The adapter rejects missing headings, implausibly long
headings, pathological heading density, and less than half of a non-trivial
top-level bookmark outline matching normalized headings. Remaining partial
bookmark coverage and undecoded formulas are explicit warnings.
`mq document.md '.tree'` is the final queryability gate.

`sandwalk-fetch-xberg` remains a bundled explicit fast adapter for simple PDFs
and other local formats. It targets the current Xberg v1 CLI, supplies an
explicit configuration rather than permitting discovery of `xberg.toml`, and
disables Xberg's result cache for each immutable snapshot. The bundled profile
uses local Tesseract OCR, Markdown output, six-level PDF font hierarchy,
bounding boxes, native table extraction, and document-structure extraction.
It does not enable VLM, remote enrichment, layout-to-Markdown, or the
layout-dependent reading-order pass. The latter two options can recover
individual structures but can also reorder section trees and fragment tables;
they require broader corpus evidence before entering the bundled profile.

The Xberg snapshot retains `original`, hierarchical `document.md`, Xberg's
`document.json`, and `quality.json`. Quality metrics bind structured and
Markdown heading counts, structured-table and Markdown-table signals,
nonblank content, maximum heading length, and any synthetic filename root. If
Xberg reports title or heading nodes but emits no ATX Markdown headings,
reports level-two-or-deeper nodes without corresponding Markdown subheadings,
reports structured tables without a Markdown table, or produces an
implausibly long heading, the adapter rejects the result instead of publishing
a flattened document. When Xberg emits headings but no H1, the adapter adds one
filename root and records that repair in `quality.json`. Choosing a normalizer
remains an adapter decision, not a core-state distinction.

Sandwalk records:

- retrieval time in UTC;
- requested and final URLs;
- redirect chain and HTTP metadata;
- input and normalized primary-document hashes;
- adapter name and adapter protocol version;
- optional implementation version, extraction profile, and sanitized
  configuration digest.

The deterministic guarantee applies to Sandwalk core. Adapters may use OCR,
specialized machine-learning models, or remote services, but they may not
silently call an LLM under a profile documented as non-LLM.

## Sources and snapshots

A source is an internal logical identity, usually a canonical URL or canonical
local file locator. Each fetch creates an immutable snapshot with its own
retrieval timestamp. Refetching does not modify old snapshots or invalidate
their excerpts. Local source identity does not imply mutable filesystem
contents are stable: the copied original and its content hash define the
snapshot actually used as evidence.

Raw payloads are retained by default with configurable size limits. If a limit
is exceeded, the snapshot remains usable but records why the raw payload was
omitted.

Cleanup is explicit and uses a plan/apply workflow:

```console
sandwalk gc --slug <slug> --raw --plan
sandwalk gc --slug <slug> --raw --apply
```

Raw cleanup preserves normalized Markdown, hashes, excerpts, evidence, and an
audit event. Active operations are skipped or rejected. Logs are never deleted
by default.

The raw plan is deterministic versioned JSON at
`artifacts/gc-raw-plan.json`. Sandwalk stores and rechecks its MD5 before apply;
modified or already-applied plans are rejected. Planning and applying are both
rejected while any step claim is active. Apply is crash-idempotent: already
absent files are accepted, while unrelated filesystem errors stop the apply.

## Excerpts

An excerpt is a contiguous, exact fragment of one immutable snapshot.

```console
sandwalk excerpt create --slug <slug> --snapshot <snapshot> --lines 120:146
sandwalk excerpt create --slug <slug> --snapshot <snapshot> \
  --text-file <path>
```

An excerpt records:

- snapshot and normalized primary-document hashes;
- line and byte ranges;
- excerpt text hash;
- optional source block, page, and bounding-box locators.

Text must occur exactly in the normalized primary document. Ambiguous matches
require an occurrence selector. Oversized excerpts are rejected with a compact
repair instruction. Creating the same excerpt twice is idempotent.

Line ranges are one-based, inclusive, and retain the source newline after the
last selected line when one exists. Byte ranges are zero-based with an
exclusive end. Exact-text matching permits overlapping occurrences and
`--occurrence` is one-based. Excerpt text is limited to 65,536 bytes. In
`researching`, creation requires the active claim that owns the snapshot.

## Visual evidence

Visual evidence covers source meaning that cannot be faithfully represented by
normalized text, such as charts, diagrams, spatial tables, formulas, and page
layout. The first version supports PDF snapshots only and renders one complete,
one-based page at a time:

```console
sandwalk visual create --slug <slug> --claim <claim> \
  --snapshot <snapshot> --page 7 --description-file <path>
```

The description is a bounded agent-authored observation used for navigation
and review; it is explicitly not source text. The PNG remains the evidence.
Sandwalk never invokes a vision model. The surrounding harness must make the
returned `image_path` available to a vision-capable agent and reviewer.

Sandwalk resolves the retained PDF only from the immutable snapshot manifest;
the agent cannot supply an arbitrary input path. The renderer adapter receives
a versioned `sandwalk.visual-render.v1` request, runs offline, and publishes a
`sandwalk.visual-render-result.v1` response with `page.png` plus a bounded
manifest. The bundled profile uses Poppler at 144 DPI, caps page count, image
dimensions, pixel count, and encoded size, and records the renderer version.
The result binds:

- the visual reference, source snapshot, and owning claim/step;
- the retained PDF path and SHA-256;
- one-based page number and total page count;
- PNG path, dimensions, byte size, and SHA-256;
- render profile, implementation version, and creation time;
- the bounded observation text and its hash.

Visual artifacts live under `artifacts/visuals/visual_.../`. Creating the same
snapshot page with the same render profile is idempotent. A visual is valid only
while its persisted PDF hash, PNG hash, and manifest hash still match the
immutable artifacts. Raw GC preserves PDFs that back visual evidence. Creating
a visual invalidates any older unapplied raw-cleanup plan in the same database;
a newly generated plan excludes every backing snapshot.

The continuation policy may present an excerpt-oriented packet because visual
capture is a semantic choice rather than a deterministic default. A worker may
perform this bounded evidence detour with its current claim, but must discard
the old packet after the mutation and run `continue` to derive fresh work from
durable state.

## Findings and evidence

A finding has a human-readable key scoped to one plan step. Its evidence bundle
is stored inside the finding rather than exposed as another reference type.

Each attached text excerpt or visual has one relation:

- `supports`
- `contradicts`
- `qualifies`
- `context`

At least one current text excerpt or visual must use a claim-bearing relation
(`supports`, `contradicts`, or `qualifies`) before a finding can be sealed.
`context` evidence may supplement a bundle but cannot satisfy the seal gate by
itself.

```console
sandwalk finding create --slug <slug> --step <step> \
  --claim <claim> --key <key> --claim-file <path>
sandwalk finding attach --slug <slug> --finding <step>/<key> \
  --claim <claim> --excerpt <excerpt> --relation supports
sandwalk finding attach --slug <slug> --finding <step>/<key> \
  --claim <claim> --visual <visual> --relation supports
sandwalk finding seal --slug <slug> --finding <step>/<key> --claim <claim>
sandwalk finding review --slug <slug> --finding <step>/<key> \
  --claim <claim> --review-file <path>
```

The finding lifecycle is:

```text
draft → sealed → reviewed
```

Changing a sealed finding creates a new revision and marks prior reviews stale.
The CLI checks reference integrity and snapshot freshness. A validation agent,
not Sandwalk, judges semantic support, source quality, conflicts, and necessary
qualifications.

Finding statements are non-empty files of at most 65,536 bytes. Every finding
mutation in `researching` also requires `--claim <claim>` for the active
capability that owns the named plan step; `--claim-file` is the statement
content, not the claim capability.

Finding reviews are bounded JSON using protocol
`sandwalk.finding-review.v1` for text-only findings. A finding containing visual
evidence requires `sandwalk.finding-review.v2` and an exact
`reviewed_visuals` list containing every current `visual_...` reference. This
does not prove semantic correctness, but it prevents a text-only review from
accidentally approving an unseen visual bundle. Reviews record one
agent-authored verdict (`supported`, `partially-supported`, `unsupported`, or
`contradicted`) plus a non-empty summary and explicit source-quality, conflict,
and qualification notes. Sandwalk accepts a review only for the current sealed
revision. Repeating the identical review is idempotent; a different review
cannot silently replace it. Editing reviewed content creates a new draft
revision, so the prior review is stale by construction.

A finding revision may attach at most 256 distinct visual references, matching
the bounded v2 review protocol. The same visual may carry more than one typed
relation without consuming another visual slot.

## Validation gates

Before drafting:

- required plan steps are complete;
- included findings are sealed;
- attached excerpts, visuals, and backing snapshots are valid;
- finding revisions have current semantic reviews;
- unsupported findings are excluded or revised.

```console
sandwalk draft prepare --slug <slug>
```

`draft prepare` rechecks the gate, validates every excerpt and visual artifact
against durable hashes (including each visual's manifest and backing PDF),
writes a deterministic bounded `exports/writer-pack.md`, and only then performs
the checked `evidence-review → drafting` transition. The pack contains current
reviewed claim text, exact evidence, provenance, and stable typed citation
tokens. It is limited to 1 MiB.

After drafting, Sandwalk splits the report into bounded citation-bearing blocks.
A validation agent records whether each block is supported, partially
supported, unsupported, or contradicted.

```console
sandwalk draft submit --slug <slug> --report-file <path>
```

Submission accepts at most 1 MiB of Markdown and splits it at blank lines into
at most 256 blocks of at most 16 KiB. Heading blocks may be uncited; every prose block must
contain at least one canonical `[cite:step-key/finding-key]` token. Citation
targets must name current reviewed findings with `supported` or
`partially-supported` verdicts. Sandwalk atomically records the report revision
and blocks, publishes `exports/report.md`, and performs the checked
`drafting → draft-review` transition.

An uncited-block failure includes the one-based block ordinal, a bounded
single-line preview of that exact block, and the blank-line splitting rule so an
agent can repair the correct paragraph without reconstructing parser behavior.

```console
sandwalk draft review --slug <slug> --review-file <path>
```

The `sandwalk.report-review.v1` JSON protocol binds one validation-agent
verdict and non-empty summary to the MD5 of every current report block. Missing,
duplicate, extra, or stale block reviews are rejected. If every verdict is
`supported` or `partially-supported`, Sandwalk performs
`draft-review → finalizing`; any `unsupported` or `contradicted` block performs
`draft-review → drafting` so a new report revision can be submitted.

The final gate rejects unknown, stale, or unreviewed citation targets.

```console
sandwalk finalize --slug <slug>
```

Finalization rechecks the current report revision, exact block hashes, accepted
block reviews, current finding reviews, and source provenance. It replaces
typed tokens with deterministic numeric citations ordered by first source
appearance, deduplicates final source URLs, writes `exports/report.md` and
`exports/sources.md`, records their hashes, and performs the checked
`finalizing → completed` transition. Retrying after a filesystem-only partial
failure renders from the durable submitted report text rather than from a
partially rewritten export.

## Report format

The writer produces ordinary Markdown with typed citation tokens:

```text
[cite:step-key/finding-key]
```

Sandwalk deterministically validates tokens, assigns stable citation numbers,
deduplicates sources, and writes the bibliography. Agents do not manually
maintain citation numbering.

## Export adapters

Finalized Markdown projections can be rendered into additional delivery formats
through versioned export adapters:

```console
sandwalk export pdf --slug <slug> [--adapter <executable>]
```

Export is allowed only after the workspace reaches `completed`. Before invoking
an adapter, Sandwalk verifies `exports/report.md` and `exports/sources.md`
against the hashes recorded by finalization. Adapter execution occurs outside
SQLite in a Sandwalk-controlled temporary directory. Sandwalk validates the
returned manifest, input hashes, media type, declared output hash, and format
signature before atomically publishing the artifact.

An exporter receives a `sandwalk.export.v1` request:

```json
{
  "protocol": "sandwalk.export.v1",
  "format": "pdf",
  "inputs": [
    {"role": "report", "path": ".../report.md", "md5": "..."},
    {"role": "bibliography", "path": ".../sources.md", "md5": "..."}
  ],
  "output_directory": ".../artifacts/temporary/export-..."
}
```

It writes the declared artifact plus `manifest.json` using
`sandwalk.export-manifest.v1`, then returns bounded JSON. Artifact paths in the
manifest are relative basenames, so an adapter cannot publish outside its
assigned directory.

The first bundled exporter is `sandwalk-export-pandoc-pdf`. It invokes Pandoc
on the finalized report followed by its bibliography and writes
`exports/report.pdf`. It turns rendered numeric citations such as `[1]` into
internal links to the corresponding bibliography entries, preserves external
URL annotations, and enables visible link colors. It uses XeLaTeX with the
installed serif, sans-serif, and monospaced fonts that support Russian
Cyrillic, selected through fontconfig and passed to XeLaTeX by file path. This
makes Unicode text, including Cyrillic, render consistently without assuming a
particular installed font family. Pandoc PDF generation therefore requires
XeLaTeX and fontconfig. The exporter assigns equal bounded widths to Markdown
table columns, so cells wrap within the PDF text area instead of extending past
the page edge. Tables with five or more columns are rendered in a landscape
page with a smaller table font so their columns remain readable rather than
overlapping. Additional formats and renderers use the same protocol rather than
adding renderer logic to the Sandwalk core.

## Audit log

Every invocation appends versioned JSON events to:

```text
<directory-prefix>/<slug>/logs/events.jsonl
```

Concurrent writers use a file lock. Each invocation records:

```text
command.started
command.finished | command.failed
```

An unmatched start event identifies a crash.

Events include timestamps, phase, claim and step when applicable, raw argument
vector, parsed logical arguments, consumed and created references, state
changes, duration, outcome, error code, and internal hint metadata.

Inline arguments are logged in full. File arguments record paths, hashes, and
sizes. Standard input is logged up to a configurable limit and otherwise records
a prefix, size, and hash. Adapter credentials and process environments are
never logged.

Logs remain local. Sandwalk performs no telemetry or automatic upload.

## Agent response contract

Agent-facing output is a compact JSON envelope. It contains at most one
recommended next command.

```json
{
  "ok": false,
  "error": {
    "code": "PLAN_NOT_VALIDATED",
    "message": "Plan must be validated before sealing."
  },
  "next": "sandwalk plan validate --slug 'typed-harness'"
}
```

The `next` value is one POSIX shell command without pipelines, redirections,
substitutions, or control operators. Dynamic values are shell-quoted.

Internal hint identifiers, template versions, and follow-up correlation are
logged but never shown to the agent. Detailed help is opt-in:

```console
sandwalk explain PLAN_NOT_VALIDATED
sandwalk next --slug <slug>
```

Hint modes are `none`, `compact`, and `full`. The bundled skill uses `compact`.
`SANDWALK_HINT_MODE` selects the mode and defaults to `compact`. `none`
suppresses repair commands, `compact` emits a command only when Sandwalk can
derive a safe deterministic repair from the current invocation, and `full`
points to the static `explain` entry. The default compact response has a strict
byte budget.

Sandwalk does not modify hint templates from runtime data. Logs may be analyzed
offline, and improved versioned templates ship in later releases.

`next` reports a phase-aware action, its reason, and one shell-safe advisory
command. Research often permits several valid actions, claims, sources, or
findings. Sandwalk selects one candidate with stable ordering to reduce choice
load; it does not reject other legal mutations. When progress requires a
semantic decision such as choosing an excerpt range or evidence relation,
Sandwalk recommends inspecting a deterministic artifact rather than making the
decision itself.

`continue` exposes the same recommendation as a durable work packet and is the
default agent loop. `apply` suppresses successful child-command payloads so
the loop remains bounded, but preserves failed child output for diagnosis.
Both orchestration commands have their own audit events; child mutations retain
their ordinary events. Once `continue` observes `completed`, it emits no next
command and the loop terminates.

## Portable skill

The deep-research skill is distributed with Sandwalk, not with Ellama.

The core skill:

- refers to capabilities rather than product-specific tool names;
- assumes only command execution and partial file reading;
- works sequentially when subagents are unavailable;
- uses Sandwalk claims when parallel workers are available;
- loads detailed command references only when needed;
- keeps the main skill instructions concise.

The skill invokes ordinary search and fetch commands only. It does not expose
or recommend `search-service start`, `stop`, `status`, `remove`, or `update`;
managed-service lifecycle is an explicit user/administrator operation.

On session replacement, the skill runs `continue`, treats the generated current
packet and durable Sandwalk state as authoritative over chat or controller
checklists, and stays in the `continue → edit editable → apply` loop. `resume`
remains the richer diagnostic boundary for crashes, unmatched audit starts, and
manual recovery.

Platform-specific installation metadata may be provided separately, but the
workflow remains canonical and agent-agnostic.

## Implementation architecture

Sandwalk is implemented in OCaml using the Jane Street ecosystem:

- Core and Core_unix
- Async and Async_unix
- Jane Street command-line parsing
- ppx_jane
- expect tests and property-based tests
- Dune and opam

SQLite and JSON bindings are allowed external dependencies.

The code is split into:

```text
sandwalk_core       pure types, FSM, and invariants
sandwalk_protocol   JSON schemas and response rendering
sandwalk_store      SQLite, migrations, and transactions
sandwalk_runtime    Async subprocesses, timeouts, locks, and files
sandwalk_cli        public commands
```

`sandwalk_core` must not depend on Async, SQLite, clocks, randomness, or the
filesystem. Identifier generation is injected at the runtime boundary.
Timestamps may be injected for provenance and audit records, but time must never
affect domain decisions, validity, or state transitions. Domain errors are typed
variants and become compact messages only at the CLI boundary.

SQLite operations are serialized and must not block the Async scheduler.
Sandwalk does not mix Async with Lwt or Eio.

## Testing strategy

- Expect tests cover every public command and JSON envelope.
- Property tests cover FSM transitions and reference invariants.
- Migration tests upgrade fixtures from every released schema.
- Adapter contract tests use deterministic fake executables.
- Integration tests run parallel claims against one WAL database.
- Crash tests verify unmatched events, persistent claims, and resume packs.
- Finalization tests prove stable citation numbering from identical state.
- Skill forward tests use fresh agent sessions and raw task artifacts.

## Initial vertical slice

The first implementation slice contains no network access:

```text
init
status
resume
plan add-step
plan validate
plan seal
step claim
step checkpoint
```

It establishes workspace layout, migrations, FSM enforcement, audit logging,
compact responses, exclusive claims, and recovery before adapter work begins.
