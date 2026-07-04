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
names for compatibility, but accept HTTP(S) URLs and absolute `file://`
locators. Schema 23 adds the requested local source root to search provenance.

The bundled ddgr connector accepts:

```json
{"protocol":"sandwalk.search.v1","query":"typed agents","limit":10}
```

and returns at most 25 bounded results in a
`sandwalk.search-results.v1` envelope. It invokes `ddgr --json` without a
shell command template.

When `--source-root` is present, the default bundled search connector is
`sandwalk-search-ugrep`. It invokes `ugrep+`, not `ug+`, so user or
working-directory `.ugrep` files cannot silently change scripted behavior. It
performs a fixed-string recursive search with stable pathname ordering,
does not follow directory symlinks, returns at most the requested number of
files, and emits canonical percent-encoded `file://` locators. Search snippets
are discovery metadata only and never become evidence.

A fetch adapter receives an output directory controlled by Sandwalk. It writes:

```text
required:
  document.md
  manifest.json

optional:
  blocks.jsonl
  original
  images/
```

The bundled web connector accepts a `sandwalk.fetch.v1` request. It uses
`curl -L` with a Lynx user-agent and requests `text/markdown` with HTML as a
lower-priority fallback. A response explicitly labeled `text/markdown` becomes
`document.md` directly. Other responses use the HTML-to-GitHub-flavored
Markdown fallback with pandoc's raw-HTML extension disabled. The original
response is retained in both cases, and `mq document.md '.tree'` must succeed
before `manifest.json` is published. The manifest identifies the selected
extraction profile as `server-markdown-direct-v1` or
`html-to-gfm-no-raw-html-v1`.

`blocks.jsonl` maps Markdown ranges to original document locators such as PDF
pages and bounding boxes.

The bundled default local-document fetch connector is
`sandwalk-fetch-docling`. `fetch` selects it for a `file://` hit. The request
repeats the source root recorded with the search. The adapter canonicalizes both
paths, rejects non-regular files and symlink/path traversal outside that root,
and copies the source into its controlled output directory before extraction so
normalization and hashing observe one input. Local adapters receive a
15-minute process timeout because first-use model acquisition and CPU-only OCR
may exceed the web adapter's two-minute bound.

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
and other local formats. It runs with an explicit configuration rather than an
auto-discovered `xberg.toml`, local Tesseract OCR, Markdown output, PDF
hierarchy and bounding boxes, and document-structure extraction. Its profile
must not enable VLM or remote enrichment. If Xberg reports title or heading
nodes but emits no ATX Markdown headings, or reports level-two-or-deeper nodes
without corresponding Markdown subheadings, the adapter rejects the result
instead of publishing a flattened document. Choosing a normalizer remains an
adapter decision, not a core-state distinction.

Sandwalk records:

- retrieval time in UTC;
- requested and final URLs;
- redirect chain and HTTP metadata;
- input and normalized Markdown hashes;
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

- snapshot and Markdown hashes;
- line and byte ranges;
- excerpt text hash;
- optional source block, page, and bounding-box locators.

Text must occur exactly in the normalized snapshot. Ambiguous matches require
an occurrence selector. Oversized excerpts are rejected with a compact repair
instruction. Creating the same excerpt twice is idempotent.

Line ranges are one-based, inclusive, and retain the source newline after the
last selected line when one exists. Byte ranges are zero-based with an
exclusive end. Exact-text matching permits overlapping occurrences and
`--occurrence` is one-based. Excerpt text is limited to 65,536 bytes. In
`researching`, creation requires the active claim that owns the snapshot.

## Findings and evidence

A finding has a human-readable key scoped to one plan step. Its evidence bundle
is stored inside the finding rather than exposed as another reference type.

Each attached excerpt has one relation:

- `supports`
- `contradicts`
- `qualifies`
- `context`

At least one current excerpt must use a claim-bearing relation (`supports`,
`contradicts`, or `qualifies`) before a finding can be sealed. `context`
evidence may supplement a bundle but cannot satisfy the seal gate by itself.

```console
sandwalk finding create --slug <slug> --step <step> \
  --claim <claim> --key <key> --claim-file <path>
sandwalk finding attach --slug <slug> --finding <step>/<key> \
  --claim <claim> --excerpt <excerpt> --relation supports
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
`sandwalk.finding-review.v1`. They record one agent-authored verdict
(`supported`, `partially-supported`, `unsupported`, or `contradicted`) plus a
non-empty summary and explicit source-quality, conflict, and qualification
notes. Sandwalk accepts a review only for the current sealed revision. Repeating
the identical review is idempotent; a different review cannot silently replace
it. Editing reviewed content creates a new draft revision, so the prior review
is stale by construction.

## Validation gates

Before drafting:

- required plan steps are complete;
- included findings are sealed;
- attached excerpts and snapshots are valid;
- finding revisions have current semantic reviews;
- unsupported findings are excluded or revised.

```console
sandwalk draft prepare --slug <slug>
```

`draft prepare` rechecks the gate, validates every excerpt artifact against its
durable hash, writes a deterministic bounded `exports/writer-pack.md`, and only
then performs the checked `evidence-review → drafting` transition. The pack
contains current reviewed claim text, exact evidence, provenance, and stable
typed citation tokens. It is limited to 1 MiB.

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
URL annotations, and enables visible link colors. Pandoc PDF generation also
requires one of its supported external PDF engines; the bundled exporter uses
Pandoc's configured default. Additional formats and renderers use the same
protocol rather than adding renderer logic to the Sandwalk core.

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
