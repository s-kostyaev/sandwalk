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
- `claim_...`: a temporary lease for an agent working on one plan step.

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
│   └── temporary/
├── exports/
│   ├── research-plan.md
│   ├── writer-pack.md
│   ├── report.md
│   └── sources.md
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
```

SQLite uses WAL mode and a configurable busy timeout. Independent commands use
short transactions. Network and adapter processes must never run inside a
database transaction.

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
sandwalk search --slug <slug> --query <query>
sandwalk fetch --slug <slug> <hit-ref>
sandwalk recon add-observation --slug <slug> ...
sandwalk recon finish --slug <slug> --summary-file <path>
```

Snapshots discovered during reconnaissance are ordinary immutable snapshots.
They are tagged with their purpose and may later be promoted to a research plan
step without being fetched again. Reconnaissance observations are not findings
and cannot pass report validation by themselves.

## Plan

The plan is canonical structured state in SQLite. `exports/research-plan.md` is
an atomically regenerated, read-only projection for humans and agents.

```console
sandwalk plan set-objective --slug <slug> --file <path>
sandwalk plan add-step --slug <slug> --key <key> --title <title> [--optional]
sandwalk plan add-dependency --slug <slug> <step> --on <dependency>
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

After work begins, existing steps are immutable. New steps are added through an
append-only plan revision with a recorded reason.

## Claims, leases, and recovery

A plan step is the durable unit of work. A claim is a temporary capability to
execute it. There is no public work identifier or permanent worker identifier.

```console
sandwalk step claim --slug <slug> --step <key> [--lease-seconds <seconds>]
```

The default lease is 900 seconds. Explicit leases range from 30 seconds to 24
hours. Claim identifiers contain the `claim_` prefix and 128 bits of random
entropy. Clocks and identifier generation are supplied at the runtime boundary.

```text
pending → claimed → suspended | expired | blocked → claimed → completed
```

Every mutating research command associated with a step accepts its claim.
Successful commands renew the lease. Long adapter operations may heartbeat.
Late commands from an expired or revoked claim are rejected.

Agents record semantic checkpoints at meaningful milestones:

```console
sandwalk step checkpoint --slug <slug> --claim <claim> \
  --summary-file <path> --next-file <path>
```

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
- one recommended next command.

Large artifacts and complete histories are referenced by path rather than
inlined.

## Search and fetch adapters

Sandwalk owns the lifecycle of search hits and snapshots. External adapters own
search, retrieval, OCR, and normalization.

Adapters are executables using a versioned JSON protocol over standard input and
standard output. Shell command templates are not part of the protocol.

A search adapter returns bounded structured results. Sandwalk mints `hit_...`
references and records the query, adapter, result position, URL, title, and
snippet.

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

`blocks.jsonl` maps Markdown ranges to original document locators such as PDF
pages and bounding boxes.

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

A source is an internal logical identity, usually a canonical URL. Each fetch
creates an immutable snapshot with its own retrieval timestamp. Refetching does
not modify old snapshots or invalidate their excerpts.

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

## Findings and evidence

A finding has a human-readable key scoped to one plan step. Its evidence bundle
is stored inside the finding rather than exposed as another reference type.

Each attached excerpt has one relation:

- `supports`
- `contradicts`
- `qualifies`
- `context`

```console
sandwalk finding create --slug <slug> --step <step> \
  --key <key> --claim-file <path>
sandwalk finding attach --slug <slug> --finding <step>/<key> \
  --excerpt <excerpt> --relation supports
sandwalk finding seal --slug <slug> --finding <step>/<key>
```

The finding lifecycle is:

```text
draft → sealed → reviewed
```

Changing a sealed finding creates a new revision and marks prior reviews stale.
The CLI checks reference integrity and snapshot freshness. A validation agent,
not Sandwalk, judges semantic support, source quality, conflicts, and necessary
qualifications.

## Validation gates

Before drafting:

- required plan steps are complete;
- included findings are sealed;
- attached excerpts and snapshots are valid;
- finding revisions have current semantic reviews;
- unsupported findings are excluded or revised.

After drafting, Sandwalk splits the report into bounded citation-bearing blocks.
A validation agent records whether each block is supported, partially
supported, unsupported, or contradicted.

The final gate rejects unknown, stale, or unreviewed citation targets.

## Report format

The writer produces ordinary Markdown with typed citation tokens:

```text
[cite:step-key/finding-key]
```

Sandwalk deterministically validates tokens, assigns stable citation numbers,
deduplicates sources, and writes the bibliography. Agents do not manually
maintain citation numbering.

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
The default compact response has a strict byte budget.

Sandwalk does not modify hint templates from runtime data. Logs may be analyzed
offline, and improved versioned templates ship in later releases.

## Portable skill

The deep-research skill is distributed with Sandwalk, not with Ellama.

The core skill:

- refers to capabilities rather than product-specific tool names;
- assumes only command execution and partial file reading;
- works sequentially when subagents are unavailable;
- uses Sandwalk claims when parallel workers are available;
- loads detailed command references only when needed;
- keeps the main skill instructions concise.

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
filesystem. Time and identifier generation are explicit inputs. Domain errors
are typed variants and become compact messages only at the CLI boundary.

SQLite operations are serialized and must not block the Async scheduler.
Sandwalk does not mix Async with Lwt or Eio.

## Testing strategy

- Expect tests cover every public command and JSON envelope.
- Property tests cover FSM transitions and reference invariants.
- Migration tests upgrade fixtures from every released schema.
- Adapter contract tests use deterministic fake executables.
- Integration tests run parallel claims against one WAL database.
- Crash tests verify unmatched events, lease expiry, and resume packs.
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
compact responses, leases, and recovery before adapter work begins.
