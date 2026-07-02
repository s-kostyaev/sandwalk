  $ sandwalk explain PLAN_NOT_VALIDATED
  {"ok":true,"result":{"code":"PLAN_NOT_VALIDATED","explanation":"The current plan revision has not passed the explicit validation gate.","repair":"Run `sandwalk plan validate --slug <slug>`, then retry sealing."}}

  $ sandwalk explain NOT_A_REAL_CODE
  {"ok":false,"error":{"code":"UNKNOWN_ERROR_CODE","message":"No explanation is available for that error code."}}
  [1]

  $ sandwalk init --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"guidance-test","phase":"initialized","schema_version":20}}

  $ sandwalk next --slug guidance-test --directory-prefix "work spaces"
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]

  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"initialized"},"next":"'sandwalk' 'recon' 'start' '--goal-file' 'goal.md' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan add-step --slug guidance-test --directory-prefix workspaces \
  >   --key source-review --title "Review source"
  {"ok":true,"result":{"key":"source-review","title":"Review source","required":true,"position":1,"phase":"planning","plan_path":"workspaces/guidance-test/exports/research-plan.md"}}

  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"planning"},"next":"'sandwalk' 'plan' 'validate' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan validate --slug guidance-test --directory-prefix workspaces >/dev/null
  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"planning"},"next":"'sandwalk' 'plan' 'seal' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk plan seal --slug guidance-test --directory-prefix workspaces >/dev/null
  $ sandwalk next --slug guidance-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"researching"},"next":"'sandwalk' 'step' 'claim' '--step' 'source-review' '--slug' 'guidance-test' '--directory-prefix' 'workspaces'"}

  $ sandwalk next --slug missing --directory-prefix workspaces
  {"ok":false,"error":{"code":"WORKSPACE_NOT_FOUND","message":"Workspace does not exist."}}
  [1]
