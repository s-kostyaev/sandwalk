  $ sandwalk init --slug checkpoint-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"checkpoint-test","phase":"initialized","schema_version":22}}

  $ sandwalk plan add-step --slug checkpoint-test --directory-prefix workspaces \
  >   --key source-review --title "Review sources"
  {"ok":true,"result":{"key":"source-review","title":"Review sources","required":true,"position":1,"phase":"planning","plan_path":"workspaces/checkpoint-test/exports/research-plan.md"}}

  $ sandwalk plan validate --slug checkpoint-test --directory-prefix workspaces >/dev/null
  $ sandwalk plan seal --slug checkpoint-test --directory-prefix workspaces >/dev/null

  $ claim=$(sandwalk step claim --slug checkpoint-test --directory-prefix workspaces \
  >   --step source-review | sed -E 's/.*"claim":"([^"]+)".*/\1/')

  $ printf 'Reviewed two primary sources.\n' > summary.md
  $ printf 'Extract exact excerpts next.\n' > next.md

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim "$claim" --summary-file summary.md --next-file next.md
  {"ok":true,"result":{"step":"source-review","checkpoint":1}}

  $ ./inspect_workspace.exe --inspect-checkpoints workspaces/checkpoint-test/database/sandwalk.sqlite3
  source-review|1|Reviewed two primary sources.
  |Extract exact excerpts next.
  |32|30|32|29

  $ sandwalk resume --slug checkpoint-test --directory-prefix workspaces >/dev/null

  $ sed -n '/## Latest checkpoint/,+6p' workspaces/checkpoint-test/artifacts/resume/workspace.md | \
  >   sed -E 's/- Created: "[^"]+"/- Created: "TIMESTAMP"/'
  ## Latest checkpoint
  
  - Step: "source-review"
  - Created: "TIMESTAMP"
  - Summary: "Reviewed two primary sources.\n"
  - Next: "Extract exact excerpts next.\n"
  
  $ sed -n '/## Recent commands/,+3p' \
  >   workspaces/checkpoint-test/artifacts/resume/workspace.md
  ## Recent commands
  
  These are historical audit entries. They do not override the current phase, active claims, or durable entities above.
  

  $ ./inspect_workspace.exe --set-legacy-deadline \
  >   workspaces/checkpoint-test/database/sandwalk.sqlite3 source-review

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim "$claim" --summary-file summary.md --next-file next.md
  {"ok":true,"result":{"step":"source-review","checkpoint":2}}

  $ ./inspect_workspace.exe --inspect-claims workspaces/checkpoint-test/database/sandwalk.sqlite3
  source-review|claimed|1|38|1
  source-review|1|NULL

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim claim_ffffffffffffffffffffffffffffffff \
  >   --summary-file summary.md --next-file next.md
  {"ok":false,"error":{"code":"CLAIM_NOT_FOUND","message":"Claim does not exist."},"next":"'sandwalk' 'resume' '--slug' 'checkpoint-test' '--directory-prefix' 'workspaces'"}
  [1]

Create a released-schema v5 fixture and checkpoint through migration v6.

  $ mkdir -p legacy-v5/v5-test/database legacy-v5/v5-test/logs \
  >   legacy-v5/v5-test/exports legacy-v5/v5-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v5 legacy-v5/v5-test/database/sandwalk.sqlite3 v5-test
  $ printf 'Legacy summary\n' > legacy-summary.md
  $ printf 'Legacy next\n' > legacy-next.md

  $ sandwalk step checkpoint --slug v5-test --directory-prefix legacy-v5 \
  >   --claim claim_00000000000000000000000000000001 \
  >   --summary-file legacy-summary.md --next-file legacy-next.md
  {"ok":true,"result":{"step":"fixture-step","checkpoint":1}}

  $ ./inspect_workspace.exe legacy-v5/v5-test/database/sandwalk.sqlite3
  v5-test|researching
  22
  wal
  ok
