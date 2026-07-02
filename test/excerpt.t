Create a released-schema v8 workspace with one immutable snapshot.

  $ mkdir -p workspace/excerpt-test/database workspace/excerpt-test/logs \
  >   workspace/excerpt-test/exports workspace/excerpt-test/artifacts/temporary \
  >   workspace/excerpt-test/artifacts/excerpts \
  >   workspace/excerpt-test/artifacts/snapshots/snap_00000000000000000000000000000001
  $ ./inspect_workspace.exe --create-v8 workspace/excerpt-test/database/sandwalk.sqlite3 excerpt-test
  $ printf '# Fetched title\n\nQueryable body.\nRepeated.\nQueryable body.\n' \
  >   > workspace/excerpt-test/artifacts/snapshots/snap_00000000000000000000000000000001/document.md

Inclusive line selection preserves the exact source bytes.

  $ sandwalk excerpt create \
  >   --slug excerpt-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot snap_00000000000000000000000000000001 \
  >   --lines 3:3 | sed -E 's/excerpt_[0-9a-f]{32}/excerpt_ID/g'
  {"ok":true,"result":{"excerpt":"excerpt_ID","created":true,"lines":"3:3","bytes":"17:33"}}

  $ cat workspace/excerpt-test/artifacts/excerpts/excerpt_*.md
  Queryable body.

Creating the same range is idempotent.

  $ sandwalk excerpt create \
  >   --slug excerpt-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot snap_00000000000000000000000000000001 \
  >   --lines 3:3 | sed -E 's/excerpt_[0-9a-f]{32}/excerpt_ID/g'
  {"ok":true,"result":{"excerpt":"excerpt_ID","created":false,"lines":"3:3","bytes":"17:33"}}

Ambiguous exact text requires a one-based occurrence.

  $ printf 'Queryable body.' > selected.txt
  $ sandwalk excerpt create \
  >   --slug excerpt-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot snap_00000000000000000000000000000001 \
  >   --text-file selected.txt
  {"ok":false,"error":{"code":"AMBIGUOUS_EXCERPT_TEXT","message":"Excerpt text occurs 2 times; specify --occurrence."}}
  [1]

  $ sandwalk excerpt create \
  >   --slug excerpt-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot snap_00000000000000000000000000000001 \
  >   --text-file selected.txt --occurrence 2 | \
  >   sed -E 's/excerpt_[0-9a-f]{32}/excerpt_ID/g'
  {"ok":true,"result":{"excerpt":"excerpt_ID","created":true,"lines":"5:5","bytes":"43:58"}}

  $ ./inspect_workspace.exe --inspect-excerpts workspace/excerpt-test/database/sandwalk.sqlite3
  40|snap_00000000000000000000000000000001|3|3|17|33|32|16
  40|snap_00000000000000000000000000000001|5|5|43|58|32|15

  $ ./inspect_workspace.exe workspace/excerpt-test/database/sandwalk.sqlite3
  excerpt-test|researching
  15
  wal
  ok

Research excerpt creation requires the snapshot-owning claim.

  $ sandwalk excerpt create \
  >   --slug excerpt-test --directory-prefix workspace \
  >   --snapshot snap_00000000000000000000000000000001 \
  >   --lines 4:4
  {"ok":false,"error":{"code":"EXCERPT_REQUIRES_CLAIM","message":"Research excerpt creation requires an active claim."}}
  [1]

  $ find workspace/excerpt-test/artifacts/excerpts -type f | wc -l | tr -d ' '
  2
