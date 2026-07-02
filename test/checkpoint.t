  $ sandwalk init --slug checkpoint-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"checkpoint-test","phase":"initialized","schema_version":20}}

  $ sandwalk plan add-step --slug checkpoint-test --directory-prefix workspaces \
  >   --key source-review --title "Review sources"
  {"ok":true,"result":{"key":"source-review","title":"Review sources","required":true,"position":1,"phase":"planning","plan_path":"workspaces/checkpoint-test/exports/research-plan.md"}}

  $ sandwalk plan validate --slug checkpoint-test --directory-prefix workspaces >/dev/null
  $ sandwalk plan seal --slug checkpoint-test --directory-prefix workspaces >/dev/null

  $ claim=$(sandwalk step claim --slug checkpoint-test --directory-prefix workspaces \
  >   --step source-review --lease-seconds 60 | sed -E 's/.*"claim":"([^"]+)".*/\1/')

  $ printf 'Reviewed two primary sources.\n' > summary.md
  $ printf 'Extract exact excerpts next.\n' > next.md

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim "$claim" --summary-file summary.md --next-file next.md | \
  >   sed -E 's/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/'
  {"ok":true,"result":{"step":"source-review","checkpoint":1,"lease_expires_at":"TIMESTAMP"}}

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
  
  - None.
  

  $ ./inspect_workspace.exe --expire-claim workspaces/checkpoint-test/database/sandwalk.sqlite3 source-review

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim "$claim" --summary-file summary.md --next-file next.md
  {"ok":false,"error":{"code":"CLAIM_EXPIRED","message":"Claim lease has expired."}}
  [1]

  $ ./inspect_workspace.exe --inspect-claims workspaces/checkpoint-test/database/sandwalk.sqlite3
  source-review|expired|1|NULL|0
  source-review|1|expired

  $ sandwalk step checkpoint --slug checkpoint-test --directory-prefix workspaces \
  >   --claim claim_ffffffffffffffffffffffffffffffff \
  >   --summary-file summary.md --next-file next.md
  {"ok":false,"error":{"code":"CLAIM_NOT_FOUND","message":"Claim does not exist."}}
  [1]

Create a released-schema v5 fixture and checkpoint through migration v6.

  $ mkdir -p legacy-v5/v5-test/database legacy-v5/v5-test/logs \
  >   legacy-v5/v5-test/exports legacy-v5/v5-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v5 legacy-v5/v5-test/database/sandwalk.sqlite3 v5-test
  $ printf 'Legacy summary\n' > legacy-summary.md
  $ printf 'Legacy next\n' > legacy-next.md

  $ sandwalk step checkpoint --slug v5-test --directory-prefix legacy-v5 \
  >   --claim claim_00000000000000000000000000000001 \
  >   --summary-file legacy-summary.md --next-file legacy-next.md | \
  >   sed -E 's/"lease_expires_at":"[^"]+"/"lease_expires_at":"TIMESTAMP"/'
  {"ok":true,"result":{"step":"fixture-step","checkpoint":1,"lease_expires_at":"TIMESTAMP"}}

  $ ./inspect_workspace.exe legacy-v5/v5-test/database/sandwalk.sqlite3
  v5-test|researching
  20
  wal
  ok
