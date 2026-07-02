  $ mkdir -p workspace/review-test/database workspace/review-test/logs
  $ ./inspect_workspace.exe --create-v11 workspace/review-test/database/sandwalk.sqlite3 review-test
  $ cat > review.json <<'EOF'
  > {"protocol":"sandwalk.finding-review.v1","verdict":"partially-supported","summary":"The excerpt supports the narrow claim.","source_quality":"Primary source.","conflicts":"","qualifications":"Keep the claim narrow."}
  > EOF

  $ sandwalk finding review \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding --review-file review.json
  {"ok":true,"result":{"finding":"fixture-step/sealed-finding","revision":1,"verdict":"partially-supported","reviewed":true,"state":"reviewed"}}

The identical review is idempotent.

  $ sandwalk finding review \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding --review-file review.json
  {"ok":true,"result":{"finding":"fixture-step/sealed-finding","revision":1,"verdict":"partially-supported","reviewed":false,"state":"reviewed"}}

  $ ./inspect_workspace.exe --inspect-reviews workspace/review-test/database/sandwalk.sqlite3
  fixture-step|sealed-finding|1|partially-supported|32|The excerpt supports the narrow claim.

  $ ./inspect_workspace.exe workspace/review-test/database/sandwalk.sqlite3
  review-test|researching
  12
  wal
  ok

Draft findings cannot be reviewed.

  $ sandwalk finding review \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding --review-file review.json
  {"ok":false,"error":{"code":"FINDING_NOT_SEALED","message":"Finding \"fixture-step/fixture-finding\" must be sealed before review."}}
  [1]

A different review cannot silently replace the current revision's review.

  $ sed 's/partially-supported/unsupported/' review.json > conflicting.json
  $ sandwalk finding review \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding --review-file conflicting.json
  {"ok":false,"error":{"code":"FINDING_REVIEW_EXISTS","message":"Finding \"fixture-step/sealed-finding\" already has a different current review."}}
  [1]

Complete the other current finding before completing the step.

  $ sandwalk finding attach \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation supports >/dev/null
  $ sandwalk finding seal \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding >/dev/null
  $ sandwalk finding review \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding --review-file review.json >/dev/null

  $ sandwalk step complete \
  >   --slug review-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001
  {"ok":true,"result":{"step":"fixture-step","state":"completed","phase":"evidence-review"}}

  $ ./inspect_workspace.exe workspace/review-test/database/sandwalk.sqlite3
  review-test|evidence-review
  12
  wal
  ok
