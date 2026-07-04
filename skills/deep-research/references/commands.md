# Sandwalk command reference

Set `<slug>` and choose one writable workspace parent. Prefer exporting
`SANDWALK_DIRECTORY_PREFIX=<path>` before the first command. If the environment
cannot be retained, pass the same `--directory-prefix <path>` to every workspace
command. Parse command output as JSON and retain returned identifiers.

## Establish scope and plan

```console
sandwalk init --slug <slug>
sandwalk recon start --slug <slug> --goal-file <goal.md>
sandwalk recon add-observation --slug <slug> --text-file <observation.md>
sandwalk recon finish --slug <slug> --summary-file <summary.md>

sandwalk plan set-objective --slug <slug> --file <objective.md>
sandwalk plan add-step --slug <slug> --key <step> --title <title>
sandwalk plan add-dependency <step> --slug <slug> --on <prerequisite>
sandwalk plan extend --slug <slug> --key <new-step> --title <title> \
  --reason-file <reason.md> [--on <prerequisite>]
sandwalk plan list --slug <slug>
sandwalk plan validate --slug <slug>
sandwalk plan seal --slug <slug>
```

Reconnaissance is optional: adding the first plan step advances a newly
initialized workspace to planning. Use lowercase hyphenated step and finding
keys. Add all dependency edges before validation.

After sealing, use `plan extend` only for a newly discovered direction. It
atomically records one new step and its reason without changing existing steps.

## Research one step

```console
sandwalk step claim --slug <slug> --step <step>
sandwalk snapshot promote --slug <slug> --claim <claim_id> <snapshot_id>
sandwalk search --slug <slug> --claim <claim_id> --query <query> [--limit 10]
sandwalk fetch --slug <slug> --claim <claim_id> <hit_id>
sandwalk excerpt create --slug <slug> --claim <claim_id> \
  --snapshot <snapshot_id> --lines <first:last>

sandwalk finding create --slug <slug> --claim <claim_id> \
  --step <step> --key <finding> --claim-file <claim.md>
sandwalk finding attach --slug <slug> --claim <claim_id> \
  --finding <step>/<finding> --excerpt <excerpt_id> --relation supports
sandwalk finding seal --slug <slug> --claim <claim_id> \
  --finding <step>/<finding>
sandwalk finding review --slug <slug> --claim <claim_id> \
  --finding <step>/<finding> --review-file <review.json>
sandwalk step complete --slug <slug> --claim <claim_id>
```

Fetch accepts only a persisted hit ID, not an arbitrary URL. Its default
connector stores the original response, headers, converted Markdown, hashes,
and a queryability check. For excerpts, use either `--lines first:last` or
`--text-file path [--occurrence N]`.

Use `snapshot promote` when reconnaissance already fetched the needed source.
It binds the immutable snapshot to the claimed step without fetching it again.

Evidence relations are `supports`, `contradicts`, `qualifies`, and `context`.
Attaching evidence to an already sealed finding creates a new revision that
must be sealed and reviewed again.
`context` cannot seal a finding by itself; at least one excerpt must use
`supports`, `contradicts`, or `qualifies`.

Checkpoint long work or handoffs:

```console
sandwalk step checkpoint --slug <slug> --claim <claim_id> \
  --summary-file <summary.md> --next-file <next.md>
sandwalk resume --slug <slug>
```

Claims do not expire. On interruption or context loss, recover the existing
active claim from `sandwalk resume`; do not claim the same step again.

## Review a finding

Submit one bounded JSON object:

```json
{
  "protocol": "sandwalk.finding-review.v1",
  "verdict": "partially-supported",
  "summary": "The exact excerpts support the narrow claim.",
  "source_quality": "Primary standards source.",
  "conflicts": "",
  "qualifications": "Limit the claim to the stated scope."
}
```

Verdicts are `supported`, `partially-supported`, `unsupported`, or
`contradicted`. Review the exact current finding revision and its excerpts.
Do not review from the draft report.

