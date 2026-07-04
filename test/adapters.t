  $ PATH="$PWD/fakes:$PATH" ../adapters/ddgr-search <<'EOF'
  > {"protocol":"sandwalk.search.v1","query":"small topic","limit":1}
  > EOF
  {"protocol":"sandwalk.search-results.v1","adapter":{"name":"ddgr","protocol_version":1},"results":[{"url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}

An inherited nonexistent TMPDIR falls back to the system temporary directory.

  $ TMPDIR="$PWD/does-not-exist" PATH="$PWD/fakes:$PATH" \
  >   ../adapters/ddgr-search <<'EOF'
  > {"protocol":"sandwalk.search.v1","query":"small topic","limit":1}
  > EOF
  {"protocol":"sandwalk.search-results.v1","adapter":{"name":"ddgr","protocol_version":1},"results":[{"url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}

ddgr diagnostics with an empty result set are adapter failures.

  $ DDGR_FORCE_FAILURE=1 PATH="$PWD/fakes:$PATH" \
  >   ../adapters/ddgr-search >/dev/null <<'EOF'
  > {"protocol":"sandwalk.search.v1","query":"small topic","limit":1}
  > EOF
  network unavailable
  [69]

  $ mkdir fetch-output
  $ MQ_TEST_LOG="$PWD/mq.log" PATH="$PWD/fakes:$PATH" \
  >   ../adapters/curl-pandoc-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://example.test/start","output_directory":"fetch-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"fetch-output/manifest.json"}

  $ cat fetch-output/document.md
  # Fetched title
  
  Queryable body.

  $ cat mq.log
  fetch-output/document.md|.tree

  $ jq -c '{protocol, requested_url, final_url, redirect_count, http, queryability_check}' \
  >   fetch-output/manifest.json
  {"protocol":"sandwalk.fetch-manifest.v1","requested_url":"https://example.test/start","final_url":"https://example.test/final","redirect_count":1,"http":{"status":200,"content_type":"text/html","request_accept":"text/markdown, text/html;q=0.9","headers_artifact":"headers.txt"},"queryability_check":{"tool":"mq","query":".tree","ok":true}}

  $ jq -r '.adapter.extraction_profile' fetch-output/manifest.json
  html-to-gfm-no-raw-html-v1

Server-provided Markdown bypasses pandoc.

  $ mkdir markdown-output
  $ CURL_FAKE_MARKDOWN=1 PANDOC_FORCE_FAILURE=1 \
  >   MQ_TEST_LOG="$PWD/mq.log" PATH="$PWD/fakes:$PATH" \
  >   ../adapters/curl-pandoc-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://example.test/markdown","output_directory":"markdown-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"markdown-output/manifest.json"}

  $ cmp markdown-output/original markdown-output/document.md

  $ jq -r '[.http.content_type, .adapter.extraction_profile] | @tsv' \
  >   markdown-output/manifest.json
  text/markdown; charset=utf-8	server-markdown-direct-v1

The manifest is not published when mq cannot query the Markdown.

  $ mkdir rejected-output
  $ MQ_TEST_LOG="$PWD/mq.log" MQ_FORCE_FAILURE=1 PATH="$PWD/fakes:$PATH" \
  >   ../adapters/curl-pandoc-fetch >/dev/null <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://example.test/rejected","output_directory":"rejected-output"}
  > EOF
  [1]

  $ test ! -e rejected-output/manifest.json

Local discovery emits bounded file locators without consulting ~/.ugrep.

  $ mkdir -p "local documents"
  $ touch "local documents/Architecture Notes.pdf"
  $ PATH="$PWD/fakes:$PATH" ../adapters/ugrep-search <<EOF \
  > | sed "s#file://$PWD#file://ROOT#"
  > {"protocol":"sandwalk.search.v1","query":"adapter architecture","limit":1,"source_root":"$PWD/local documents"}
  > EOF
  {"protocol":"sandwalk.search-results.v1","adapter":{"name":"ugrep+","protocol_version":1,"search_profile":"fixed-string-recursive-sorted-v1"},"results":[{"url":"file://ROOT/local%20documents/Architecture%20Notes.pdf","title":"Architecture Notes.pdf","snippet":"Typed adapter architecture Adapter protocol details"}]}

Xberg fetch retains hierarchical Markdown and the structured source model.

  $ mkdir local-output
  $ PATH="$PWD/fakes:$PATH" ../adapters/xberg-fetch <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/Architecture%20Notes.pdf","source_root":"$PWD/local documents","output_directory":"local-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"local-output/manifest.json"}

  $ cat local-output/document.md
  # Architecture Notes
  
  ## Adapter protocol
  
  Typed adapter architecture.

  $ jq -r '[.artifacts.structure, .adapter.extraction_profile, .queryability_check.ok] | @tsv' \
  >   local-output/manifest.json
  document.json	markdown-hierarchy-tesseract-v1	true

  $ jq -r '.results[0].document.nodes[] | [.content.node_type, (.content.level // 0)] | @tsv' \
  >   local-output/document.json
  title	0
  heading	2
  paragraph	0

Flattening recognized subheadings fails before snapshot publication.

  $ mkdir flat-output
  $ XBERG_FLAT_MARKDOWN=1 PATH="$PWD/fakes:$PATH" \
  >   ../adapters/xberg-fetch >/dev/null <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/Architecture%20Notes.pdf","source_root":"$PWD/local documents","output_directory":"flat-output"}
  > EOF
  xberg flattened Markdown subheadings
  [65]

  $ test ! -e flat-output/manifest.json

Canonicalization prevents a file locator from escaping the authorized root.

  $ mkdir outside
  $ touch outside/secret.pdf
  $ PATH="$PWD/fakes:$PATH" ../adapters/xberg-fetch >/dev/null <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/outside/secret.pdf","source_root":"$PWD/local documents","output_directory":"escape-output"}
  > EOF
  local source resolves outside its authorized root
  [77]

  $ ln -s "$PWD/outside/secret.pdf" "local documents/linked-secret.pdf"
  $ PATH="$PWD/fakes:$PATH" ../adapters/xberg-fetch >/dev/null <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/linked-secret.pdf","source_root":"$PWD/local documents","output_directory":"symlink-output"}
  > EOF
  local source resolves outside its authorized root
  [77]
