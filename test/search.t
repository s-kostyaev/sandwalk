Create a released-schema v6 workspace with an active claim and search through v7.

  $ mkdir -p workspace/search-test/database workspace/search-test/logs \
  >   workspace/search-test/exports workspace/search-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v6 workspace/search-test/database/sandwalk.sqlite3 search-test

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query "small topic" --limit 1 \
  >   --adapter ../adapters/ddgr-search | \
  >   sed -E 's/hit_[0-9a-f]{32}/hit_ID/g'
  {"ok":true,"result":{"count":1,"hits":[{"hit":"hit_ID","url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}}

  $ ./inspect_workspace.exe --inspect-hits workspace/search-test/database/sandwalk.sqlite3
  36|1|https://example.test/primary|Primary result|A deterministic search result.

  $ mkdir -p "local documents"
  $ touch "local documents/Architecture Notes.pdf"
  $ local_search=$(PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query "adapter architecture" --limit 1 \
  >   --source-root "local documents" \
  >   --adapter ../adapters/ugrep-search)
  $ printf '%s\n' "$local_search" | \
  >   sed -E -e 's/hit_[0-9a-f]{32}/hit_ID/g' -e "s#file://$PWD#file://ROOT#"
  {"ok":true,"result":{"count":1,"hits":[{"hit":"hit_ID","url":"file://ROOT/local%20documents/Architecture%20Notes.pdf","title":"Architecture Notes.pdf","snippet":"Typed adapter architecture Adapter protocol details"}]}}

  $ local_hit=$(printf '%s' "$local_search" | jq -r '.result.hits[0].hit')
  $ local_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   "$local_hit")
  $ printf '%s\n' "$local_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/search-test/artifacts/snapshots/snap_ID/document.md","document_media_type":"text/markdown"}}

  $ local_document=$(printf '%s' "$local_fetch" | jq -r '.result.document_path')
  $ grep '^#' "$local_document"
  # Architecture Notes
  ## Adapter protocol

  $ test -s "$(dirname "$local_document")/document.json"

  $ mkdir -p info-fixture
  $ printf '%s\n' 'Fixture Info source.' > info-fixture/ellama.info
  $ info_search=$(TEXIQ_FAKE_SOURCE="$PWD/info-fixture/ellama.info" \
  >   PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query "blueprint" --limit 1 \
  >   --adapter ../adapters/texiq-search)
  $ printf '%s\n' "$info_search" | \
  >   jq -r '[.ok, .result.count, .result.hits[0].title, (.result.hits[0].url | startswith("info://texiq/"))] | @tsv'
  true	1	ellama — Blueprints and Community Prompts	true

  $ info_hit=$(printf '%s' "$info_search" | jq -r '.result.hits[0].hit')
  $ info_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   "$info_hit")
  $ printf '%s\n' "$info_fetch" | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/search-test/artifacts/snapshots/snap_ID/document.txt","document_media_type":"text/plain"}}

  $ info_document=$(printf '%s' "$info_fetch" | jq -r '.result.document_path')
  $ cat "$info_document"
  2.9 Blueprints and Community Prompts
  Blueprints are reusable prompt templates with variables.

  $ jq -r '[.adapter.name, .info.node, .artifacts.metadata] | @tsv' \
  >   "$(dirname "$info_document")/manifest.json"
  texiq	Blueprints and Community Prompts	node.json

  $ ./inspect_workspace.exe --inspect-search-roots workspace/search-test/database/sandwalk.sqlite3 | \
  >   sed "s#$PWD#ROOT#"
  ../adapters/ddgr-search|NULL
  ../adapters/ugrep-search|ROOT/local documents
  ../adapters/texiq-search|NULL

  $ ./inspect_workspace.exe workspace/search-test/database/sandwalk.sqlite3
  search-test|researching
  24
  wal
  ok

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --query "missing claim" --limit 1 \
  >   --adapter ../adapters/ddgr-search
  {"ok":false,"error":{"code":"SEARCH_REQUIRES_CLAIM","message":"Research search requires an active claim."},"next":"'sandwalk' 'next' '--slug' 'search-test' '--directory-prefix' 'workspace'"}
  [1]
