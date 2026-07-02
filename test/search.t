Create a released-schema v6 workspace with an active claim and search through v7.

  $ mkdir -p workspace/search-test/database workspace/search-test/logs \
  >   workspace/search-test/exports workspace/search-test/artifacts/temporary
  $ ./inspect_workspace.exe --create-v6 workspace/search-test/database/sandwalk.sqlite3 search-test

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --query "small topic" --limit 1 \
  >   --adapter ../adapters/ddgr-search | \
  >   sed -E 's/hit_[0-9a-f]{32}/hit_ID/g'
  {"ok":true,"result":{"count":1,"hits":[{"hit":"hit_ID","url":"https://example.test/primary","title":"Primary result","snippet":"A deterministic search result."}]}}

  $ ./inspect_workspace.exe --inspect-hits workspace/search-test/database/sandwalk.sqlite3
  36|1|https://example.test/primary|Primary result|A deterministic search result.

  $ ./inspect_workspace.exe workspace/search-test/database/sandwalk.sqlite3
  search-test|researching
  19
  wal
  ok

  $ PATH="$PWD/fakes:$PATH" sandwalk search \
  >   --slug search-test --directory-prefix workspace \
  >   --query "missing claim" --limit 1 \
  >   --adapter ../adapters/ddgr-search
  {"ok":false,"error":{"code":"SEARCH_REQUIRES_CLAIM","message":"Research search requires an active claim."}}
  [1]
