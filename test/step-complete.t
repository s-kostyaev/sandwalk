  $ mkdir -p workspace/rejected-test/database workspace/rejected-test/logs
  $ ./inspect_workspace.exe --create-v11 workspace/rejected-test/database/sandwalk.sqlite3 rejected-test
  $ cat > rejected.json <<'EOF'
  > {"protocol":"sandwalk.finding-review.v1","verdict":"unsupported","summary":"The excerpt does not establish the claim.","source_quality":"Primary source.","conflicts":"","qualifications":"Revise the finding."}
  > EOF

  $ sandwalk finding review \
  >   --slug rejected-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding --review-file rejected.json
  {"ok":true,"result":{"finding":"fixture-step/sealed-finding","revision":1,"verdict":"unsupported","reviewed":true,"state":"reviewed"}}

  $ sed 's/unsupported/supported/; s/The excerpt does not establish the claim/The excerpt establishes the narrow claim/' \
  >   rejected.json > supported.json
  $ sandwalk finding attach \
  >   --slug rejected-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation supports >/dev/null
  $ sandwalk finding seal \
  >   --slug rejected-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding >/dev/null
  $ sandwalk finding review \
  >   --slug rejected-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding --review-file supported.json >/dev/null

  $ sandwalk step complete \
  >   --slug rejected-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001
  {"ok":false,"error":{"code":"STEP_HAS_REJECTED_FINDINGS","message":"Step \"fixture-step\" has unsupported or contradicted findings."}}
  [1]
