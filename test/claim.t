  $ sandwalk init --slug claim-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"claim-test","phase":"initialized","schema_version":24}}

  $ sandwalk plan add-step --slug claim-test --directory-prefix workspaces \
  >   --key primary --title "Primary research"
  {"ok":true,"result":{"key":"primary","title":"Primary research","required":true,"position":1,"phase":"planning","plan_path":"workspaces/claim-test/exports/research-plan.md"}}

  $ sandwalk plan add-step --slug claim-test --directory-prefix workspaces \
  >   --key parallel --title "Parallel contention"
  {"ok":true,"result":{"key":"parallel","title":"Parallel contention","required":true,"position":2,"phase":"planning","plan_path":"workspaces/claim-test/exports/research-plan.md"}}

  $ sandwalk plan validate --slug claim-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":2,"validated":true,"already_validated":false,"phase":"planning","plan_path":"workspaces/claim-test/exports/research-plan.md"}}

  $ sandwalk plan seal --slug claim-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":2,"sealed":true,"already_sealed":false,"phase":"researching","plan_path":"workspaces/claim-test/exports/research-plan.md"}}

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary | sed -E 's/claim_[0-9a-f]{32}/claim_ID/g'
  {"ok":true,"result":{"claim":"claim_ID","step":"primary","attempt":1}}

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary
  {"ok":false,"error":{"code":"STEP_ALREADY_CLAIMED","message":"Plan step already has an active claim."},"next":"'sandwalk' 'resume' '--slug' 'claim-test' '--directory-prefix' 'workspaces'"}
  [1]

Two concurrent contenders must produce exactly one claim.

  $ (sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >    --step parallel >one.out; echo $? >one.status) &
  $ (sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >    --step parallel >two.out; echo $? >two.status) &
  $ wait

  $ sort one.status two.status
  0
  1

  $ cat one.out two.out | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g' | \
  >   sort
  {"ok":false,"error":{"code":"STEP_ALREADY_CLAIMED","message":"Plan step already has an active claim."},"next":"'sandwalk' 'resume' '--slug' 'claim-test' '--directory-prefix' 'workspaces'"}
  {"ok":true,"result":{"claim":"claim_ID","step":"parallel","attempt":1}}

  $ ./inspect_workspace.exe --inspect-claims workspaces/claim-test/database/sandwalk.sqlite3
  parallel|claimed|1|38|1
  primary|claimed|1|38|1
  parallel|1|NULL
  primary|1|NULL

Legacy lease timestamps do not affect claim validity.

  $ ./inspect_workspace.exe --set-legacy-deadline \
  >   workspaces/claim-test/database/sandwalk.sqlite3 primary

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary
  {"ok":false,"error":{"code":"STEP_ALREADY_CLAIMED","message":"Plan step already has an active claim."},"next":"'sandwalk' 'resume' '--slug' 'claim-test' '--directory-prefix' 'workspaces'"}
  [1]

  $ ./inspect_workspace.exe --inspect-claims workspaces/claim-test/database/sandwalk.sqlite3
  parallel|claimed|1|38|1
  primary|claimed|1|38|1
  parallel|1|NULL
  primary|1|NULL

  $ sandwalk resume --slug claim-test --directory-prefix workspaces >/dev/null

  $ sed -n '/## Active claims/,+4p' workspaces/claim-test/artifacts/resume/workspace.md | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g'
  ## Active claims
  
  - Step "parallel": "claim_ID", attempt 1
  - Step "primary": "claim_ID", attempt 1
  

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step missing
  {"ok":false,"error":{"code":"PLAN_STEP_NOT_FOUND","message":"Plan step \"missing\" does not exist."}}
  [1]

Create a released-schema v4 fixture and claim its step through migration v5.

  $ mkdir -p legacy-v4/v4-test/database legacy-v4/v4-test/logs \
  >   legacy-v4/v4-test/exports legacy-v4/v4-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v4 legacy-v4/v4-test/database/sandwalk.sqlite3 v4-test

  $ sandwalk step claim --slug v4-test --directory-prefix legacy-v4 \
  >   --step fixture-step | sed -E 's/claim_[0-9a-f]{32}/claim_ID/g'
  {"ok":true,"result":{"claim":"claim_ID","step":"fixture-step","attempt":1}}

  $ ./inspect_workspace.exe legacy-v4/v4-test/database/sandwalk.sqlite3
  v4-test|researching
  24
  wal
  ok

Schema 21 converts legacy expired steps to resumable suspended steps.

  $ mkdir -p legacy-v20/v20-test/database legacy-v20/v20-test/logs \
  >   legacy-v20/v20-test/exports legacy-v20/v20-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v20 \
  >   legacy-v20/v20-test/database/sandwalk.sqlite3 v20-test

  $ sandwalk gc --slug v20-test --directory-prefix legacy-v20 \
  >   --raw --plan >/dev/null

  $ ./inspect_workspace.exe --inspect-claims \
  >   legacy-v20/v20-test/database/sandwalk.sqlite3
  completed-step|completed|1|NULL|0
  fixture-step|suspended|1|NULL|0
  completed-step|1|completed
  fixture-step|1|suspended
