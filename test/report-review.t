  $ mkdir -p workspace/block-review/database workspace/block-review/logs
  $ ./inspect_workspace.exe --create-v13 workspace/block-review/database/sandwalk.sqlite3 block-review

Reviews must cover every current block and bind to exact hashes.

  $ cat > incomplete.json <<'EOF'
  > {"protocol":"sandwalk.report-review.v1","report_revision":1,"blocks":[{"ordinal":1,"block_md5":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","verdict":"supported","summary":"Heading is consistent."}]}
  > EOF
  $ sandwalk draft review \
  >   --slug block-review --directory-prefix workspace \
  >   --review-file incomplete.json
  {"ok":false,"error":{"code":"REPORT_REVIEW_INCOMPLETE","message":"Report review must cover every current block."}}
  [1]

  $ cat > stale.json <<'EOF'
  > {"protocol":"sandwalk.report-review.v1","report_revision":1,"blocks":[{"ordinal":1,"block_md5":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","verdict":"supported","summary":"Heading is consistent."},{"ordinal":2,"block_md5":"dddddddddddddddddddddddddddddddd","verdict":"supported","summary":"Claim is supported."}]}
  > EOF
  $ sandwalk draft review \
  >   --slug block-review --directory-prefix workspace \
  >   --review-file stale.json
  {"ok":false,"error":{"code":"REPORT_BLOCK_STALE","message":"Report block 2 hash is stale."}}
  [1]

  $ cat > accepted.json <<'EOF'
  > {"protocol":"sandwalk.report-review.v1","report_revision":1,"blocks":[{"ordinal":1,"block_md5":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","verdict":"supported","summary":"Heading is consistent."},{"ordinal":2,"block_md5":"cccccccccccccccccccccccccccccccc","verdict":"partially-supported","summary":"Claim is supported with its qualification."}]}
  > EOF
  $ sandwalk draft review \
  >   --slug block-review --directory-prefix workspace \
  >   --review-file accepted.json
  {"ok":true,"result":{"revision":1,"accepted":true,"phase":"finalizing"}}

  $ ./inspect_workspace.exe --inspect-block-reviews workspace/block-review/database/sandwalk.sqlite3
  1|1|supported|32|Heading is consistent.
  1|2|partially-supported|32|Claim is supported with its qualification.

  $ ./inspect_workspace.exe workspace/block-review/database/sandwalk.sqlite3
  block-review|finalizing
  25
  wal
  ok

Rejected blocks return the workspace to drafting.

  $ mkdir -p workspace/redraft/database workspace/redraft/logs
  $ ./inspect_workspace.exe --create-v13 workspace/redraft/database/sandwalk.sqlite3 redraft
  $ sed 's/partially-supported/unsupported/' accepted.json > rejected.json
  $ sandwalk draft review \
  >   --slug redraft --directory-prefix workspace \
  >   --review-file rejected.json
  {"ok":true,"result":{"revision":1,"accepted":false,"phase":"drafting"}}

  $ ./inspect_workspace.exe workspace/redraft/database/sandwalk.sqlite3
  redraft|drafting
  25
  wal
  ok
