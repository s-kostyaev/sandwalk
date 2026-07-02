  $ mkdir -p workspace/attach-test/database workspace/attach-test/logs
  $ ./inspect_workspace.exe --create-v10 workspace/attach-test/database/sandwalk.sqlite3 attach-test

  $ sandwalk finding attach \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation supports
  {"ok":true,"result":{"finding":"fixture-step/fixture-finding","revision":1,"attached":true,"revised":false}}

Duplicate attachment is idempotent.

  $ sandwalk finding attach \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation supports
  {"ok":true,"result":{"finding":"fixture-step/fixture-finding","revision":1,"attached":false,"revised":false}}

  $ sandwalk finding seal \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding
  {"ok":true,"result":{"finding":"fixture-step/fixture-finding","revision":1,"state":"sealed","already_sealed":false}}

Sealing is idempotent.

  $ sandwalk finding seal \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding
  {"ok":true,"result":{"finding":"fixture-step/fixture-finding","revision":1,"state":"sealed","already_sealed":true}}

Changing a sealed finding creates a new draft revision.

  $ sandwalk finding attach \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation qualifies
  {"ok":true,"result":{"finding":"fixture-step/sealed-finding","revision":2,"attached":true,"revised":true}}

  $ ./inspect_workspace.exe --inspect-evidence workspace/attach-test/database/sandwalk.sqlite3
  fixture-step|fixture-finding|1|excerpt_00000000000000000000000000000001|supports
  fixture-step|sealed-finding|2|excerpt_00000000000000000000000000000001|qualifies

  $ ./inspect_workspace.exe workspace/attach-test/database/sandwalk.sqlite3
  attach-test|researching
  16
  wal
  ok

  $ sandwalk finding attach \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000002 \
  >   --relation supports
  {"ok":false,"error":{"code":"EXCERPT_NOT_FOUND","message":"Excerpt \"excerpt_00000000000000000000000000000002\" does not exist."}}
  [1]

  $ sandwalk finding attach \
  >   --slug attach-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation maybe
  {"ok":false,"error":{"code":"INVALID_RELATION","message":"Relation must be supports, contradicts, qualifies, or context."}}
  [1]
