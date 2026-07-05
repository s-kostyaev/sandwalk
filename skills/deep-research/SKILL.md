---
name: deep-research
description: Conduct durable, source-grounded research with Sandwalk, including planning, parallel claims, immutable web or local-document snapshots, exact excerpts, reviewed findings, citation-safe drafting, recovery, and finalization. Use for research tasks that need auditable provenance, interruption recovery, independent evidence review, or a reviewed report rather than an informal summary.
---

# Deep Research

Use Sandwalk as the durable system of record. Sandwalk never supplies reasoning
or prose: perform those tasks yourself, then submit bounded artifacts through
its commands. Use the default compact hint mode (or set
`SANDWALK_HINT_MODE=compact` explicitly).

## Required startup

Choose exactly one writable directory prefix:

- If `SANDWALK_DIRECTORY_PREFIX` is non-empty, use it and never pass a
  conflicting `--directory-prefix`.
- Otherwise choose one prefix and pass the same `--directory-prefix` to every
  workspace command.

If the user names an existing workspace, start with the continuation loop
below. Do not initialize it and do not reconstruct its state from chat.

For a new workspace, read
[references/commands.md](references/commands.md) completely before the first
Sandwalk or network command. Treat its command forms as canonical; do not guess
flags or subcommands. After `sandwalk init --slug <slug>` succeeds, never
initialize that workspace again.

## Resume existing research

First ensure the previous worker has stopped. Never run two sessions
concurrently against the same claim. Then repeat this loop:

1. Run `sandwalk continue --slug <slug>` with the established directory
   prefix.
   If it reports phase `completed`, stop and report the exported result.
2. Read the returned `artifacts/work/current.json` and every artifact it
   explicitly asks you to inspect.
3. Edit only fields inside `editable`. Never change `fixed`, `workspace`,
   `action`, identifiers, or `integrity_md5`. The integrity hash excludes
   `editable`, so it remains valid after the intended edit and must never be
   removed or recomputed. Make the requested semantic decisions from the exact
   artifacts, not from memory or search snippets.
4. Run the exact `sandwalk apply --file ...` command returned by `continue`.
5. Run the `continue` command returned by `apply` and repeat until the reported
   phase is `completed`.

The current packet and durable state override chat history, controller
checklists, old errors, and any lost command response. After compaction,
uncertainty, or a partially applied action, discard the session-local procedure
and run `continue` again. It migrates old state and derives a valid action from
the state that actually committed.

If `apply` reports `INVALID_WORK_PACKET`, run `continue` once to regenerate the
packet, then edit only `editable` and retry the exact returned `apply` command.
Do not recompute the integrity hash, use `next`, or switch to the manual command
workflow while a current packet exists.

The packet presents one deterministic valid path; other legal research actions
may exist. If inspecting its fixed artifact shows that candidate is unsuitable,
set its editable decision to `reject`, give a concise reason, and apply the
packet. Sandwalk will durably skip it and derive another action. Never create an
excerpt or finding from a bot challenge, access-denied page, irrelevant result,
or content that does not address the packet's research objective and step.

Search packets contain an editable query and an initially empty
`editable.source_root`. Confirm that the query names the research subject and
current step goal. When the user authorized a local document directory, put
that readable directory in `source_root`; otherwise leave it empty.

## Exclusive retrieval

While this skill is active, Sandwalk is the only permitted path for every
network or local-document search and fetch, including reconnaissance. Do not load or invoke
another web-search, browsing, or fetch skill. Do not call `ddgr`, `curl`,
`wget`, `yt-dlp`, `ug`, `ugrep`, Xberg, Docling, a browser, or an HTTP client
directly. These programs may run only behind a Sandwalk adapter.

