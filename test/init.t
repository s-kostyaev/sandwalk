  $ sandwalk init --slug typed-harness --directory-prefix workspaces
  {"ok":true,"result":{"slug":"typed-harness","phase":"initialized","schema_version":1}}

  $ find workspaces/typed-harness -type d | sort
  workspaces/typed-harness
  workspaces/typed-harness/artifacts
  workspaces/typed-harness/artifacts/excerpts
  workspaces/typed-harness/artifacts/resume
  workspaces/typed-harness/artifacts/snapshots
  workspaces/typed-harness/artifacts/temporary
  workspaces/typed-harness/database
  workspaces/typed-harness/exports
  workspaces/typed-harness/logs

  $ ./inspect_workspace.exe workspaces/typed-harness/database/sandwalk.sqlite3
  typed-harness|initialized
  1
  wal
  ok

  $ wc -l < workspaces/typed-harness/logs/events.jsonl
         2

  $ sandwalk init --slug typed-harness --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_EXISTS","message":"Workspace already exists."}}
  [1]

  $ wc -l < workspaces/typed-harness/logs/events.jsonl
         4

  $ sandwalk init --slug ../escape --directory-prefix workspaces
  {"ok":false,"error":{"code":"INVALID_SLUG","message":"Slug must use lowercase letters or digits, separated by single hyphens."}}
  [1]
