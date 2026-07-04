Create a current research fixture with one registered excerpt and no findings.

  $ mkdir -p workspace/continue-test/database workspace/continue-test/logs \
  >   workspace/continue-test/artifacts/work
  $ ./inspect_workspace.exe --create-v10 \
  >   workspace/continue-test/database/sandwalk.sqlite3 continue-test
  $ sandwalk next --slug continue-test --directory-prefix workspace >/dev/null
  $ ./inspect_workspace.exe --clear-findings \
  >   workspace/continue-test/database/sandwalk.sqlite3

`continue` materializes one editable packet and returns one universal apply
command.

  $ sandwalk continue --slug continue-test --directory-prefix workspace
  {"ok":true,"result":{"packet":"workspace/continue-test/artifacts/work/current.json","loop":"Edit only editable; keep integrity_md5 unchanged; apply the packet; then run continue again.","phase":"researching","action":"create-finding","reason":"The selected active step has exact evidence but no finding. Author a bounded statement in finding.md.","advisory":true,"alternatives_possible":true,"step":"fixture-step","claim":"claim_00000000000000000000000000000001","candidate_excerpt":"excerpt_00000000000000000000000000000001","candidate_excerpt_path":"fixture-excerpt.md"},"next":"'sandwalk' 'apply' '--file' 'workspace/continue-test/artifacts/work/current.json'"}

  $ grep -E '"(protocol|action|candidate_excerpt|key|statement|relation)"' \
  >   workspace/continue-test/artifacts/work/current.json
    "protocol": "sandwalk.work.v1",
    "action": "create-finding",
      "candidate_excerpt": "excerpt_00000000000000000000000000000001",
      "key": "finding",
      "statement": "",
      "relation": "",

Incomplete semantic fields fail before any mutation.

  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":false,"error":{"code":"INVALID_WORK_PACKET","message":"Fill every editable field with a valid value and retry apply."}}
  [1]

Fixed context is integrity-bound. Editing it invalidates the packet before any
child command runs.

  $ sed -e 's/fixture-excerpt.md/other-excerpt.md/' \
  >   workspace/continue-test/artifacts/work/current.json > tampered.json
  $ mv tampered.json workspace/continue-test/artifacts/work/current.json
  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":false,"error":{"code":"INVALID_WORK_PACKET","message":"Work-packet fixed fields or integrity_md5 changed. Run sandwalk continue again, edit only editable, and keep integrity_md5 unchanged."}}
  [1]
  $ sandwalk continue --slug continue-test --directory-prefix workspace >/dev/null

Malformed and unsupported packets distinguish their repair paths.

  $ printf '{\n' > workspace/continue-test/artifacts/work/current.json
  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":false,"error":{"code":"INVALID_WORK_PACKET","message":"Work packet is malformed. Run sandwalk continue again and apply the regenerated current.json."}}
  [1]
  $ sandwalk continue --slug continue-test --directory-prefix workspace >/dev/null

  $ sed -e 's/sandwalk.work.v1/sandwalk.work.v0/' \
  >   workspace/continue-test/artifacts/work/current.json > unsupported.json
  $ mv unsupported.json workspace/continue-test/artifacts/work/current.json
  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":false,"error":{"code":"INVALID_WORK_PACKET","message":"Work packet protocol is missing or unsupported. Run sandwalk continue again and apply the regenerated current.json."}}
  [1]
  $ sandwalk continue --slug continue-test --directory-prefix workspace >/dev/null

Only the canonical current packet path can be applied.

  $ cp workspace/continue-test/artifacts/work/current.json copied-packet.json
  $ sandwalk apply --file copied-packet.json
  {"ok":false,"error":{"code":"INVALID_WORK_PACKET","message":"Work packet workspace or path is invalid. Apply only the exact current.json path returned by sandwalk continue."}}
  [1]

Fill only the semantic fields. Applying the packet creates, attaches, and seals
the finding without requiring the agent to reproduce identifiers or CLI flags.

  $ sed -e 's/"statement": ""/"statement": "Fixture claim."/' \
  >   -e 's/"relation": ""/"relation": "supports"/' \
  >   -e 's/"decision": ""/"decision": "accept"/' \
  >   workspace/continue-test/artifacts/work/current.json > filled.json
  $ mv filled.json workspace/continue-test/artifacts/work/current.json

  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":true,"result":{"applied":"create-finding","packet":"workspace/continue-test/artifacts/work/current.json"},"next":"'sandwalk' 'continue' '--slug' 'continue-test' '--directory-prefix' 'workspace'"}

  $ ./inspect_workspace.exe --inspect-findings \
  >   workspace/continue-test/database/sandwalk.sqlite3
  fixture-step|finding|1|sealed|32|14|Fixture claim.

The next packet embeds the exact review protocol and allowed verdicts.

  $ sandwalk continue --slug continue-test --directory-prefix workspace >/dev/null
  $ grep -E '"(action|protocol|verdict|summary|source_quality|conflicts|qualifications)"' \
  >   workspace/continue-test/artifacts/work/current.json
    "protocol": "sandwalk.work.v1",
    "action": "review-finding",
        "protocol": "sandwalk.finding-review.v1",
        "verdict": "",
        "summary": "",
        "source_quality": "",
        "conflicts": "",
        "qualifications": ""

The review packet also carries the exact current statement and evidence paths,
so a fresh agent does not have to reconstruct review context.

  $ grep -E '"(statement|evidence|excerpt|path|relation)"' \
  >   workspace/continue-test/artifacts/work/current.json
      "statement": "Fixture claim.",
      "evidence": [
          "excerpt": "excerpt_00000000000000000000000000000001",
          "path": "fixture-excerpt.md",
          "relation": "supports"

  $ sed -e 's/"verdict": ""/"verdict": "supported"/' \
  >   -e 's/"summary": ""/"summary": "Exact evidence supports the claim."/' \
  >   -e 's/"source_quality": ""/"source_quality": "Primary source."/' \
  >   workspace/continue-test/artifacts/work/current.json > reviewed.json
  $ mv reviewed.json workspace/continue-test/artifacts/work/current.json

  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":true,"result":{"applied":"review-finding","packet":"workspace/continue-test/artifacts/work/current.json"},"next":"'sandwalk' 'continue' '--slug' 'continue-test' '--directory-prefix' 'workspace'"}

Mechanical gates use the same packet/apply loop.

  $ sandwalk continue --slug continue-test --directory-prefix workspace >/dev/null
  $ grep -E '"(action|workflow_action)"' \
  >   workspace/continue-test/artifacts/work/current.json
    "action": "run-command",
    "workflow_action": "complete-step",

  $ sandwalk apply --file workspace/continue-test/artifacts/work/current.json
  {"ok":true,"result":{"applied":"run-command","packet":"workspace/continue-test/artifacts/work/current.json"},"next":"'sandwalk' 'continue' '--slug' 'continue-test' '--directory-prefix' 'workspace'"}

  $ sandwalk status --slug continue-test --directory-prefix workspace
  {"ok":true,"result":{"slug":"continue-test","phase":"evidence-review","schema_version":23}}
