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
  {"protocol":"sandwalk.fetch-manifest.v1","requested_url":"https://example.test/start","final_url":"https://example.test/final","redirect_count":1,"http":{"status":200,"content_type":"text/html","request_accept":"text/markdown, text/html;q=0.9, application/pdf;q=0.8","headers_artifact":"headers.txt"},"queryability_check":{"tool":"mq","query":".tree","ok":true}}

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

YouTube snapshots use source-provided chapters as Markdown structure.

  $ mkdir youtube-chapters-output
  $ PATH="$PWD/fakes:$PATH" ../adapters/youtube-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://www.youtube.com/watch?v=chapter-test","output_directory":"youtube-chapters-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"youtube-chapters-output/manifest.json"}

  $ jq -r '[.artifacts.document, .document_media_type, .youtube.caption_kind, .youtube.chapter_count, .queryability_check.tool] | @tsv' \
  >   youtube-chapters-output/manifest.json
  document.md	text/markdown	manual	2	mq

  $ grep '^## ' youtube-chapters-output/document.md
  ## [00:00] Introduction
  ## [01:00] Main result

  $ grep -F 'youtube.com/watch?v=chapter-test&t=70s' \
  >   youtube-chapters-output/document.md
  [01:10](https://www.youtube.com/watch?v=chapter-test&t=70s) The main result follows. The conclusion is bounded.

Without source chapters the same constructor publishes plain text and no
Markdown alias.

  $ mkdir youtube-flat-output
  $ PATH="$PWD/fakes:$PATH" ../adapters/youtube-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://youtu.be/flat-test","output_directory":"youtube-flat-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"youtube-flat-output/manifest.json"}

  $ jq -r '[.artifacts.document, .document_media_type, .youtube.caption_kind, .youtube.chapter_count, .queryability_check.tool] | @tsv' \
  >   youtube-flat-output/manifest.json
  transcript.txt	text/plain	automatic	0	rg

  $ find youtube-flat-output -maxdepth 1 -type f -exec basename {} \; | sort
  blocks.jsonl
  captions.json3
  manifest.json
  metadata.json
  transcript.txt

  $ grep '^#' youtube-flat-output/transcript.txt
  [1]

Remote PDFs are normalized by the same pinned Docling profile as local PDFs.

  $ mkdir remote-pdf-output
  $ CURL_FAKE_PDF=1 DOCLING_TEST_LOG="$PWD/remote-docling.log" \
  >   PATH="$PWD/fakes:$PATH" ../adapters/curl-pandoc-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://example.test/paper.pdf","output_directory":"remote-pdf-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"remote-pdf-output/manifest.json"}

  $ jq -r '[.adapter.name, .adapter.extraction_profile, .artifacts.structure, .http.content_type] | @tsv' \
  >   remote-pdf-output/manifest.json
  curl-docling	standard-native-hierarchy-bookmark-095-v2	document.json	application/pdf

  $ cat remote-pdf-output/document.md
  # Architecture Notes
  
  ## Adapter protocol
  
  Typed adapter architecture.

arXiv keeps the exact-version PDF for readers while normalizing the article
container from HTML.

  $ mkdir arxiv-output
  $ CURL_FAKE_ARXIV=1 CURL_TEST_LOG="$PWD/arxiv-curl.log" \
  >   PATH="$PWD/fakes:$PATH" ../adapters/curl-pandoc-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://arxiv.org/abs/2402.07630","output_directory":"arxiv-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"arxiv-output/manifest.json"}

  $ jq -r '[.adapter.name, .final_url, .arxiv.normalization_source, .artifacts.pdf] | @tsv' \
  >   arxiv-output/manifest.json
  arxiv-html	https://arxiv.org/abs/2402.07630v3	html	source.pdf

  $ file arxiv-output/source.pdf | sed 's/.*: //'
  PDF document, version 1.7

  $ cat arxiv-curl.log
  https://arxiv.org/html/2402.07630|text/html
  https://arxiv.org/pdf/2402.07630v3|application/pdf

An unavailable or structurally rejected arXiv HTML representation falls back
to the already downloaded PDF without losing it as a reader artifact.

  $ mkdir arxiv-fallback-output
  $ CURL_FAKE_ARXIV=1 CURL_FAKE_ARXIV_HTML_FAILURE=1 \
  >   PATH="$PWD/fakes:$PATH" ../adapters/curl-pandoc-fetch <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://arxiv.org/abs/2402.07630v3","output_directory":"arxiv-fallback-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"arxiv-fallback-output/manifest.json"}

  $ jq -r '[.adapter.name, .arxiv.normalization_source, .arxiv.fallback_reason, .artifacts.pdf] | @tsv' \
  >   arxiv-fallback-output/manifest.json
  arxiv-pdf-docling	pdf	html-unavailable-or-quality-gate	source.pdf

  $ test -s arxiv-fallback-output/source.pdf
  $ test ! -e arxiv-fallback-output/original

The reader PDF is mandatory; a partial HTML-only snapshot is never published.

  $ mkdir arxiv-missing-pdf-output
  $ CURL_FAKE_ARXIV=1 CURL_FAKE_ARXIV_PDF_FAILURE=1 \
  >   PATH="$PWD/fakes:$PATH" ../adapters/curl-pandoc-fetch >/dev/null <<'EOF'
  > {"protocol":"sandwalk.fetch.v1","url":"https://arxiv.org/abs/2402.07630v3","output_directory":"arxiv-missing-pdf-output"}
  > EOF
  arXiv PDF unavailable
  [22]

  $ test ! -e arxiv-missing-pdf-output/manifest.json

Local discovery emits bounded file locators without consulting ~/.ugrep.

  $ mkdir -p "local documents"
  $ touch "local documents/Architecture Notes.pdf"
  $ PATH="$PWD/fakes:$PATH" ../adapters/ugrep-search <<EOF \
  > | sed "s#file://$PWD#file://ROOT#"
  > {"protocol":"sandwalk.search.v1","query":"adapter architecture","limit":1,"source_root":"$PWD/local documents"}
  > EOF
  {"protocol":"sandwalk.search-results.v1","adapter":{"name":"ugrep+","protocol_version":1,"search_profile":"fixed-string-recursive-sorted-v1"},"results":[{"url":"file://ROOT/local%20documents/Architecture%20Notes.pdf","title":"Architecture Notes.pdf","snippet":"Typed adapter architecture Adapter protocol details"}]}

Local file fetch preserves ordinary source text as a plain-text primary
artifact, even when the file is not named *.txt.

  $ cat > "local documents/source.el" <<'EOF'
  > (defun sandwalk-example ()
  >   "Plain source evidence."
  >   t)
  > EOF
  $ PATH="$PWD/fakes:$PATH" ../adapters/file-fetch <<EOF \
  > | sed "s#file://$PWD#file://ROOT#"
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/source.el","source_root":"$PWD/local documents","output_directory":"file-text-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"file-text-output/manifest.json"}

  $ jq -r '[.adapter.name, .adapter.extraction_profile, .artifacts.document, .document_media_type, .queryability_check.tool] | @tsv' \
  >   file-text-output/manifest.json
  file-text	plain-text-mime-v1	document.txt	text/plain	rg

  $ cat file-text-output/document.txt
  (defun sandwalk-example ()
    "Plain source evidence."
    t)

