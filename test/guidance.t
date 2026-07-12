  $ sandwalk explain PLAN_NOT_VALIDATED
  {"ok":true,"result":{"code":"PLAN_NOT_VALIDATED","explanation":"The current plan revision has not passed the explicit validation gate.","repair":"Run `sandwalk plan validate --slug <slug>`, then retry sealing."}}

  $ sandwalk explain NOT_A_REAL_CODE
  {"ok":false,"error":{"code":"UNKNOWN_ERROR_CODE","message":"No explanation is available for that error code."}}
  [1]

  $ sandwalk explain WORKSPACE_IO_ERROR
  {"ok":true,"result":{"code":"WORKSPACE_IO_ERROR","explanation":"Sandwalk could not create or update the selected workspace directory.","repair":"Choose a writable `--directory-prefix` or set `SANDWALK_DIRECTORY_PREFIX` to one, then retry."}}

  $ sandwalk explain SEARCH_ADAPTER_FAILED
  {"ok":true,"result":{"code":"SEARCH_ADAPTER_FAILED","explanation":"The search adapter exited unsuccessfully, timed out, or returned invalid JSON.","repair":"Verify the selected adapter and its search tool (`ddgr` or `ugrep+`) are on PATH and allowed by the filesystem or network sandbox."}}

  $ sandwalk explain FETCH_ADAPTER_FAILED
  {"ok":true,"result":{"code":"FETCH_ADAPTER_FAILED","explanation":"The fetch adapter exited unsuccessfully, timed out, or returned invalid JSON.","repair":"Verify the selected adapter and its normalizer are on PATH. The default web fallback requires the pinned Playwright Chromium runtime; local rich documents require Docling and a sandbox-readable source root."}}

  $ sandwalk explain INVALID_WORK_PACKET
  {"ok":true,"result":{"code":"INVALID_WORK_PACKET","explanation":"The current work packet is malformed, unsupported, applied from the wrong path, or has modified fixed context.","repair":"Run `sandwalk continue --slug <slug>` once, edit only `editable`, leave `integrity_md5` unchanged, and run the exact returned `apply` command."}}

  $ sandwalk explain REPORT_BLOCK_UNCITED
  {"ok":true,"result":{"code":"REPORT_BLOCK_UNCITED","explanation":"A non-heading report block contains no current typed citation token.","repair":"Use the block preview from the failing command. Blank lines delimit blocks; add `[cite:step-key/finding-key]` to that exact prose block."}}

  $ sandwalk explain EXPORT_ADAPTER_FAILED
  {"ok":true,"result":{"code":"EXPORT_ADAPTER_FAILED","explanation":"The selected export adapter exited unsuccessfully, timed out, or returned invalid JSON.","repair":"Verify the adapter, Pandoc, and a supported Pandoc PDF engine are on PATH, then retry the export."}}

  $ sandwalk explain EXPORT_INPUT_STALE
  {"ok":true,"result":{"code":"EXPORT_INPUT_STALE","explanation":"The final Markdown report or bibliography no longer matches the hashes recorded at finalization.","repair":"Do not edit finalized projections. Restore the exact finalized `report.md` and `sources.md` before exporting."}}

  $ sandwalk init --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"guidance-test","phase":"initialized","schema_version":24}}

  $ sandwalk next --slug guidance-test --directory-prefix "work spaces"
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]

  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"initialized","action":"start-reconnaissance","reason":"Workspace scope and plan are not yet defined.","advisory":true,"alternatives_possible":true},"next":"'sandwalk' 'recon' 'start' '--goal-file' 'goal.md' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan add-step --slug guidance-test --directory-prefix workspaces \
  >   --key source-review --title "Review source"
  {"ok":true,"result":{"key":"source-review","title":"Review source","required":true,"position":1,"phase":"planning","plan_path":"workspaces/guidance-test/exports/research-plan.md"}}

  $ SANDWALK_HINT_MODE=none sandwalk plan seal \
  >   --slug guidance-test --directory-prefix workspaces
  {"ok":false,"error":{"code":"PLAN_NOT_VALIDATED","message":"Plan must be validated before sealing."}}
  [1]

  $ SANDWALK_HINT_MODE=full sandwalk plan seal \
  >   --slug guidance-test --directory-prefix workspaces
  {"ok":false,"error":{"code":"PLAN_NOT_VALIDATED","message":"Plan must be validated before sealing."},"next":"'sandwalk' 'explain' 'PLAN_NOT_VALIDATED'"}
  [1]

  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"planning","action":"validate-plan","reason":"The current plan revision has not been validated.","advisory":true,"alternatives_possible":true},"next":"'sandwalk' 'plan' 'validate' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan validate --slug guidance-test --directory-prefix workspaces >/dev/null
  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"planning","action":"seal-plan","reason":"The current plan revision is validated but not sealed.","advisory":true,"alternatives_possible":true},"next":"'sandwalk' 'plan' 'seal' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan seal --slug guidance-test --directory-prefix workspaces >/dev/null
  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"researching","action":"claim-step","reason":"The selected dependency-ready plan step has no active claim.","advisory":true,"alternatives_possible":true,"step":"source-review"},"next":"'sandwalk' 'step' 'claim' '--step' 'source-review' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

Wrong-phase failures identify the current phase and route back through durable
guidance.

  $ sandwalk finalize --slug guidance-test --directory-prefix workspaces
  {"ok":false,"error":{"code":"FINALIZE_NOT_ALLOWED","message":"Finalization is not allowed while the workspace phase is researching."},"next":"'sandwalk' 'next' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}
  [1]

Research guidance selects one stable candidate without claiming it is the only
legal action.

  $ mkdir -p active/active-guidance/database active/active-guidance/logs
  $ ./inspect_workspace.exe --create-v10 \
  >   active/active-guidance/database/sandwalk.sqlite3 active-guidance

  $ sandwalk next --slug active-guidance --directory-prefix active
  {"ok":true,"result":{"phase":"researching","action":"attach-evidence","reason":"Inspect the selected exact excerpt, then attach appropriate evidence with a relation chosen from its semantic role.","advisory":true,"alternatives_possible":true,"step":"fixture-step","claim":"claim_00000000000000000000000000000001","finding":"fixture-step/fixture-finding","candidate_excerpt":"excerpt_00000000000000000000000000000001","candidate_excerpt_path":"fixture-excerpt.md"},"next":"'sed' '-n' '1,200p' 'fixture-excerpt.md'"}

With exact evidence but no finding, the recommendation advances to authoring a
finding instead of cycling between `next` and `resume`.

  $ ./inspect_workspace.exe --clear-findings \
  >   active/active-guidance/database/sandwalk.sqlite3
  $ sandwalk next --slug active-guidance --directory-prefix active
  {"ok":true,"result":{"phase":"researching","action":"create-finding","reason":"The selected active step has exact evidence but no finding. Author a bounded statement in finding.md.","advisory":true,"alternatives_possible":true,"step":"fixture-step","claim":"claim_00000000000000000000000000000001","candidate_excerpt":"excerpt_00000000000000000000000000000001","candidate_excerpt_path":"fixture-excerpt.md"},"next":"'sandwalk' 'finding' 'create' '--step' 'fixture-step' '--claim' 'claim_00000000000000000000000000000001' '--key' 'finding' '--claim-file' 'finding.md' '--slug' 'active-guidance' '--directory-prefix' 'active'"}

  $ sandwalk next --slug missing --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]
