  $ mkdir -p workspace/gc-test/database workspace/gc-test/logs \
  >   workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001
  $ ./inspect_workspace.exe --create-v17 workspace/gc-test/database/sandwalk.sqlite3 gc-test
  $ printf '<html>raw</html>' > workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001/original
  $ printf 'Normalized Markdown.\n' > workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001/document.md

  $ sandwalk gc --slug gc-test --directory-prefix workspace --raw --plan
  {"ok":true,"result":{"mode":"plan","count":1,"plan_path":"workspace/gc-test/artifacts/gc-raw-plan.json"}}

  $ cat workspace/gc-test/artifacts/gc-raw-plan.json
  {"protocol":"sandwalk.gc-raw-plan.v1","artifacts":["workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001/original"]}

Plans are hash-bound and cannot be edited before apply.

  $ printf ' ' >> workspace/gc-test/artifacts/gc-raw-plan.json
  $ sandwalk gc --slug gc-test --directory-prefix workspace --raw --apply
  {"ok":false,"error":{"code":"GC_PLAN_STALE","message":"Raw cleanup plan is stale or modified."}}
  [1]

  $ sandwalk gc --slug gc-test --directory-prefix workspace --raw --plan >/dev/null
  $ sandwalk gc --slug gc-test --directory-prefix workspace --raw --apply
  {"ok":true,"result":{"mode":"apply","count":1,"plan_path":"workspace/gc-test/artifacts/gc-raw-plan.json"}}

  $ test ! -e workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001/original
  $ cat workspace/gc-test/artifacts/snapshots/snap_00000000000000000000000000000001/document.md
  Normalized Markdown.

  $ ./inspect_workspace.exe workspace/gc-test/database/sandwalk.sqlite3
  gc-test|completed
  19
  wal
  ok

  $ sandwalk gc --slug gc-test --directory-prefix workspace --raw --apply
  {"ok":false,"error":{"code":"GC_NO_PLAN","message":"No unapplied raw cleanup plan exists."}}
  [1]

Active research claims block cleanup planning.

  $ mkdir -p active/active-gc/database active/active-gc/logs
  $ ./inspect_workspace.exe --create-v7 active/active-gc/database/sandwalk.sqlite3 active-gc
  $ sandwalk gc --slug active-gc --directory-prefix active --raw --plan
  {"ok":false,"error":{"code":"GC_ACTIVE_CLAIMS","message":"Raw cleanup is blocked while claims are active."}}
  [1]