Rich local document formats are delegated to Docling before plain-text
classification, so ASCII-looking RTF is not treated as source text.

  $ printf '{\\rtf1\\ansi Rich text evidence.}\n' > "local documents/Rich.rtf"
  $ PATH="$PWD/fakes:$PATH" ../adapters/file-fetch <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/Rich.rtf","source_root":"$PWD/local documents","output_directory":"file-rich-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"file-rich-output/manifest.json"}

  $ jq -r '[.adapter.name, .artifacts.document, .document_media_type, .queryability_check.tool] | @tsv' \
  >   file-rich-output/manifest.json
  docling	document.md	text/markdown	mq

Docling fetch uses the pinned non-LLM hierarchy profile and retains quality
metrics alongside the structured source model.

  $ mkdir docling-output
  $ DOCLING_TEST_LOG="$PWD/docling.log" PATH="$PWD/fakes:$PATH" \
  >   ../adapters/docling-fetch <<EOF
  > {"protocol":"sandwalk.fetch.v1","url":"file://$PWD/local%20documents/Architecture%20Notes.pdf","source_root":"$PWD/local documents","output_directory":"docling-output"}
  > EOF
  {"protocol":"sandwalk.fetch-result.v1","manifest":"docling-output/manifest.json"}

  $ cat docling-output/document.md
  # Architecture Notes
  
  ## Adapter protocol
  
  Typed adapter architecture.

  $ jq -r '[.artifacts.structure, .artifacts.quality, .adapter.extraction_profile, .queryability_check.ok] | @tsv' \
  >   docling-output/manifest.json
  document.json	quality.json	standard-native-hierarchy-bookmark-095-v2	true

  $ jq -r '[.heading_count, .top_level_bookmarks.coverage, (.warnings | length)] | @tsv' \
  >   docling-output/quality.json
  2	1.0	0

Normalization reads the retained extension-preserving original directly, and
the explicit profile is removed.

  $ sed "s#$PWD#ROOT#g" docling.log
  docling-output/original/Architecture Notes.pdf|docling-output/docling-profile.json

  $ test -f "docling-output/original/Architecture Notes.pdf"
  $ test ! -e docling-output/docling-profile.json

Xberg remains an explicit fast adapter and retains its structured source model.

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

  $ jq -r '.result.document.nodes[] | [.content.node_type, (.content.level // 0)] | @tsv' \
  >   local-output/document.json
  title	0
  heading	2
  paragraph	0

  $ test ! -e "local-output/input-Architecture Notes.pdf"

Retained source artifacts are independent files, not hardlink aliases.

  $ find docling-output local-output remote-pdf-output arxiv-fallback-output \
  >   -type f -links +1 -print

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
