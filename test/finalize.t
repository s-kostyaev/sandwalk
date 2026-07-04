  $ mkdir -p workspace/final-test/database workspace/final-test/logs \
  >   workspace/final-test/exports
  $ ./inspect_workspace.exe --create-v14 workspace/final-test/database/sandwalk.sqlite3 final-test

  $ sandwalk finalize --slug final-test --directory-prefix workspace
  {"ok":true,"result":{"phase":"completed","report":"workspace/final-test/exports/report.md","sources":"workspace/final-test/exports/sources.md","source_count":1}}

The packet loop has an explicit terminal response.

  $ sandwalk continue --slug final-test --directory-prefix workspace
  {"ok":true,"result":{"packet":"workspace/final-test/artifacts/work/current.json","loop":"Edit only editable; keep integrity_md5 unchanged; apply the packet; then run continue again.","phase":"completed","action":"inspect-completed-workspace","reason":"The workflow is complete.","advisory":true,"alternatives_possible":true}}

  $ cat workspace/final-test/exports/report.md
  # Fixture
  
  Supported fixture. [1]

  $ cat workspace/final-test/exports/sources.md
  <!-- sandwalk-sources-v1 -->
  # Sources
  
  1. https://example.test/final

  $ ./inspect_workspace.exe --inspect-finalization workspace/final-test/database/sandwalk.sqlite3
  1|32|32|1

  $ ./inspect_workspace.exe workspace/final-test/database/sandwalk.sqlite3
  final-test|completed
  22
  wal
  ok

Identical durable state produces identical citation numbering and bibliography.

  $ mkdir -p workspace/final-copy/database workspace/final-copy/logs \
  >   workspace/final-copy/exports
  $ ./inspect_workspace.exe --create-v14 workspace/final-copy/database/sandwalk.sqlite3 final-copy
  $ sandwalk finalize --slug final-copy --directory-prefix workspace >/dev/null
  $ cmp workspace/final-test/exports/report.md workspace/final-copy/exports/report.md
  $ cmp workspace/final-test/exports/sources.md workspace/final-copy/exports/sources.md
