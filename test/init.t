  $ sandwalk init --slug typed-harness --directory-prefix workspaces
  {"ok":true,"result":{"slug":"typed-harness","phase":"initialized","schema_version":25}}

  $ find workspaces/typed-harness -type d | sort
  workspaces/typed-harness
  workspaces/typed-harness/artifacts
  workspaces/typed-harness/artifacts/excerpts
  workspaces/typed-harness/artifacts/resume
  workspaces/typed-harness/artifacts/snapshots
  workspaces/typed-harness/artifacts/temporary
  workspaces/typed-harness/artifacts/work
  workspaces/typed-harness/database
  workspaces/typed-harness/exports
  workspaces/typed-harness/logs

  $ ./inspect_workspace.exe workspaces/typed-harness/database/sandwalk.sqlite3
  typed-harness|initialized
  25
  wal
  ok

  $ wc -l < workspaces/typed-harness/logs/events.jsonl
         2

  $ sandwalk status --slug typed-harness --directory-prefix workspaces
  {"ok":true,"result":{"slug":"typed-harness","phase":"initialized","schema_version":25}}

  $ sandwalk init --slug second-workspace --directory-prefix workspaces
  {"ok":true,"result":{"slug":"second-workspace","phase":"initialized","schema_version":25}}

  $ sandwalk list --directory-prefix workspaces
  {"ok":true,"result":{"directory_prefix":"workspaces","workspaces":[{"slug":"second-workspace","phase":"initialized","schema_version":25},{"slug":"typed-harness","phase":"initialized","schema_version":25}]}}

  $ sandwalk list --directory-prefix empty-workspaces
  {"ok":true,"result":{"directory_prefix":"empty-workspaces","workspaces":[]}}

  $ wc -l < workspaces/typed-harness/logs/events.jsonl
         4

  $ sandwalk init --slug typed-harness --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_EXISTS","message":"Workspace already exists."}}
  [1]

  $ wc -l < workspaces/typed-harness/logs/events.jsonl
         6

  $ SANDWALK_DIRECTORY_PREFIX=workspaces sandwalk status --slug typed-harness
  {"ok":true,"result":{"slug":"typed-harness","phase":"initialized","schema_version":25}}

  $ sandwalk status --slug missing --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]

  $ test ! -e workspaces/missing

  $ sandwalk plan validate --slug typed-harness --directory-prefix workspaces
  {"ok":false,"error":{"code":"PLAN_VALIDATION_NOT_ALLOWED","message":"Plan validation is not allowed while the workspace phase is initialized."},"next":"'sandwalk' 'next' '--slug' 'typed-harness' '--directory-prefix' 'workspaces'"}
  [1]

  $ sandwalk init --slug ../escape --directory-prefix workspaces
  {"ok":false,"error":{"code":"INVALID_SLUG","message":"Slug must use lowercase letters or digits, separated by single hyphens."}}
  [1]
