Create a released-schema v7 workspace with an owned hit and fetch through v8.

  $ mkdir -p workspace/fetch-test/database workspace/fetch-test/logs \
  >   workspace/fetch-test/exports workspace/fetch-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v7 workspace/fetch-test/database/sandwalk.sqlite3 fetch-test

  $ MQ_TEST_LOG="$PWD/mq.log" PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter ../adapters/curl-pandoc-fetch \
  >   hit_00000000000000000000000000000001 | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/document.md","document_media_type":"text/markdown"}}

  $ cat workspace/fetch-test/artifacts/snapshots/snap_*/document.md
  # Fetched title
  
  Queryable body.

  $ sed -E 's#/temporary/fetch-[^/]+#/temporary/fetch_INV#' mq.log
  workspace/fetch-test/artifacts/temporary/fetch_INV/document.md|.tree

  $ ./inspect_workspace.exe --inspect-snapshots workspace/fetch-test/database/sandwalk.sqlite3 | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  37|hit_00000000000000000000000000000001|https://example.test/final|64|64|workspace/fetch-test/artifacts/snapshots/snap_ID

  $ ./inspect_workspace.exe workspace/fetch-test/database/sandwalk.sqlite3
  fetch-test|researching
  26
  wal
  ok

Plain-text snapshots preserve their declared primary artifact without a
Markdown alias.

  $ text_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter "$PWD/fakes/sandwalk-fetch-text" \
  >   hit_00000000000000000000000000000001)
  $ printf '%s\n' "$text_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/transcript.txt","document_media_type":"text/plain"}}

  $ text_snapshot=$(dirname "$(printf '%s' "$text_fetch" | jq -r '.result.document_path')")
  $ find "$text_snapshot" -maxdepth 1 -type f -exec basename {} \; | sort
  manifest.json
  transcript.txt

  $ text_snapshot_id=$(printf '%s' "$text_fetch" | jq -r '.result.snapshot')
  $ sandwalk excerpt create \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$text_snapshot_id" --lines 2:2 | \
  >   sed -E 's/excerpt_[0-9a-f]{32}/excerpt_ID/g'
  {"ok":true,"result":{"excerpt":"excerpt_ID","created":true,"lines":"2:2","bytes":"25:60"}}

  $ cat workspace/fetch-test/artifacts/excerpts/excerpt_*.md
  [00:42] Exact plain-text evidence.

YouTube locators select the site adapter by default and persist its genuine
plain-text primary artifact.

  $ sqlite3 workspace/fetch-test/database/sandwalk.sqlite3 \
  >   "INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet) VALUES ('hit_00000000000000000000000000000004', 1, 2, 'https://youtu.be/flat-test', 'Fixture video', 'Fixture video snippet.');"
  $ youtube_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   hit_00000000000000000000000000000004)
  $ printf '%s\n' "$youtube_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/transcript.txt","document_media_type":"text/plain"}}

Local file locators select the bundled file dispatcher by default. Ordinary
source text is preserved as text/plain without going through Docling.

  $ mkdir -p plain-source
  $ cat > plain-source/module.el <<'EOF'
  > (defun fixture ()
  >   "Default local text fetch."
  >   t)
  > EOF
  $ sqlite3 workspace/fetch-test/database/sandwalk.sqlite3 \
  >   "INSERT INTO search_queries (query, phase, claim_id, step_key, adapter, source_root, created_at) VALUES ('plain source', 'researching', 'claim_00000000000000000000000000000001', 'fixture-step', 'fixture-search', '$PWD/plain-source', '2026-01-01 00:00:00Z'); INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet) VALUES ('hit_00000000000000000000000000000005', last_insert_rowid(), 1, 'file://$PWD/plain-source/module.el', 'module.el', 'Default local text fetch.');"
  $ file_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   hit_00000000000000000000000000000005)
  $ printf '%s\n' "$file_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/document.el","document_media_type":"text/plain"}}

  $ file_snapshot=$(dirname "$(printf '%s' "$file_fetch" | jq -r '.result.document_path')")
  $ jq -r '[.adapter.name, .artifacts.document, .document_media_type] | @tsv' \
  >   "$file_snapshot/manifest.json"
  file-text	document.el	text/plain

Ordinary remote locators select the bounded web dispatcher by default, which
can publish a Playwright fallback through the unchanged snapshot protocol.

  $ sqlite3 workspace/fetch-test/database/sandwalk.sqlite3 \
  >   "INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet) VALUES ('hit_00000000000000000000000000000006', 1, 3, 'https://example.test/challenge', 'Dynamic fixture', 'Dynamic fixture snippet.');"
  $ browser_fetch=$(CURL_FAKE_CHALLENGE=1 PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   hit_00000000000000000000000000000006)
  $ printf '%s\n' "$browser_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/document.md","document_media_type":"text/markdown"}}

  $ browser_snapshot=$(dirname "$(printf '%s' "$browser_fetch" | jq -r '.result.document_path')")
  $ jq -r '[.adapter.name, .fallback.reason] | @tsv' "$browser_snapshot/manifest.json"
  playwright	bot-challenge

Research fetches fail before invoking an adapter when no claim is supplied.

  $ PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --adapter ../adapters/curl-pandoc-fetch \
  >   hit_00000000000000000000000000000001
  {"ok":false,"error":{"code":"FETCH_REQUIRES_CLAIM","message":"Research fetch requires an active claim."},"next":"'sandwalk' 'next' '--slug' 'fetch-test' '--directory-prefix' 'workspace'"}
  [1]

An active claim cannot persist a snapshot for another step's hit.

  $ MQ_TEST_LOG="$PWD/mq-other.log" PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter ../adapters/curl-pandoc-fetch \
  >   hit_00000000000000000000000000000002
  {"ok":false,"error":{"code":"HIT_NOT_OWNED_BY_CLAIM","message":"Search hit \"hit_00000000000000000000000000000002\" belongs to another research step."}}
  [1]

Hits must belong to the workspace.

  $ PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter ../adapters/curl-pandoc-fetch \
  >   hit_00000000000000000000000000000003
  {"ok":false,"error":{"code":"HIT_NOT_FOUND","message":"Search hit \"hit_00000000000000000000000000000003\" does not exist."}}
  [1]
