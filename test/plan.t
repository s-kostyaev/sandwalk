  $ sandwalk init --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"initialized","schema_version":2}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key primary-sources --title "Review primary sources"
  {"ok":true,"result":{"key":"primary-sources","title":"Review primary sources","required":true,"position":1,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ cat workspaces/plan-test/exports/research-plan.md
  <!-- sandwalk-plan-revision: 1 -->
  # Research plan
  
  Phase: planning
  
  1. `primary-sources` (required)
     Title: "Review primary sources"

  $ sandwalk status --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"planning","schema_version":2}}

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key background --title "Collect background" --optional
  {"ok":true,"result":{"key":"background","title":"Collect background","required":false,"position":2,"phase":"planning","plan_path":"workspaces/plan-test/exports/research-plan.md"}}

  $ cat workspaces/plan-test/exports/research-plan.md
  <!-- sandwalk-plan-revision: 2 -->
  # Research plan
  
  Phase: planning
  
  1. `primary-sources` (required)
     Title: "Review primary sources"
  2. `background` (optional)
     Title: "Collect background"

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key background --title "Duplicate"
  {"ok":false,"error":{"code":"PLAN_STEP_EXISTS","message":"Plan step \"background\" already exists."}}
  [1]

  $ wc -l < workspaces/plan-test/logs/events.jsonl
        10

  $ sandwalk plan add-step --slug plan-test --directory-prefix workspaces \
  >   --key Bad/key --title "Invalid"
  {"ok":false,"error":{"code":"INVALID_PLAN_STEP_KEY","message":"Plan step key must use lowercase letters or digits, separated by single hyphens."}}
  [1]

  $ sandwalk resume --slug plan-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"plan-test","phase":"planning","resume_path":"workspaces/plan-test/artifacts/resume/workspace.md"}}

  $ sed -n '/## Durable entities/,+5p' workspaces/plan-test/artifacts/resume/workspace.md
  ## Durable entities
  
  The workspace record and these plan steps are durable:
  - 1. "primary-sources": "Review primary sources" (required)
  - 2. "background": "Collect background" (optional)
  

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
  2
  wal
  ok
