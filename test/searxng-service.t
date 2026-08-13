SearXNG lifecycle is a human-facing command group and keeps the ordinary
workspace search command backward compatible.

  $ sandwalk search-service -help 2>&1 | sed -n '/=== subcommands ===/,$p' | sed -n '1,12p'
  === subcommands ===
  
    remove                     . Stop and remove only Sandwalk's owned SearXNG
                                 container.
    start                      . Start or validate the configured SearXNG service.
    status                     . Show desired and active SearXNG service state.
    stop                       . Stop Sandwalk's managed SearXNG container.
    update                     . Apply desired SearXNG configuration and pinned
                                 image.
    help                       . explain a given subcommand (perhaps recursively)
  

Service commands preserve the standard JSON envelope. The fake helper makes
this contract deterministic without requiring Docker in the default test suite.

  $ PATH="$PWD/fakes:$PATH" SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/state" \
  > sandwalk search-service status | jq -c .
  {"ok":true,"result":{"mode":"managed","configuration_drift":false,"active":null}}

  $ PATH="$PWD/fakes:$PATH" SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/state" \
  > sandwalk search-service start --idle-timeout 30 --engine-enable arxiv | \
  > jq -c '{ok, mode: .result.mode, endpoint: .result.endpoint, profile: .result.profile}'
  {"ok":true,"mode":"managed","endpoint":"http://127.0.0.1:18888","profile":"research-v1"}

  $ PATH="$PWD/fakes:$PATH" SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/state" \
  > sandwalk search-service stop | jq -c .
  {"ok":true,"result":{"stopped":false,"removed":false}}

The actual helper validates external transport policy without contacting
Docker. Plain HTTP is accepted only on loopback.

  $ SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/external-state" \
  > ../adapters/searxng-service status \
  > --mode external --endpoint http://search.example.test 2>&1
  external HTTP endpoints are allowed only on loopback
  [69]

  $ SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/external-state" \
  > sandwalk search-service status \
  > --mode external --endpoint http://search.example.test
  {"ok":false,"error":{"code":"SEARCH_SERVICE_FAILED","message":"SearXNG service command failed: external HTTP endpoints are allowed only on loopback"}}
  [1]

  $ SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/external-state" \
  > ../adapters/searxng-service status \
  > --mode external --endpoint https://search.example.test | \
  > jq -c '{protocol, mode: .result.mode, desired_endpoint: .result.desired.endpoint, active: .result.active}'
  {"protocol":"sandwalk.searxng-service-result.v1","mode":"external","desired_endpoint":"https://search.example.test","active":null}

Config precedence is defaults, user JSON, environment, then explicit flags.

  $ mkdir config
  $ printf '%s\n' '{"schema":"sandwalk.searxng-config.v1","mode":"managed","idle_timeout_seconds":20,"search":{"language":"de","safe_search":1},"engines":{"profile":"research-v1","enable":["arxiv"],"disable":[],"keep_only":null}}' > config/searxng.json
  $ SANDWALK_CONFIG_DIRECTORY="$PWD/config" \
  > SANDWALK_SEARXNG_STATE_DIRECTORY="$PWD/config-state" \
  > SANDWALK_SEARXNG_IDLE_TIMEOUT=30 \
  > ../adapters/searxng-service status --idle-timeout 40 --language en | \
  > jq -c '{timeout: .result.desired.idle_timeout_seconds, language: .result.desired.search.language, safe: .result.desired.search.safe_search, enable: .result.desired.engines.enable}'
  {"timeout":40,"language":"en","safe":1,"enable":["arxiv"]}

The shared activity guard permits parallel searches, while lifecycle shutdown
waits for them. The watchdog also rechecks generation before stopping the exact
owned container.

  $ PYTHONDONTWRITEBYTECODE=1 python3 ./check_searxng_service.py ../adapters/searxng-service
  searxng service locks and watchdog: ok
