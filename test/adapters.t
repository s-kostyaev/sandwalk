  $ PATH="$PWD/fakes:$PATH" ../adapters/ddgr-search <<'EOF'
  > {"protocol":"sandwalk.search.v1","query":"small topic","limit":1}
  > EOF
  {"protocol":"sandwalk.search-results.v1","adapter":{"name":"ddgr","protocol_version":1},"results":[{"url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}

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
  {"protocol":"sandwalk.fetch-manifest.v1","requested_url":"https://example.test/start","final_url":"https://example.test/final","redirect_count":1,"http":{"status":200,"content_type":"text/html","headers_artifact":"headers.txt"},"queryability_check":{"tool":"mq","query":".tree","ok":true}}

The manifest is not published when mq cannot query the Markdown.

  $ mkdir rejected-output
  $ MQ_TEST_LOG="$PWD/mq.log" MQ_FORCE_FAILURE=1 PATH="$PWD/fakes:$PATH" \
  >   ../adapters/curl-pandoc-fetch >/dev/null <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://example.test/rejected","output_directory":"rejected-output"}
  > EOF
  [1]

  $ test ! -e rejected-output/manifest.json
