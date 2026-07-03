  $ mkdir -p workspace/report-test/database workspace/report-test/logs \
  >   workspace/report-test/exports
  $ ./inspect_workspace.exe --create-v12 workspace/report-test/database/sandwalk.sqlite3 report-test

Prose blocks require typed citations.

  $ printf '# Draft\n\nAn uncited assertion.\n' > uncited.md
  $ sandwalk draft submit \
  >   --slug report-test --directory-prefix workspace \
  >   --report-file uncited.md
  {"ok":false,"error":{"code":"REPORT_BLOCK_UNCITED","message":"Report block 2 has no citation."}}
  [1]

Citation targets must be current, reviewed, and accepted.

  $ printf '# Draft\n\nUnknown claim. [cite:fixture-step/missing]\n' > unknown.md
  $ sandwalk draft submit \
  >   --slug report-test --directory-prefix workspace \
  >   --report-file unknown.md
  {"ok":false,"error":{"code":"REPORT_CITATION_INVALID","message":"Citation target \"fixture-step/missing\" is unknown, stale, or rejected."}}
  [1]
  $ test ! -e workspace/report-test/exports/report.md

  $ printf '# Small Report\n\nThe fixture claim is supported. [cite:fixture-step/sealed-finding]\n' > report.md
  $ sandwalk draft submit \
  >   --slug report-test --directory-prefix workspace \
  >   --report-file report.md
  {"ok":true,"result":{"revision":1,"blocks":2,"review_blocks":[{"ordinal":1,"block_md5":"503410e60bdf3d6f82d795c3003fdc23"},{"ordinal":2,"block_md5":"8cc434085ae5bb936317a724b26a081c"}],"phase":"draft-review","report":"workspace/report-test/exports/report.md"}}

  $ cat workspace/report-test/exports/report.md
  # Small Report
  
  The fixture claim is supported. [cite:fixture-step/sealed-finding]

  $ ./inspect_workspace.exe --inspect-reports workspace/report-test/database/sandwalk.sqlite3
  1|32|83|1
  1|1|32|[]
  1|2|32|["fixture-step/sealed-finding"]

  $ ./inspect_workspace.exe workspace/report-test/database/sandwalk.sqlite3
  report-test|draft-review
  21
  wal
  ok
