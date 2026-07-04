Rejecting a fetched candidate is a durable packet action. It skips the hit and
returns to a subject-aware search instead of forcing unusable evidence.

  $ mkdir -p reject/hit/database reject/hit/logs reject/hit/artifacts/work
  $ ./inspect_workspace.exe --create-v7 reject/hit/database/sandwalk.sqlite3 hit
  $ sandwalk continue --slug hit --directory-prefix reject >/dev/null
  $ grep -E '"(action|title|url|decision|rejection_reason)"' \
  >   reject/hit/artifacts/work/current.json
    "action": "fetch",
      "title": "Fixture result",
      "url": "https://example.test/start",
      "decision": "",
      "rejection_reason": "",
  $ sed -e 's/"decision": ""/"decision": "reject"/' \
  >   -e 's/"rejection_reason": ""/"rejection_reason": "Irrelevant result."/' \
  >   reject/hit/artifacts/work/current.json > rejected.json
  $ mv rejected.json reject/hit/artifacts/work/current.json
  $ sandwalk apply --file reject/hit/artifacts/work/current.json
  {"ok":true,"result":{"applied":"fetch","packet":"reject/hit/artifacts/work/current.json"},"next":"'sandwalk' 'continue' '--slug' 'hit' '--directory-prefix' 'reject'"}
  $ sandwalk continue --slug hit --directory-prefix reject >/dev/null
  $ grep -E '"(action|research_objective|step_title|query)"' \
  >   reject/hit/artifacts/work/current.json
    "action": "search",
      "research_objective": "Fixture step",
      "step_title": "Fixture step"
    "editable": { "query": "Fixture step — Fixture step", "source_root": "" },

The packet can select a sandbox-visible local source root without bypassing
Sandwalk retrieval.

  $ mkdir -p "local documents"
  $ touch "local documents/Architecture Notes.pdf"
  $ sed -e 's#"source_root": ""#"source_root": "'"$PWD"'/local documents"#' \
  >   reject/hit/artifacts/work/current.json > local-search.json
  $ mv local-search.json reject/hit/artifacts/work/current.json
  $ PATH="$PWD/fakes:$PATH" sandwalk apply \
  >   --file reject/hit/artifacts/work/current.json >/dev/null
  $ sqlite3 reject/hit/database/sandwalk.sqlite3 \
  >   "SELECT source_root FROM search_queries ORDER BY query_id DESC LIMIT 1;" | \
  >   sed "s#$PWD#ROOT#"
  ROOT/local documents

An agent can reject a bad query path and restart search without exhausting all
of its irrelevant hits. Guidance prefers the newest query.

  $ mkdir -p restart/restart/database restart/restart/logs \
  >   restart/restart/artifacts/work
  $ ./inspect_workspace.exe --create-v7 \
  >   restart/restart/database/sandwalk.sqlite3 restart
  $ sandwalk continue --slug restart --directory-prefix restart >/dev/null
  $ sed -e 's/"decision": ""/"decision": "restart-search"/' \
  >   -e 's/"rejection_reason": ""/"rejection_reason": "The query omitted the subject."/' \
  >   -e 's/"replacement_query": "[^"]*"/"replacement_query": "oxcaml features"/' \
  >   restart/restart/artifacts/work/current.json > restarted.json
  $ mv restarted.json restart/restart/artifacts/work/current.json
  $ PATH="$PWD/fakes:$PATH" sandwalk apply \
  >   --file restart/restart/artifacts/work/current.json >/dev/null
  $ sqlite3 restart/restart/database/sandwalk.sqlite3 \
  >   "SELECT query FROM search_queries ORDER BY query_id DESC LIMIT 1;"
  oxcaml features
  $ sandwalk continue --slug restart --directory-prefix restart | \
  >   sed -E 's/hit_[0-9a-f]{32}/hit_ID/g'
  {"ok":true,"result":{"packet":"restart/restart/artifacts/work/current.json","loop":"Edit only editable; keep integrity_md5 unchanged; apply the packet; then run continue again.","phase":"researching","action":"fetch","reason":"The selected active step has an unfetched search result and no snapshot.","advisory":true,"alternatives_possible":true,"step":"fixture-step","claim":"claim_00000000000000000000000000000001","hit":"hit_ID","hit_title":"Primary result","hit_url":"https://example.test/primary","hit_snippet":"A deterministic search result."},"next":"'sandwalk' 'apply' '--file' 'restart/restart/artifacts/work/current.json'"}

