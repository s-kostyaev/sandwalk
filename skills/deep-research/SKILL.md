---
name: deep-research
description: Conduct durable, source-grounded research with Sandwalk, including planning, parallel claims, immutable web snapshots, exact excerpts, reviewed findings, citation-safe drafting, recovery, and finalization. Use for research tasks that need auditable provenance, interruption recovery, independent evidence review, or a reviewed report rather than an informal web summary.
---

# Deep Research

Use Sandwalk as the durable system of record. Sandwalk never supplies reasoning
or prose: perform those tasks yourself, then submit bounded artifacts through
its commands. Use the default compact hint mode (or set
`SANDWALK_HINT_MODE=compact` explicitly).

## Workflow

1. Create a workspace with a short lowercase slug. Run `sandwalk next` after
   each phase when the required command is unclear.
2. Perform bounded reconnaissance only when the topic needs scoping. Record the
   objective, an append-only step plan, and dependency edges; validate and seal
   the plan before research.
3. Claim one eligible step. When parallel workers are available, give each
   worker a different claim. Otherwise process steps sequentially.
4. Search, select relevant hit identifiers from the JSON response, fetch those
   hits, and read only the necessary portions of immutable `document.md`
   snapshots.
5. Create exact excerpts. Write narrow findings, attach excerpts with typed
   relations, seal each finding revision, and review it against its evidence.
   Prefer an independent validation worker; with one worker, perform the review
   as a separate evidence-only pass.
6. Complete the claim only after its current findings pass review. Repeat until
   all required steps complete.
7. Prepare the writer pack, draft using only its typed citation tokens, submit
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
- Keep at most one live claim per worker and checkpoint before handing work off.

Read [references/commands.md](references/commands.md) when exact command
arguments, review envelopes, or the end-to-end sequence are needed.
