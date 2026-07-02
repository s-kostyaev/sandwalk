  $ sandwalk init --slug dag-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"dag-test","phase":"initialized","schema_version":20}}
  $ printf 'Determine a small, well-sourced answer.\n' > objective.md

  $ sandwalk plan set-objective \
  >   --slug dag-test --directory-prefix workspaces --file objective.md
  {"ok":true,"result":{"revision":1,"phase":"planning","plan_path":"workspaces/dag-test/exports/research-plan.md"}}

  $ sandwalk plan add-step \
  >   --slug dag-test --directory-prefix workspaces \
  >   --key collect --title 'Collect exact evidence' >/dev/null
  $ sandwalk plan add-step \
  >   --slug dag-test --directory-prefix workspaces \
  >   --key synthesize --title 'Synthesize the answer' >/dev/null

  $ sandwalk plan add-dependency \
  >   --slug dag-test --directory-prefix workspaces \
  >   synthesize --on collect
  {"ok":true,"result":{"revision":4,"step":"synthesize","depends_on":"collect","plan_path":"workspaces/dag-test/exports/research-plan.md"}}

Cycles and self-dependencies are rejected transactionally.

  $ sandwalk plan add-dependency \
  >   --slug dag-test --directory-prefix workspaces \
  >   collect --on synthesize
  {"ok":false,"error":{"code":"PLAN_DEPENDENCY_CYCLE","message":"Plan dependency would create a cycle."}}
  [1]

  $ sandwalk plan add-dependency \
  >   --slug dag-test --directory-prefix workspaces \
  >   collect --on collect
  {"ok":false,"error":{"code":"PLAN_DEPENDENCY_SELF","message":"A plan step cannot depend on itself."}}
  [1]

  $ sandwalk plan list --slug dag-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"planning","revision":4,"objective":"Determine a small, well-sourced answer.\n","steps":[{"key":"collect","title":"Collect exact evidence","required":true,"position":1},{"key":"synthesize","title":"Synthesize the answer","required":true,"position":2}],"dependencies":[{"step":"synthesize","depends_on":"collect"}],"extensions":[]}}

  $ grep -E '^(##|Determine|1[.]|2[.]|- `)' \
  >   workspaces/dag-test/exports/research-plan.md
  ## Objective
  Determine a small, well-sourced answer.
  ## Steps
  1. `collect` (required)
  2. `synthesize` (required)
  ## Dependencies
  - `synthesize` depends on `collect`

  $ sandwalk plan validate --slug dag-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":4,"validated":true,"already_validated":false,"phase":"planning","plan_path":"workspaces/dag-test/exports/research-plan.md"}}
  $ sandwalk plan seal --slug dag-test --directory-prefix workspaces
  {"ok":true,"result":{"revision":4,"sealed":true,"already_sealed":false,"phase":"researching","plan_path":"workspaces/dag-test/exports/research-plan.md"}}

  $ sandwalk step claim \
  >   --slug dag-test --directory-prefix workspaces --step synthesize
  {"ok":false,"error":{"code":"STEP_DEPENDENCIES_INCOMPLETE","message":"Plan step \"synthesize\" has incomplete dependencies."},"next":"'sandwalk' 'next' '--slug' 'dag-test' '--directory-prefix' 'workspaces'"}
  [1]

  $ sandwalk step claim \
  >   --slug dag-test --directory-prefix workspaces --step collect | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+Z/TIMESTAMP/g'
  {"ok":true,"result":{"claim":"claim_ID","step":"collect","attempt":1,"lease_expires_at":"TIMESTAMP"}}