A context-only evidence bundle cannot seal a finding.

  $ mkdir -p context/context-test/database context/context-test/logs
  $ ./inspect_workspace.exe --create-v10 \
  >   context/context-test/database/sandwalk.sqlite3 context-test
  $ sandwalk finding attach \
  >   --slug context-test --directory-prefix context \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation context >/dev/null
  $ sandwalk finding seal \
  >   --slug context-test --directory-prefix context \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding
  {"ok":false,"error":{"code":"FINDING_HAS_NO_EVIDENCE","message":"Finding \"fixture-step/fixture-finding\" must have non-context evidence before sealing."},"next":"'sandwalk' 'next' '--slug' 'context-test' '--directory-prefix' 'context'"}
  [1]
  $ sandwalk continue --slug context-test --directory-prefix context >/dev/null
  $ grep -E '"(action|workflow_action)"' \
  >   context/context-test/artifacts/work/current.json
    "action": "create-excerpt",
    "workflow_action": "create-excerpt",

A completed finding can be explicitly reopened before drafting. The repair
suspends other active claims, creates an evidence-empty draft revision, and
rejects the previous evidence for this step.

  $ mkdir -p repair/repair-test/database repair/repair-test/logs \
  >   repair/repair-test/exports
  $ ./inspect_workspace.exe --create-v11 \
  >   repair/repair-test/database/sandwalk.sqlite3 repair-test
  $ cat > accepted.json <<'EOF'
  > {"protocol":"sandwalk.finding-review.v1","verdict":"supported","summary":"Accepted fixture.","source_quality":"Primary.","conflicts":"","qualifications":""}
  > EOF
  $ sandwalk finding review \
  >   --slug repair-test --directory-prefix repair \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/sealed-finding --review-file accepted.json >/dev/null
  $ sandwalk finding attach \
  >   --slug repair-test --directory-prefix repair \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding \
  >   --excerpt excerpt_00000000000000000000000000000001 \
  >   --relation supports >/dev/null
  $ sandwalk finding seal \
  >   --slug repair-test --directory-prefix repair \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding >/dev/null
  $ sandwalk finding review \
  >   --slug repair-test --directory-prefix repair \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/fixture-finding --review-file accepted.json >/dev/null
  $ sandwalk step complete \
  >   --slug repair-test --directory-prefix repair \
  >   --claim claim_00000000000000000000000000000001 >/dev/null
  $ printf 'The current evidence does not cover the finding.' > reason.md
  $ sandwalk finding repair \
  >   --slug repair-test --directory-prefix repair \
  >   --finding fixture-step/fixture-finding --reason-file reason.md
  {"ok":true,"result":{"finding":"fixture-step/fixture-finding","revision":2,"suspended_claims":0,"rejected_excerpts":1},"next":"'sandwalk' 'continue' '--slug' 'repair-test' '--directory-prefix' 'repair'"}
  $ sqlite3 repair/repair-test/database/sandwalk.sqlite3 \
  >   "SELECT f.current_revision,f.state,e.state FROM findings f JOIN step_executions e USING(step_key) WHERE f.step_key='fixture-step' AND f.finding_key='fixture-finding';"
  2|draft|suspended
  $ sandwalk continue --slug repair-test --directory-prefix repair >/dev/null
  $ sandwalk apply \
  >   --file repair/repair-test/artifacts/work/current.json >/dev/null
  $ sandwalk continue --slug repair-test --directory-prefix repair | \
  >   sed -E 's/claim_[0-9a-f]{32}/claim_ID/g'
  {"ok":true,"result":{"packet":"repair/repair-test/artifacts/work/current.json","loop":"Edit only editable; keep integrity_md5 unchanged; apply the packet; then run continue again.","phase":"researching","action":"create-excerpt","reason":"Inspect the selected normalized snapshot, then create an exact excerpt from a semantically relevant range.","advisory":true,"alternatives_possible":true,"step":"fixture-step","claim":"claim_ID","snapshot":"snap_00000000000000000000000000000001","document_path":"workspace/repair-test/artifacts/snapshots/snap_00000000000000000000000000000001/document.md"},"next":"'sandwalk' 'apply' '--file' 'repair/repair-test/artifacts/work/current.json'"}

Released schema 21 migrates candidate rejection and finding repair state.

  $ mkdir -p legacy21/legacy21/database legacy21/legacy21/logs
  $ ./inspect_workspace.exe --create-v21 \
  >   legacy21/legacy21/database/sandwalk.sqlite3 legacy21
  $ sandwalk continue --slug legacy21 --directory-prefix legacy21 >/dev/null
  $ sqlite3 legacy21/legacy21/database/sandwalk.sqlite3 \
  >   "SELECT (SELECT COUNT(*) FROM candidate_rejections), (SELECT COUNT(*) FROM finding_repairs), user_version FROM pragma_user_version;"
  0|0|23