Use `sandwalk search` to discover persisted hits, `sandwalk fetch` to create
immutable snapshots, and read only the returned `document_path`. If either
command fails, diagnose and retry its adapter; never substitute another
retrieval path. The fetch result also declares `document_media_type`. Navigate
`text/markdown` through `mq` headings. For `text/plain`, locate relevant terms
with `rg -n`, then read only bounded line ranges around matches. Do not run
`mq` against plain text or read an entire long transcript into context.

For user-authorized local documents, run `sandwalk search` with exactly one
`--source-root <directory>`. The root must already be readable inside the
agent's filesystem sandbox. Sandwalk records it with every hit, defaults to
the `ugrep+` connector, and later selects the structured Docling fetch
connector for `file://` hits. Remote PDF hits use the same structured
normalization. For arXiv hits, Sandwalk prefers the article HTML for
`document.md` and retains the matching versioned `source.pdf` for the user; an
unusable HTML representation falls back to Docling automatically. Inspect the
returned primary document according to its declared media type; never treat
the search snippet as document content.

For YouTube hits, the default constructor uses source chapters when they exist.
If it returns `text/plain`, the video had no usable source chapter structure:
search the timestamped transcript with `rg -n` and read bounded ranges. Never
invent headings, summarize unread transcript regions, or fetch the video,
audio, or captions outside Sandwalk.

## Workflow

1. Create one workspace with a short lowercase slug using the required startup
   rules above.
2. Perform bounded reconnaissance whenever the topic name is unfamiliar or
   ambiguous. Resolve its identity with Sandwalk search and a fetched primary
   document, never from memory or search snippets, before recording the
   objective or sealing the plan.
3. Record the objective, an append-only step plan, and dependency edges;
   validate and seal the plan. Then enter the continuation loop.
4. Claim one eligible step. When parallel workers are available, give each
   worker a different claim. Otherwise process steps sequentially.
5. Search, select relevant hit identifiers from the JSON response, fetch those
   hits, and read only the necessary portions of the returned immutable
   primary documents.
6. Create exact excerpts. Write narrow findings, attach excerpts with typed
   relations, seal each finding revision, and review it against its evidence.
   Prefer an independent validation worker; with one worker, perform the review
   as a separate evidence-only pass.
7. Complete the claim only after its current findings pass review. Repeat until
   all required steps complete.
8. Prepare the writer pack, draft using only its typed citation tokens, submit
   the report, review every hashed block, and finalize. When the user requests
   a PDF, run `sandwalk export pdf --slug <slug>` after completion.

Report blocks are separated by blank lines. Every non-heading block needs a
current citation token, including short lead-in prose before a list. When
Sandwalk reports `REPORT_BLOCK_UNCITED`, use the returned block preview to edit
that exact block inside `editable.report_markdown`; do not repair a separate
draft file and do not guess the ordinal.

On interruption, use the continuation loop. Use `sandwalk resume` only when
you need its richer crash diagnostics or bounded recovery report. Do not edit
the SQLite database, projections, snapshots, excerpts, or audit log.

## Guardrails

- Keep claims narrower than their evidence.
- Preserve source disagreement using `contradicts` or `qualifies`; never erase
  it to force consensus.
- Cite exact excerpts, not search snippets or remembered page content.
- Never query or edit the Sandwalk SQLite database directly. Candidate
  selection and recovery must go through the current packet.
- Never fabricate or manually alter `hit_`, `snap_`, `excerpt_`, or `claim_`
  identifiers.
- Never rewrite citation numbering. Use
  `[cite:step-key/finding-key]`; Sandwalk renders final citations.
- If a manual command fails, execute its `next` command when present. Otherwise
  use `sandwalk explain CODE`, repair the stated invariant, and retry. If
  `apply` fails after a child mutation committed, run `continue`; do not replay
  the entire packet blindly.
- Keep at most one active claim per worker. Claims do not expire; recover the
  existing claim through `continue` after interruption, and checkpoint before
  handing work off.
- Relation `context` is supplemental. Every finding needs at least one
  `supports`, `contradicts`, or `qualifies` excerpt before sealing.
