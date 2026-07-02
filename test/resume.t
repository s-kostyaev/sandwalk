  $ sandwalk init --slug recovery-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"recovery-test","phase":"initialized","schema_version":19}}

Simulate a command whose process exited before recording its terminal event.

  $ printf '%s\n' '{"version":1,"event":"command.started","invocation_id":"crashed-1","timestamp":"2026-07-01 12:00:00Z","command":"plan add-step","phase":"initialized","claim":null,"step":null,"raw_argv":[],"arguments":{},"consumed_references":[],"created_references":[],"state_changes":[],"hint":null}' >> workspaces/recovery-test/logs/events.jsonl

  $ sandwalk resume --slug recovery-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"recovery-test","phase":"initialized","resume_path":"workspaces/recovery-test/artifacts/resume/workspace.md"}}

  $ cat workspaces/recovery-test/artifacts/resume/workspace.md
  # Sandwalk resume pack
  
  - Workspace: "recovery-test"
  - Phase: initialized
  - Schema version: 19
  
  ## Step objective and scope
  
  No plan step is active.
  
  ## Latest checkpoint
  
  None.
  
  ## Durable entities
  
  The workspace record is initialized. No plan steps exist yet.
  Created research entities: none.
  
  ## Active claims
  
  - None.
  
  ## Recent commands
  
  - "init": success
  
  ## Unmatched command starts
  
  - "plan add-step"
  
  ## Last error or blocker
  
  None.
  
  ## Unresolved items
  
  Workspace scope and plan are not yet defined.
  
  ## Relevant artifact paths
  
  - Event log: "workspaces/recovery-test/logs/events.jsonl"
  
  ## Recommended next command
  
  ```console
  sandwalk next --slug 'recovery-test' --directory-prefix 'workspaces'
  ```

  $ find workspaces/recovery-test/artifacts/resume -name '*.tmp.*'

  $ wc -l < workspaces/recovery-test/logs/events.jsonl
         5

  $ sandwalk resume --slug missing --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]

  $ test ! -e workspaces/missing

Durable research identifiers and artifact paths survive context loss.

  $ mkdir -p rich/rich-recovery/database rich/rich-recovery/logs \
  >   rich/rich-recovery/artifacts/resume
  $ ./inspect_workspace.exe --create-v11 \
  >   rich/rich-recovery/database/sandwalk.sqlite3 rich-recovery
  $ sandwalk resume --slug rich-recovery --directory-prefix rich >/dev/null

  $ sed -n '/## Step objective and scope/,/## Latest checkpoint/p' \
  >   rich/rich-recovery/artifacts/resume/workspace.md
  ## Step objective and scope
  
  - Step: "fixture-step"
  - Title: "Fixture step"
  - Active claim: "claim_00000000000000000000000000000001"
  
  ## Latest checkpoint

  $ sed -n '/## Durable entities/,/## Active claims/p' \
  >   rich/rich-recovery/artifacts/resume/workspace.md
  ## Durable entities
  
  Plan steps:
  - 1. "fixture-step": "Fixture step" (required)
  - 2. "completed-step": "Completed fixture step" (required)
  Created research entities:
  - hit "hit_00000000000000000000000000000002", step "completed-step": "https://example.test/completed"
  - hit "hit_00000000000000000000000000000001", step "fixture-step": "https://example.test/start"
  - snapshot "snap_00000000000000000000000000000001", step "fixture-step": "workspace/rich-recovery/artifacts/snapshots/snap_00000000000000000000000000000001"
  - excerpt "excerpt_00000000000000000000000000000001", step "fixture-step": "fixture-excerpt.md"
  - finding "fixture-step/sealed-finding", step "fixture-step": "revision 1, sealed"
  - finding "fixture-step/fixture-finding", step "fixture-step": "revision 1, draft"
  
  ## Active claims

  $ sed -n '/## Relevant artifact paths/,/## Recommended next command/p' \
  >   rich/rich-recovery/artifacts/resume/workspace.md
  ## Relevant artifact paths
  
  - Event log: "rich/rich-recovery/logs/events.jsonl"
  - snapshot "snap_00000000000000000000000000000001": "workspace/rich-recovery/artifacts/snapshots/snap_00000000000000000000000000000001"
  - excerpt "excerpt_00000000000000000000000000000001": "fixture-excerpt.md"
  
  ## Recommended next command
