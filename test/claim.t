  $ sandwalk init --slug claim-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"claim-test","phase":"initialized","schema_version":8}}

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
  >   --step primary --lease-seconds 60 | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/'
  {"ok":true,"result":{"claim":"claim_ID","step":"primary","attempt":1,"lease_expires_at":"TIMESTAMP"}}

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary --lease-seconds 60
  {"ok":false,"error":{"code":"STEP_ALREADY_CLAIMED","message":"Plan step already has an active claim."}}
  [1]

Two concurrent contenders must produce exactly one claim.

  $ (sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >    --step parallel --lease-seconds 60 >one.out; echo $? >one.status) &
  $ (sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >    --step parallel --lease-seconds 60 >two.out; echo $? >two.status) &
  $ wait

  $ sort one.status two.status
  0
  1

  $ cat one.out two.out | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/' | \
  >   sort
  {"ok":false,"error":{"code":"STEP_ALREADY_CLAIMED","message":"Plan step already has an active claim."}}
  {"ok":true,"result":{"claim":"claim_ID","step":"parallel","attempt":1,"lease_expires_at":"TIMESTAMP"}}

  $ ./inspect_workspace.exe --inspect-claims workspaces/claim-test/database/sandwalk.sqlite3
  parallel|claimed|1|38|1
  primary|claimed|1|38|1
  parallel|1|NULL
  primary|1|NULL

Force the active lease into the past and verify atomic expiry and reassignment.

  $ ./inspect_workspace.exe --expire-claim workspaces/claim-test/database/sandwalk.sqlite3 primary

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary --lease-seconds 60 | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/'
  {"ok":true,"result":{"claim":"claim_ID","step":"primary","attempt":2,"lease_expires_at":"TIMESTAMP"}}

  $ ./inspect_workspace.exe --inspect-claims workspaces/claim-test/database/sandwalk.sqlite3
  parallel|claimed|1|38|1
  primary|claimed|2|38|1
  parallel|1|NULL
  primary|1|expired
  primary|2|NULL

  $ sandwalk resume --slug claim-test --directory-prefix workspaces >/dev/null

  $ sed -n '/## Active claims/,+4p' workspaces/claim-test/artifacts/resume/workspace.md | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/expires "[^"]+"/expires "TIMESTAMP"/'
  ## Active claims
  
  - Step "parallel": "claim_ID", attempt 1, expires "TIMESTAMP"
  - Step "primary": "claim_ID", attempt 2, expires "TIMESTAMP"
  

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step missing
  {"ok":false,"error":{"code":"PLAN_STEP_NOT_FOUND","message":"Plan step \"missing\" does not exist."}}
  [1]

  $ sandwalk step claim --slug claim-test --directory-prefix workspaces \
  >   --step primary --lease-seconds 10
  {"ok":false,"error":{"code":"INVALID_LEASE","message":"Lease duration must be between 30 and 86400 seconds."}}
  [1]

Create a released-schema v4 fixture and claim its step through migration v5.

  $ mkdir -p legacy-v4/v4-test/database legacy-v4/v4-test/logs \
  >   legacy-v4/v4-test/exports legacy-v4/v4-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v4 legacy-v4/v4-test/database/sandwalk.sqlite3 v4-test

  $ sandwalk step claim --slug v4-test --directory-prefix legacy-v4 \
  >   --step fixture-step --lease-seconds 60 | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/'
  {"ok":true,"result":{"claim":"claim_ID","step":"fixture-step","attempt":1,"lease_expires_at":"TIMESTAMP"}}

  $ ./inspect_workspace.exe legacy-v4/v4-test/database/sandwalk.sqlite3
  v4-test|researching
  8
  wal
  ok
