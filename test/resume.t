  $ sandwalk init --slug recovery-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"recovery-test","phase":"initialized","schema_version":7}}

Simulate a command whose process exited before recording its terminal event.

  $ printf '%s\n' '{"version":1,"event":"command.started","invocation_id":"crashed-1","timestamp":"2026-07-01 12:00:00Z","command":"plan add-step","phase":"initialized","claim":null,"step":null,"raw_argv":[],"arguments":{},"consumed_references":[],"created_references":[],"state_changes":[],"hint":null}' >> workspaces/recovery-test/logs/events.jsonl

  $ sandwalk resume --slug recovery-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"recovery-test","phase":"initialized","resume_path":"workspaces/recovery-test/artifacts/resume/workspace.md"}}

  $ cat workspaces/recovery-test/artifacts/resume/workspace.md
  # Sandwalk resume pack
  
  - Workspace: "recovery-test"
  - Phase: initialized
  - Schema version: 7
  
  ## Step objective and scope
  
  No plan step is active.
  
  ## Latest checkpoint
  
  None.
  
  ## Durable entities
  
  The workspace record is initialized. No plan entities exist yet.
  
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
  sandwalk status --slug 'recovery-test' --directory-prefix 'workspaces'
  ```

  $ find workspaces/recovery-test/artifacts/resume -name '*.tmp.*'

  $ wc -l < workspaces/recovery-test/logs/events.jsonl
         5

  $ sandwalk resume --slug missing --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]

  $ test ! -e workspaces/missing
