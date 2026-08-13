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

Web search defaults to the managed SearXNG connector without exposing service
lifecycle commands to the research workflow.

  $ PATH="$PWD/fakes:$PATH" SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/searx-state" \
  > sandwalk search --slug search-test --directory-prefix workspace \
  > --claim claim_00000000000000000000000000000001 \
  > --query "default metasearch" --limit 1 | \
  > sed -E 's/hit_[0-9a-f]{32}/hit_ID/g'
  {"ok":true,"result":{"count":1,"hits":[{"hit":"hit_ID","url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}}

  $ ./inspect_workspace.exe --inspect-search-roots workspace/search-test/database/sandwalk.sqlite3 | \
  >   sed "s#$PWD#ROOT#"
  ../adapters/ddgr-search|NULL
  ../adapters/ugrep-search|ROOT/local documents
  ../adapters/texiq-search|NULL
  sandwalk-search-searxng|NULL

  $ ./inspect_workspace.exe --inspect-search-metadata workspace/search-test/database/sandwalk.sqlite3
  {"name":"ddgr","protocol_version":1}
  {"name":"ugrep+","protocol_version":1,"search_profile":"fixed-string-recursive-sorted-v1"}
  {"name":"texiq","protocol_version":1,"search_profile":"emacs-info-node-search-v1"}
  {"name":"searxng","protocol_version":1,"search_profile":"research-v1","mode":"managed","image_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","config_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","endpoint_origin":"http://127.0.0.1:18888"}

Credential-bearing or otherwise non-origin adapter metadata is rejected before
the query is recorded.

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query "unsafe provenance" --limit 1 \
  >   --adapter "$PWD/fakes/sandwalk-search-invalid-metadata"
  {"ok":false,"error":{"code":"SEARCH_PROTOCOL_ERROR","message":"Search adapter returned an invalid response."}}
  [1]
  $ sqlite3 workspace/search-test/database/sandwalk.sqlite3 \
  >   'SELECT COUNT(*) FROM search_queries;'
  4

  $ ./inspect_workspace.exe workspace/search-test/database/sandwalk.sqlite3
  search-test|researching
  26
  wal
  ok

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --query "missing claim" --limit 1 \
  >   --adapter ../adapters/ddgr-search
  {"ok":false,"error":{"code":"SEARCH_REQUIRES_CLAIM","message":"Research search requires an active claim."},"next":"'sandwalk' 'next' '--slug' 'search-test' '--directory-prefix' 'workspace'"}
  [1]

The released v24 schema migrates existing search rows to bounded empty adapter
metadata before recording sanitized metadata for new searches.

  $ mkdir -p legacy-v24/database legacy-v24/logs legacy-v24/exports \
  >   legacy-v24/artifacts/temporary legacy-v24/artifacts/work \
  >   legacy-v24/artifacts/resume
  $ ./inspect_workspace.exe --create-v24 \
  >   legacy-v24/database/sandwalk.sqlite3 legacy-v24
  $ sandwalk resume --slug legacy-v24 --directory-prefix . >/dev/null
  $ ./inspect_workspace.exe --inspect-search-metadata \
  >   legacy-v24/database/sandwalk.sqlite3
  {}
  {}
  $ ./inspect_workspace.exe legacy-v24/database/sandwalk.sqlite3 | sed -n '2p'
  26
