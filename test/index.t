Build a reusable semantic index through the public command. Plain text and a
rich document go through the same existing fetch-normalization boundary.

  $ chmod +x fakes/* ../adapters/qmd-index ../adapters/qmd-search ../adapters/qmd-fetch
  $ mkdir -p document-source
  $ printf '%s\n' 'Local semantic retrieval keeps exact evidence separate.' > document-source/manual.txt
  $ printf '%s\n' '%PDF fixture' > 'document-source/Architecture Notes.pdf'
  $ PATH="$PWD/fakes:$PATH" sandwalk index build \
  >   --source-root document-source \
  >   --index-directory document-index \
  >   --adapter ../adapters/qmd-index | \
  >   sed -E -e "s#$PWD#ROOT#g" -e 's/[0-9a-f]{32}/INDEX_ID/g'
  {"ok":true,"result":{"index_directory":"ROOT/document-index","index_id":"INDEX_ID","entries":2,"skipped":0,"embedding_model":"hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"}}

  $ jq -r '[.protocol, .ingest.mode, .backend.implementation_version, .backend.search_mode, (.entries | length), (.skipped | length), ([.entries[].document_media_type] | sort | join(","))] | @tsv' document-index/manifest.json
  sandwalk.semantic-index.v1	documents	qmd 2.5.3-test	structured-vec-no-rerank	2	0	text/markdown,text/plain
  $ test -s document-index/.qmd/index.sqlite
  $ test "$(find document-index/corpus -name '*.md' | wc -l | tr -d ' ')" = 2

The index directory cannot be nested under its own input corpus, and an
unrelated existing directory is never replaced.

  $ PATH="$PWD/fakes:$PATH" sandwalk index build \
  >   --source-root document-source --index-directory document-source/index \
  >   --adapter ../adapters/qmd-index
  {"ok":false,"error":{"code":"INDEX_ADAPTER_FAILED","message":"Semantic index adapter failed."}}
  [1]

  $ mkdir unrelated
  $ PATH="$PWD/fakes:$PATH" sandwalk index build \
  >   --source-root document-source --index-directory unrelated \
  >   --adapter ../adapters/qmd-index
  {"ok":false,"error":{"code":"INDEX_ADAPTER_FAILED","message":"Semantic index adapter failed."}}
  [1]

Semantic search persists the authorized index root. Fetch resolves the QMD hit
back to the exact normalized source and publishes original source provenance.

  $ mkdir -p workspace/qmd-test/database workspace/qmd-test/logs \
  >   workspace/qmd-test/exports workspace/qmd-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v6 workspace/qmd-test/database/sandwalk.sqlite3 qmd-test
  $ semantic_search=$(QMD_FAKE_MATCH=manual.txt PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug qmd-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query 'semantic evidence' --limit 1 \
  >   --source-index document-index \
  >   --adapter ../adapters/qmd-search)
  $ printf '%s\n' "$semantic_search" | jq -r '[.ok, .result.count, (.result.hits[0].url | startswith("qmd://")), .result.hits[0].title] | @tsv'
  true	1	true	manual.txt

  $ semantic_hit=$(printf '%s' "$semantic_search" | jq -r '.result.hits[0].hit')
  $ semantic_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug qmd-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   "$semantic_hit")
  $ printf '%s\n' "$semantic_fetch" | sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/qmd-test/artifacts/snapshots/snap_ID/document.txt","document_media_type":"text/plain"}}
  $ semantic_document=$(printf '%s' "$semantic_fetch" | jq -r '.result.document_path')
  $ cat "$semantic_document"
  Local semantic retrieval keeps exact evidence separate.
  $ jq -r '[.adapter.name, (.final_url | startswith("file://")), .document_media_type] | @tsv' "$(dirname "$semantic_document")/manifest.json"
  qmd-index	true	text/plain
  $ ./inspect_workspace.exe --inspect-search-roots workspace/qmd-test/database/sandwalk.sqlite3 | sed "s#$PWD#ROOT#"
  ../adapters/qmd-search|ROOT/document-index

The same verified fetch path retains rich-document structure needed by the
snapshot queryability contract.

  $ rich_id=$(jq -r '.entries[] | select(.title == "Architecture Notes.pdf") | .id' document-index/manifest.json)
  $ index_id=$(jq -r '.index_id' document-index/manifest.json)
  $ mkdir rich-output
  $ ../adapters/qmd-fetch >/dev/null <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"qmd://$index_id/$rich_id","source_root":"$PWD/document-index","output_directory":"rich-output"}
  > EOF
  $ jq -r '[.document_media_type, .artifacts.document, .artifacts.structure, .queryability_check.ok] | @tsv' rich-output/manifest.json
  text/markdown	document.md	document.json	true
  $ test -s rich-output/document.json

A source mutation makes the discovery cache stale and blocks direct fetch.

  $ semantic_url=$(printf '%s' "$semantic_search" | jq -r '.result.hits[0].url')
  $ printf '%s\n' 'Changed after indexing.' > document-source/manual.txt
  $ mkdir stale-output
  $ ../adapters/qmd-fetch >/dev/null <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"$semantic_url","source_root":"$PWD/document-index","output_directory":"stale-output"}
  > EOF
  semantic index is stale; rebuild it before fetching
  [75]
  $ test ! -e stale-output/manifest.json

  $ sandwalk search --slug qmd-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 --query conflict \
  >   --source-root document-source --source-index document-index
  {"ok":false,"error":{"code":"INVALID_SEARCH_SOURCE","message":"--source-root and --source-index are mutually exclusive."}}
  [1]

Info ingest creates one searchable document per exact texiq node while keeping
the evidence locator in the Info namespace.

  $ mkdir info-fixture
  $ printf '%s\n' 'Fixture Info source.' > info-fixture/ellama.info
  $ TEXIQ_FAKE_SOURCE="$PWD/info-fixture/ellama.info" PATH="$PWD/fakes:$PATH" \
  >   sandwalk index build --info-manual ellama --emacs \
  >   --index-directory info-index --adapter ../adapters/qmd-index | \
  >   sed -E -e "s#$PWD#ROOT#g" -e 's/[0-9a-f]{32}/INDEX_ID/g'
  {"ok":true,"result":{"index_directory":"ROOT/info-index","index_id":"INDEX_ID","entries":1,"skipped":0,"embedding_model":"hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"}}
  $ jq -r '[.ingest.mode, .entries[0].title, (.entries[0].source_locator | startswith("info://texiq/")), .entries[0].document_media_type] | @tsv' info-index/manifest.json
  info	ellama — Blueprints and Community Prompts	true	text/plain
