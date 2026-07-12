  $ sandwalk init --slug extension-test --directory-prefix workspaces
  {"ok":true,"result":{"slug":"extension-test","phase":"initialized","schema_version":24}}

Extensions are rejected until the initial plan is sealed.

  $ printf 'A source gap appeared during research.' > reason.md
  $ sandwalk plan extend --slug extension-test --directory-prefix workspaces \
  >   --key follow-up --title 'Resolve source gap' --reason-file reason.md
  {"ok":false,"error":{"code":"PLAN_EXTENSION_NOT_ALLOWED","message":"Plan extension is not allowed while the workspace phase is initialized."},"next":"'sandwalk' 'next' '--slug' 'extension-test' '--directory-prefix' 'workspaces'"}
  [1]

  $ sandwalk plan add-step --slug extension-test --directory-prefix workspaces \
  >   --key primary --title 'Research primary source' >/dev/null
  $ sandwalk plan validate --slug extension-test --directory-prefix workspaces >/dev/null
  $ sandwalk plan seal --slug extension-test --directory-prefix workspaces >/dev/null

An extension atomically appends one reasoned step and keeps the new revision
validated and sealed.

  $ sandwalk plan extend --slug extension-test --directory-prefix workspaces \
  >   --key follow-up --title 'Resolve source gap' --reason-file reason.md \
  >   --on primary
  {"ok":true,"result":{"key":"follow-up","title":"Resolve source gap","required":true,"position":2,"revision":2,"dependencies":["primary"],"phase":"researching","plan_path":"workspaces/extension-test/exports/research-plan.md"}}

  $ grep -E '^(Phase|Validation|Sealed):|^## Extensions|^- Revision|^  Reason:' \
  >   workspaces/extension-test/exports/research-plan.md
  Phase: researching
  Validation: current
  Sealed: yes
  ## Extensions
  - Revision 2 added `follow-up`
    Reason: "A source gap appeared during research."

  $ sandwalk plan list --slug extension-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"researching","revision":2,"objective":null,"steps":[{"key":"primary","title":"Research primary source","required":true,"position":1},{"key":"follow-up","title":"Resolve source gap","required":true,"position":2}],"dependencies":[{"step":"follow-up","depends_on":"primary"}],"extensions":[{"revision":2,"step":"follow-up","reason":"A source gap appeared during research."}]}}

  $ ./inspect_workspace.exe --inspect-extensions \
  >   workspaces/extension-test/database/sandwalk.sqlite3
  2|follow-up|A source gap appeared during research.|32|38

The new dependency participates in eligibility; the original step remains next.

  $ sandwalk next --slug extension-test --directory-prefix workspaces
  {"ok":true,"result":{"phase":"researching","action":"claim-step","reason":"The selected dependency-ready plan step has no active claim.","advisory":true,"alternatives_possible":true,"step":"primary"},"next":"'sandwalk' 'step' 'claim' '--step' 'primary' '--slug' 'extension-test' '--directory-prefix' 'workspaces'"}

Invalid dependencies roll back the entire extension.

  $ printf 'Investigate a second gap.' > missing.md
  $ sandwalk plan extend --slug extension-test --directory-prefix workspaces \
  >   --key missing-dependency --title 'Missing dependency' \
  >   --reason-file missing.md --on absent
  {"ok":false,"error":{"code":"PLAN_STEP_NOT_FOUND","message":"Plan step \"absent\" does not exist."}}
  [1]

  $ sandwalk plan list --slug extension-test --directory-prefix workspaces | \
  >   jq -r '.result.revision'
  2

Released schema 18 upgrades through the extension migration.

  $ mkdir -p legacy/database legacy/logs legacy/artifacts
  $ ./inspect_workspace.exe --create-v18 legacy/database/sandwalk.sqlite3 legacy
  $ sandwalk gc --slug legacy --directory-prefix . --raw --plan >/dev/null
  $ ./inspect_workspace.exe legacy/database/sandwalk.sqlite3 | sed -n '2p'
  24
