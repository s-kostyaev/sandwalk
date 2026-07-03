  $ sandwalk init --slug promotion-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"promotion-test","phase":"initialized","schema_version":22}}
  $ printf 'Find one reusable source.' > goal.md
  $ sandwalk recon start --slug promotion-test --directory-prefix workspaces \
  >   --goal-file goal.md >/dev/null

  $ search=$(PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug promotion-test --directory-prefix workspaces \
  >   --query 'reusable source' --limit 1 --adapter ../adapters/ddgr-search)
  $ hit=$(printf '%s\n' "$search" | jq -r '.result.hits[0].hit')
  $ fetched=$(MQ_TEST_LOG="$PWD/mq.log" PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug promotion-test --directory-prefix workspaces \
  >   --adapter ../adapters/curl-pandoc-fetch "$hit")
  $ snapshot=$(printf '%s\n' "$fetched" | jq -r '.result.snapshot')

  $ printf 'Use the reconnaissance source in the evidence plan.' > summary.md
  $ sandwalk recon finish --slug promotion-test --directory-prefix workspaces \
  >   --summary-file summary.md >/dev/null
  $ sandwalk plan add-step --slug promotion-test --directory-prefix workspaces \
  >   --key evidence --title 'Extract exact evidence' >/dev/null
  $ sandwalk plan add-step --slug promotion-test --directory-prefix workspaces \
  >   --key alternative --title 'Check alternative interpretation' >/dev/null
  $ sandwalk plan validate --slug promotion-test --directory-prefix workspaces >/dev/null
  $ sandwalk plan seal --slug promotion-test --directory-prefix workspaces >/dev/null

  $ evidence_claim=$(sandwalk step claim --slug promotion-test \
  >   --directory-prefix workspaces --step evidence | jq -r '.result.claim')
  $ alternative_claim=$(sandwalk step claim --slug promotion-test \
  >   --directory-prefix workspaces --step alternative | jq -r '.result.claim')

A promotion associates the snapshot without changing its immutable artifact.

  $ before=$(shasum -a 256 workspaces/promotion-test/artifacts/snapshots/"$snapshot"/document.md)
  $ sandwalk snapshot promote --slug promotion-test \
  >   --directory-prefix workspaces --claim "$evidence_claim" "$snapshot" | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","step":"evidence","promoted":true}}
  $ after=$(shasum -a 256 workspaces/promotion-test/artifacts/snapshots/"$snapshot"/document.md)
  $ test "$before" = "$after"

The same step may retry idempotently, while another step cannot take ownership.

  $ sandwalk snapshot promote --slug promotion-test \
  >   --directory-prefix workspaces --claim "$evidence_claim" "$snapshot" | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"snapshot":"snap_ID","step":"evidence","promoted":false}}

  $ sandwalk snapshot promote --slug promotion-test \
  >   --directory-prefix workspaces --claim "$alternative_claim" "$snapshot" | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":false,"error":{"code":"SNAPSHOT_PROMOTION_CONFLICT","message":"Snapshot \"snap_ID\" already belongs to another plan step."}}

The owning claim can create exact evidence directly from the reconnaissance
snapshot without a second fetch.

  $ sandwalk excerpt create --slug promotion-test \
  >   --directory-prefix workspaces --claim "$evidence_claim" \
  >   --snapshot "$snapshot" --lines 1:1 | \
  >   sed -E 's/excerpt_[0-9a-f]{32}/excerpt_ID/g'
  {"ok":true,"result":{"excerpt":"excerpt_ID","created":true,"lines":"1:1","bytes":"0:16"}}

  $ sandwalk excerpt create --slug promotion-test \
  >   --directory-prefix workspaces --claim "$alternative_claim" \
  >   --snapshot "$snapshot" --lines 1:1 | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":false,"error":{"code":"SNAPSHOT_NOT_OWNED_BY_CLAIM","message":"Snapshot \"snap_ID\" belongs to another research step."}}

  $ ./inspect_workspace.exe --inspect-promotions \
  >   workspaces/promotion-test/database/sandwalk.sqlite3 | \
  >   sed -E 's/snap_[0-9a-f]{32}/snap_ID/; s/claim_[0-9a-f]{32}/claim_ID/'
  snap_ID|evidence|claim_ID

Released schema 19 upgrades through the promotion migration.

  $ mkdir -p legacy/database legacy/logs legacy/artifacts
  $ ./inspect_workspace.exe --create-v19 legacy/database/sandwalk.sqlite3 legacy
  $ sandwalk gc --slug legacy --directory-prefix . --raw --plan >/dev/null
  $ ./inspect_workspace.exe legacy/database/sandwalk.sqlite3 | sed -n '2p'
  22
