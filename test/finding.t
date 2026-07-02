  $ mkdir -p workspace/finding-test/database workspace/finding-test/logs
  $ ./inspect_workspace.exe --create-v9 workspace/finding-test/database/sandwalk.sqlite3 finding-test
  $ printf 'The fixture result supports the small claim.\n' > claim.md

  $ sandwalk finding create \
  >   --slug finding-test --directory-prefix workspace \
  >   --step fixture-step \
  >   --claim claim_00000000000000000000000000000001 \
  >   --key small-claim --claim-file claim.md
  {"ok":true,"result":{"finding":"fixture-step/small-claim","revision":1,"state":"draft"}}

  $ ./inspect_workspace.exe --inspect-findings workspace/finding-test/database/sandwalk.sqlite3
  fixture-step|small-claim|1|draft|32|45|The fixture result supports the small claim.
  

  $ sandwalk finding seal \
  >   --slug finding-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/small-claim
  {"ok":false,"error":{"code":"FINDING_HAS_NO_EVIDENCE","message":"Finding \"fixture-step/small-claim\" must have evidence before sealing."}}
  [1]

  $ sandwalk step complete \
  >   --slug finding-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001
  {"ok":false,"error":{"code":"STEP_HAS_UNREVIEWED_FINDINGS","message":"Step \"fixture-step\" has draft, sealed, or stale findings."}}
  [1]

  $ ./inspect_workspace.exe workspace/finding-test/database/sandwalk.sqlite3
  finding-test|researching
  19
  wal
  ok

  $ sandwalk finding create \
  >   --slug finding-test --directory-prefix workspace \
  >   --step fixture-step \
  >   --claim claim_00000000000000000000000000000001 \
  >   --key small-claim --claim-file claim.md
  {"ok":false,"error":{"code":"FINDING_EXISTS","message":"Finding \"fixture-step/small-claim\" already exists."}}
  [1]

  $ sandwalk finding create \
  >   --slug finding-test --directory-prefix workspace \
  >   --step completed-step \
  >   --claim claim_00000000000000000000000000000001 \
  >   --key wrong-step --claim-file claim.md
  {"ok":false,"error":{"code":"FINDING_STEP_MISMATCH","message":"Active claim belongs to another plan step."}}
  [1]
