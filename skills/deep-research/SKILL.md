---
name: deep-research
description: Conduct durable, source-grounded research with Sandwalk, including planning, parallel claims, immutable web snapshots, exact excerpts, reviewed findings, citation-safe drafting, recovery, and finalization. Use for research tasks that need auditable provenance, interruption recovery, independent evidence review, or a reviewed report rather than an informal web summary.
---

# Deep Research

Use Sandwalk as the durable system of record. Sandwalk never supplies reasoning
or prose: perform those tasks yourself, then submit bounded artifacts through
its commands. Use the default compact hint mode (or set
`SANDWALK_HINT_MODE=compact` explicitly).

## Required startup

Before the first Sandwalk or network command, read
[references/commands.md](references/commands.md) completely. Treat its command
forms as canonical; do not guess flags or subcommands.

Choose exactly one writable directory prefix:

- If `SANDWALK_DIRECTORY_PREFIX` is non-empty, use it and never pass a
  conflicting `--directory-prefix`.
- Otherwise choose one prefix and pass the same `--directory-prefix` to every
  workspace command.

After `sandwalk init --slug <slug>` succeeds, do not initialize that workspace
again. Continue with `status`, `next`, or `resume` using the same prefix.

## Exclusive retrieval

While this skill is active, Sandwalk is the only permitted path for every
network search and fetch, including reconnaissance. Do not load or invoke
another web-search, browsing, or fetch skill. Do not call `ddgr`, `curl`,
`wget`, a browser, or an HTTP client directly. These programs may run only
behind a Sandwalk adapter.

Use `sandwalk search` to discover persisted hits, `sandwalk fetch` to create
immutable snapshots, and read only the returned `document.md`. If either
command fails, diagnose and retry its adapter; never substitute another
retrieval path.

## Workflow

1. Create one workspace with a short lowercase slug using the required startup
   rules above.
2. Perform bounded reconnaissance whenever the topic name is unfamiliar or
   ambiguous. Resolve its identity with Sandwalk search and a fetched
   `document.md`, never from memory or search snippets, before recording the
   objective or sealing the plan.
3. Record the objective, an append-only step plan, and dependency edges;
   validate and seal the plan. Run `sandwalk next` when the required command is
   unclear.
4. Claim one eligible step. When parallel workers are available, give each
   worker a different claim. Otherwise process steps sequentially.
5. Search, select relevant hit identifiers from the JSON response, fetch those
   hits, and read only the necessary portions of immutable `document.md`
   snapshots.
6. Create exact excerpts. Write narrow findings, attach excerpts with typed
   relations, seal each finding revision, and review it against its evidence.
   Prefer an independent validation worker; with one worker, perform the review
   as a separate evidence-only pass.
7. Complete the claim only after its current findings pass review. Repeat until
   all required steps complete.
8. Prepare the writer pack, draft using only its typed citation tokens, submit
   the report, review every hashed block, and finalize.

On interruption, run `sandwalk resume` before continuing. Treat the generated
resume pack and command JSON as authoritative; do not infer state from memory or
edit the SQLite database, projections, snapshots, excerpts, or audit log.

## Guardrails

- Keep claims narrower than their evidence.
- Preserve source disagreement using `contradicts` or `qualifies`; never erase
  it to force consensus.
- Cite exact excerpts, not search snippets or remembered page content.
- Never fabricate or manually alter `hit_`, `snap_`, `excerpt_`, or `claim_`
  identifiers.
- Never rewrite citation numbering. Use
  `[cite:step-key/finding-key]`; Sandwalk renders final citations.
- If a command fails, use `sandwalk explain CODE`, repair the stated invariant,
  and retry.
- Keep at most one active claim per worker. Claims do not expire; recover the
  existing claim with `resume` after interruption, and checkpoint before handing
  work off.
