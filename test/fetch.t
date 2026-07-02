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
  {"ok":true,"result":{"snapshot":"snap_ID","document_path":"workspace/fetch-test/artifacts/snapshots/snap_ID/document.md"}}

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
  8
  wal
  ok

Research fetches fail before invoking an adapter when no claim is supplied.

  $ PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug fetch-test --directory-prefix workspace \
  >   --adapter ../adapters/curl-pandoc-fetch \
  >   hit_00000000000000000000000000000001
  {"ok":false,"error":{"code":"FETCH_REQUIRES_CLAIM","message":"Research fetch requires an active claim."}}
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
