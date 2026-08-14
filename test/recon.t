  $ sandwalk init --slug recon-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"recon-test","phase":"initialized","schema_version":26}}
  $ printf 'Map the small topic before planning.' > goal.md

  $ sandwalk recon start \
  >   --slug recon-test --directory-prefix workspaces --goal-file goal.md
  {"ok":true,"result":{"phase":"reconnaissance","observations":0}}

Search and fetch do not require a claim during reconnaissance.

  $ search_result=$(PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug recon-test --directory-prefix workspaces \
  >   --query 'small topic' --limit 1 --adapter ../adapters/ddgr-search)
  $ printf '%s\n' "$search_result" | \
  >   sed -E 's/hit_[0-9a-f]{32}/hit_ID/g'
  {"ok":true,"result":{"count":1,"hits":[{"hit":"hit_ID","url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}}
  $ hit=$(printf '%s\n' "$search_result" | jq -r '.result.hits[0].hit')

  $ MQ_TEST_LOG="$PWD/mq.log" PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug recon-test --directory-prefix workspaces \
  >   --adapter ../adapters/curl-pandoc-fetch "$hit" | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspaces/recon-test/artifacts/snapshots/snap_ID/document.md","document_media_type":"text/markdown"}}

  $ printf 'The primary result defines the topic boundary.' > observation.md
  $ sandwalk recon add-observation \
  >   --slug recon-test --directory-prefix workspaces \
  >   --text-file observation.md
  {"ok":true,"result":{"phase":"reconnaissance","observations":1}}

  $ printf 'Proceed with one narrow evidence step.' > summary.md
  $ sandwalk recon finish \
  >   --slug recon-test --directory-prefix workspaces \
  >   --summary-file summary.md
  {"ok":true,"result":{"phase":"planning","observations":1}}

  $ ./inspect_workspace.exe --inspect-recon workspaces/recon-test/database/sandwalk.sqlite3
  Map the small topic before planning.|Proceed with one narrow evidence step.|1
  1|The primary result defines the topic boundary.

Planning may reopen reconnaissance without discarding prior observations.

  $ printf 'Refine the source boundary before sealing.' > refined-goal.md
  $ sandwalk recon start \
  >   --slug recon-test --directory-prefix workspaces \
  >   --goal-file refined-goal.md
  {"ok":true,"result":{"phase":"reconnaissance","observations":1}}

  $ printf 'The refined boundary still needs one primary source.' > refined.md
  $ sandwalk recon add-observation \
  >   --slug recon-test --directory-prefix workspaces --text-file refined.md
  {"ok":true,"result":{"phase":"reconnaissance","observations":2}}

  $ printf 'Return to the existing plan with the refined boundary.' > refined-summary.md
  $ sandwalk recon finish \
  >   --slug recon-test --directory-prefix workspaces \
  >   --summary-file refined-summary.md
  {"ok":true,"result":{"phase":"planning","observations":2}}

  $ ./inspect_workspace.exe --inspect-recon workspaces/recon-test/database/sandwalk.sqlite3
  Refine the source boundary before sealing.|Return to the existing plan with the refined boundary.|1
  1|The primary result defines the topic boundary.
  2|The refined boundary still needs one primary source.

  $ sandwalk plan add-step \
  >   --slug recon-test --directory-prefix workspaces \
  >   --key narrow-evidence --title 'Collect narrow evidence'
  {"ok":true,"result":{"key":"narrow-evidence","title":"Collect narrow evidence","required":true,"position":1,"phase":"planning","plan_path":"workspaces/recon-test/exports/research-plan.md"}}
