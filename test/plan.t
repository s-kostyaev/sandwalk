  $ sandwalk init --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"initialized","schema_version":3}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key primary-sources --title "Review primary sources"
  {"ok":true,"result":{"key":"primary-sources","title":"Review primary sources","required":true,"position":1,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ cat workspaces/plan-test/exports/research-plan.md
  <!-- sandwalk-projection-version: 2 -->
  <!-- sandwalk-plan-revision: 1 -->
  # Research plan
  
  Phase: planning
  Validation: pending
  
  1. `primary-sources` (required)
     Title: "Review primary sources"

  $ sandwalk status --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"planning","schema_version":3}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key background --title "Collect background" --optional
  {"ok":true,"result":{"key":"background","title":"Collect background","required":false,"position":2,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ cat workspaces/plan-test/exports/research-plan.md
  <!-- sandwalk-projection-version: 4 -->
  <!-- sandwalk-plan-revision: 2 -->
  # Research plan
  
  Phase: planning
  Validation: pending
  
  1. `primary-sources` (required)
     Title: "Review primary sources"
  2. `background` (optional)
     Title: "Collect background"

  $ sandwalk plan validate --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":2,"validated":true,"already_validated":false,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ grep '^Validation:' workspaces/plan-test/exports/research-plan.md
  Validation: current

  $ sandwalk plan validate --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":2,"validated":true,"already_validated":true,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key follow-up --title "Follow up"
  {"ok":true,"result":{"key":"follow-up","title":"Follow up","required":true,"position":3,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ grep '^Validation:' workspaces/plan-test/exports/research-plan.md
  Validation: pending

  $ sandwalk plan validate --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":3,"validated":true,"already_validated":false,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key background --title "Duplicate"
  {"ok":false,"error":{"code":"PLAN_STEP_EXISTS","message":"Plan step \"background\" already exists."}}
  [1]

  $ wc -l < workspaces/plan-test/logs/events.jsonl
        18

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key Bad/key --title "Invalid"
  {"ok":false,"error":{"code":"INVALID_PLAN_STEP_KEY","message":"Plan step key must use lowercase letters or digits, separated by single hyphens."}}
  [1]

  $ sandwalk resume --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"planning","resume_path":"workspaces/plan-test/artifacts/resume/workspace.md"}}

  $ sed -n '/## Durable entities/,+6p' workspaces/plan-test/artifacts/resume/workspace.md
  ## Durable entities
  
  The workspace record and these plan steps are durable:
  - 1. "primary-sources": "Review primary sources" (required)
  - 2. "background": "Collect background" (optional)
  - 3. "follow-up": "Follow up" (required)
  

Create a released-schema v1 fixture and prove the first plan mutation upgrades it.

  $ mkdir -p legacy/legacy-test/database legacy/legacy-test/logs \
  >   legacy/legacy-test/exports legacy/legacy-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v1 legacy/legacy-test/database/sandwalk.sqlite3 legacy-test

  $ sandwalk status --slug legacy-test --directory-prefix legacy
  {"ok":true,"result":{"slug":"legacy-test","phase":"initialized","schema_version":1}}

  $ sandwalk plan add-step --slug legacy-test --directory-prefix legacy \
  >   --key migrated-step --title "Upgrade then append"
  {"ok":true,"result":{"key":"migrated-step","title":"Upgrade then append","required":true,"position":1,"phase":"planning","plan_path":"legacy/legacy-test/exports/research-plan.md"}}

  $ ./inspect_workspace.exe legacy/legacy-test/database/sandwalk.sqlite3
  legacy-test|planning
  3
  wal
  ok

Create a released-schema v2 fixture and validate it through the v3 migration.

  $ mkdir -p legacy-v2/v2-test/database legacy-v2/v2-test/logs \
  >   legacy-v2/v2-test/exports legacy-v2/v2-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v2 legacy-v2/v2-test/database/sandwalk.sqlite3 v2-test

  $ sandwalk status --slug v2-test --directory-prefix legacy-v2
  {"ok":true,"result":{"slug":"v2-test","phase":"planning","schema_version":2}}

  $ sandwalk plan validate --slug v2-test --directory-prefix legacy-v2
  {"ok":true,"result":{"revision":1,"validated":true,"already_validated":false,"phase":"planning","plan_path":"legacy-v2/v2-test/exports/research-plan.md"}}

  $ ./inspect_workspace.exe legacy-v2/v2-test/database/sandwalk.sqlite3
  v2-test|planning
  3
  wal
  ok
