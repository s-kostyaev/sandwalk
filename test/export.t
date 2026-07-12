  $ mkdir -p workspace/export-test/database workspace/export-test/logs \
  >   workspace/export-test/exports
  $ ./inspect_workspace.exe --create-v14 \
  >   workspace/export-test/database/sandwalk.sqlite3 export-test
  $ sandwalk finalize --slug export-test --directory-prefix workspace >/dev/null

The first export adapter renders the finalized report and bibliography as one
atomically published PDF.

  $ PANDOC_TEST_LOG="$PWD/pandoc-export.log" \
  > PANDOC_TEST_HEADER_LOG="$PWD/unicode-fonts.tex" PATH="$PWD/fakes:$PATH" \
  >   sandwalk export pdf \
  >   --slug export-test --directory-prefix workspace \
  >   --adapter ../adapters/pandoc-pdf-export | \
  >   sed -E 's/"md5":"[0-9a-f]{32}"/"md5":"MD5"/'
  {"ok":true,"result":{"format":"pdf","artifact":"workspace/export-test/exports/report.pdf","media_type":"application/pdf","md5":"MD5","size":25}}

  $ head -c 5 workspace/export-test/exports/report.pdf
  %PDF-

The bundled renderer uses XeLaTeX and installed Unicode fonts, so Cyrillic
report text is rendered rather than being dropped or causing the default PDF
engine to fail.

  $ grep -E -- '--lua-filter=.*citation-links.lua.*--pdf-engine=xelatex.*--include-in-header=.*unicode-fonts.tex.*--variable=colorlinks:true.*--variable=linkcolor:blue.*--variable=urlcolor:blue' pandoc-export.log >/dev/null
  $ grep -E '^\\setmainfont\{[^}]+\}\[Path=[^]]+/\]$' unicode-fonts.tex >/dev/null
  $ grep -E '^\\setsansfont\{[^}]+\}\[Path=[^]]+/\]$' unicode-fonts.tex >/dev/null
  $ grep -E '^\\setmonofont\{[^}]+\}\[Path=[^]]+/\]$' unicode-fonts.tex >/dev/null

The exporter request and manifest are versioned contracts.

  $ mkdir direct-export
  $ report_md5=$(md5 -q workspace/export-test/exports/report.md)
  $ sources_md5=$(md5 -q workspace/export-test/exports/sources.md)
  $ PATH="$PWD/fakes:$PATH" ../adapters/pandoc-pdf-export <<EOF
  > {"protocol":"sandwalk.export.v1","format":"pdf","inputs":[{"role":"report","path":"workspace/export-test/exports/report.md","md5":"$report_md5"},{"role":"bibliography","path":"workspace/export-test/exports/sources.md","md5":"$sources_md5"}],"output_directory":"direct-export"}
  > EOF
  {"protocol":"sandwalk.export-result.v1","manifest":"direct-export/manifest.json"}

  $ jq -c '{protocol, format, inputs, artifact}' direct-export/manifest.json | \
  >   sed -E 's/"md5":"[0-9a-f]{32}"/"md5":"MD5"/g'
  {"protocol":"sandwalk.export-manifest.v1","format":"pdf","inputs":[{"role":"report","md5":"MD5"},{"role":"bibliography","md5":"MD5"}],"artifact":{"path":"report.pdf","media_type":"application/pdf","md5":"MD5"}}

Only completed, untampered finalization outputs can be exported.

  $ mkdir -p workspace/incomplete/database workspace/incomplete/logs \
  >   workspace/incomplete/exports
  $ ./inspect_workspace.exe --create-v12 \
  >   workspace/incomplete/database/sandwalk.sqlite3 incomplete
  $ sandwalk export pdf --slug incomplete --directory-prefix workspace \
  >   --adapter ../adapters/pandoc-pdf-export
  {"ok":false,"error":{"code":"EXPORT_NOT_ALLOWED","message":"Export is not allowed while the workspace phase is drafting."}}
  [1]

  $ printf '\ntampered\n' >> workspace/export-test/exports/report.md
  $ PATH="$PWD/fakes:$PATH" sandwalk export pdf \
  >   --slug export-test --directory-prefix workspace \
  >   --adapter ../adapters/pandoc-pdf-export
  {"ok":false,"error":{"code":"EXPORT_INPUT_STALE","message":"Final report or bibliography differs from the finalized workspace."}}
  [1]