## Draft and review the report

```console
sandwalk draft prepare --slug <slug>
sandwalk draft submit --slug <slug> --report-file <draft.md>
sandwalk draft review --slug <slug> --review-file <report-review.json>
sandwalk finalize --slug <slug>
sandwalk export pdf --slug <slug>
```

`draft prepare` writes `exports/writer-pack.md`. Every prose block in the draft
must include at least one current token copied from that pack:

```text
[cite:step-key/finding-key]
```

Blank lines delimit report blocks. Headings may be uncited; every other block,
including a lead-in sentence before a list, needs a citation. A
`REPORT_BLOCK_UNCITED` response includes a bounded preview of the exact block
to repair.

`draft submit` returns the report revision and an ordered list of block MD5
hashes. Review every block exactly once:

```json
{
  "protocol": "sandwalk.report-review.v1",
  "report_revision": 1,
  "blocks": [
    {
      "ordinal": 1,
      "block_md5": "503410e60bdf3d6f82d795c3003fdc23",
      "verdict": "supported",
      "summary": "The heading accurately describes the report."
    }
  ]
}
```

Accepted block verdicts are `supported` and `partially-supported`. An
`unsupported` or `contradicted` block returns the workspace to drafting; submit
a new complete report revision after repair. Finalization writes
`exports/report.md` and `exports/sources.md`.

After finalization, `export pdf` verifies those two projections against the
durable finalization hashes and invokes the configured export adapter. The
bundled `sandwalk-export-pandoc-pdf` adapter publishes `exports/report.pdf`.

## Guidance and recovery

```console
sandwalk status --slug <slug>
sandwalk continue --slug <slug>
sandwalk apply --file <workspace>/artifacts/work/current.json
sandwalk next --slug <slug>
sandwalk explain <ERROR_CODE>
sandwalk resume --slug <slug>
```

Use `continue` as the normal agent loop. It migrates the workspace and writes a
bounded current packet. Inspect its referenced artifacts, change only
`editable`, leave `integrity_md5` unchanged, run the returned `apply`, then
follow the returned `continue`. The hash covers the fixed packet context, not
`editable`, and must not be removed or recomputed.
`apply` supplies fixed identifiers and command flags and validates the semantic
fields. Stop when `continue` reports phase `completed`.

After `INVALID_WORK_PACKET`, run `continue` once and retry the packet loop. Do
not switch to `next` or a manual mutation while a current packet exists.

Search packets provide an editable subject-aware query. Candidate packets
require `accept` or `reject`; rejection reasons are persisted and the rejected
hit, snapshot, or excerpt will not be recommended again. Do not force unusable
content through the workflow.

Use `next` for a read-only phase-aware, shell-safe recommendation. Use `resume`
for detailed crash diagnostics; it applies schema migrations, regenerates a
bounded pack from durable state, and reports unmatched command starts. These
commands return a recommended action and at most one advisory command.
Alternative legal research actions may exist. When the action requires a
semantic decision, inspect the selected artifact and choose the excerpt range,
finding statement, or evidence relation yourself.

Current phase, active claims, and durable entities override chat history,
controller checklists, and historical errors in the pack. Reconcile any
session-local plan before continuing. Do not repeat a mutating command solely
because its prior response was lost: inspect the resume pack first.

Before drafting, a completed finding with a bad semantic review can be reopened:

```console
sandwalk finding repair --slug <slug> --finding <step>/<finding> \
  --reason-file <reason.md>
```

This suspends active claims, reopens the completed step, creates a fresh draft
revision without evidence, and rejects the prior revision's excerpts for that
step. It is rejected after a dependent step has completed.

After completion, raw payload cleanup is an explicit hash-bound two-step
operation:

```console
sandwalk gc --slug <slug> --raw --plan
sandwalk gc --slug <slug> --raw --apply
```
