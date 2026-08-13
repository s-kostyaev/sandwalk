Visual evidence is an immutable, bounded rendering of one retained PDF page.

  $ mkdir -p workspace/visual-test/database workspace/visual-test/logs \
  >   workspace/visual-test/exports workspace/visual-test/artifacts/temporary \
  >   workspace/visual-test/artifacts/visuals
  $ ./inspect_workspace.exe --create-v7 \
  >   workspace/visual-test/database/sandwalk.sqlite3 visual-test

  $ fetched=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter "$PWD/fakes/sandwalk-fetch-pdf" \
  >   hit_00000000000000000000000000000001)
  $ snapshot=$(printf '%s' "$fetched" | jq -r '.result.snapshot')
  $ printf 'The page contains the fixture diagram and its labels.\n' > observation.md
  $ ./inspect_workspace.exe --seed-raw-gc-plan \
  >   workspace/visual-test/database/sandwalk.sqlite3

  $ rendered=$(PATH="$PWD/fakes:$PATH" sandwalk visual create \
  >   --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$snapshot" --page 1 \
  >   --description-file observation.md \
  >   --adapter "$PWD/fakes/sandwalk-render-pdf-page")
  $ printf '%s\n' "$rendered" | sed -E \
  >   -e 's/visual_[0-9a-f]{32}/visual_ID/g' \
  >   -e 's/snap_[0-9a-f]{32}/snap_ID/g' \
  >   -e 's#artifacts/visuals/visual_ID/page.png#artifacts/visuals/visual_ID/page.png#'
  {"ok":true,"result":{"visual":"visual_ID","created":true,"snapshot":"snap_ID","page":1,"page_count":2,"image":"workspace/visual-test/artifacts/visuals/visual_ID/page.png","render_profile":"poppler-png-144dpi-v1"}}
  $ visual=$(printf '%s' "$rendered" | jq -r '.result.visual')
  $ file "workspace/visual-test/artifacts/visuals/$visual/page.png" | sed "s/$visual/visual_ID/"
  workspace/visual-test/artifacts/visuals/visual_ID/page.png: PNG image data, 1 x 1, 8-bit gray+alpha, non-interlaced

The same snapshot page and render profile are idempotent.

  $ PATH="$PWD/fakes:$PATH" sandwalk visual create \
  >   --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$snapshot" --page 1 \
  >   --description-file observation.md \
  >   --adapter "$PWD/fakes/sandwalk-render-pdf-page" | \
  >   sed -E -e 's/visual_[0-9a-f]{32}/visual_ID/g' -e 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"ok":true,"result":{"visual":"visual_ID","created":false,"snapshot":"snap_ID","page":1,"page_count":2,"image":"workspace/visual-test/artifacts/visuals/visual_ID/page.png","render_profile":"poppler-png-144dpi-v1"}}
  $ find workspace/visual-test/artifacts/visuals -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
  1

Renderer output is a closed two-file set; undeclared artifacts are rejected.

  $ SANDWALK_TEST_EXTRA_VISUAL_ARTIFACT=1 PATH="$PWD/fakes:$PATH" \
  >   sandwalk visual create --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$snapshot" --page 1 --description-file observation.md \
  >   --adapter "$PWD/fakes/sandwalk-render-pdf-page"
  {"ok":false,"error":{"code":"VISUAL_RENDER_ARTIFACT_ERROR","message":"Visual render output must contain only the bounded regular artifacts."}}
  [1]
  $ find workspace/visual-test/artifacts/visuals -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
  1
  $ find workspace/visual-test/artifacts/temporary -name 'visual-*' | wc -l | tr -d ' '
  0

Visuals attach through the same typed relation as exact excerpts.

  $ printf 'The fixture page contains a labeled diagram.\n' > finding.md
  $ sandwalk finding create --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --step fixture-step --key visual-finding --claim-file finding.md
  {"ok":true,"result":{"finding":"fixture-step/visual-finding","revision":1,"state":"draft"}}
  $ sandwalk finding attach --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/visual-finding --visual "$visual" --relation supports
  {"ok":true,"result":{"finding":"fixture-step/visual-finding","revision":1,"attached":true,"revised":false}}
  $ sandwalk finding seal --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/visual-finding >/dev/null

A v1 text-only review cannot silently approve an attached image.

  $ sandwalk continue --slug visual-test --directory-prefix workspace >/dev/null
  $ jq -c '{evidence:.fixed.evidence,review:.editable.review}' \
  >   workspace/visual-test/artifacts/work/current.json | \
  >   sed -E -e 's/visual_[0-9a-f]{32}/visual_ID/g' -e 's/snap_[0-9a-f]{32}/snap_ID/g'
  {"evidence":[{"kind":"visual","visual":"visual_ID","image_path":"workspace/visual-test/artifacts/visuals/visual_ID/page.png","snapshot":"snap_ID","page":1,"relation":"supports","description":"The page contains the fixture diagram and its labels.","description_is_source_text":false}],"review":{"protocol":"sandwalk.finding-review.v2","verdict":"","summary":"","source_quality":"","conflicts":"","qualifications":"","reviewed_visuals":[]}}

  $ printf '%s\n' '{"protocol":"sandwalk.finding-review.v1","verdict":"supported","summary":"Reviewed.","source_quality":"Primary PDF.","conflicts":"","qualifications":""}' > review-v1.json
  $ sandwalk finding review --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/visual-finding --review-file review-v1.json
  {"ok":false,"error":{"code":"FINDING_VISUAL_REVIEW_INCOMPLETE","message":"Finding \"fixture-step/visual-finding\" review must enumerate every attached visual reference."}}
  [1]

  $ jq -n --arg visual "$visual" '{protocol:"sandwalk.finding-review.v2",verdict:"supported",summary:"The image was inspected.",source_quality:"Primary PDF page.",conflicts:"",qualifications:"",reviewed_visuals:[$visual]}' > review-v2.json
  $ sandwalk finding review --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/visual-finding --review-file review-v2.json
  {"ok":true,"result":{"finding":"fixture-step/visual-finding","revision":1,"verdict":"supported","reviewed":true,"state":"reviewed"}}

The writer pack points a vision-capable model at the image and labels the
agent observation as non-source text.

  $ sandwalk step complete --slug visual-test --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 >/dev/null
  $ sandwalk gc --slug visual-test --directory-prefix workspace --raw --apply
  {"ok":false,"error":{"code":"GC_NO_PLAN","message":"No unapplied raw cleanup plan exists."}}
  [1]
  $ sandwalk gc --slug visual-test --directory-prefix workspace --raw --plan
  {"ok":true,"result":{"mode":"plan","count":0,"plan_path":"workspace/visual-test/artifacts/gc-raw-plan.json"}}
  $ test -f "workspace/visual-test/artifacts/snapshots/$snapshot/original/source.pdf"
  $ cp "workspace/visual-test/artifacts/visuals/$visual/page.png" saved-page.png
  $ printf tamper >> "workspace/visual-test/artifacts/visuals/$visual/page.png"
  $ sandwalk draft prepare --slug visual-test --directory-prefix workspace
  {"ok":false,"error":{"code":"WRITER_PACK_ARTIFACT_ERROR","message":"Could not validate bounded evidence artifacts."}}
  [1]
  $ mv saved-page.png "workspace/visual-test/artifacts/visuals/$visual/page.png"
  $ sandwalk draft prepare --slug visual-test --directory-prefix workspace | \
  >   sed -E 's/visual_[0-9a-f]{32}/visual_ID/g'
  {"ok":true,"result":{"phase":"drafting","writer_pack":"workspace/visual-test/exports/writer-pack.md","evidence_count":1}}
  $ sed -E -e 's/visual_[0-9a-f]{32}/visual_ID/g' -e 's/snap_[0-9a-f]{32}/snap_ID/g' workspace/visual-test/exports/writer-pack.md | \
  >   sed -n '/### Visual evidence/,+7p'
  ### Visual evidence: visual_ID (supports)
  
  - Source: https://example.test/start
  - Snapshot: snap_ID
  - PDF page: 1
  - Image: workspace/visual-test/artifacts/visuals/visual_ID/page.png
  - Agent observation (not source text): The page contains the fixture diagram and its labels.
  

Visual-only findings retain their source provenance through finalization.

  $ printf '# Visual report\n\nThe diagram is present. [cite:fixture-step/visual-finding]\n' > report.md
  $ submitted=$(sandwalk draft submit --slug visual-test --directory-prefix workspace --report-file report.md)
  $ printf '%s' "$submitted" | jq '{protocol:"sandwalk.report-review.v1",report_revision:.result.revision,blocks:[.result.review_blocks[] | . + {verdict:"supported",summary:"Checked."}]}' > report-review.json
  $ sandwalk draft review --slug visual-test --directory-prefix workspace --review-file report-review.json >/dev/null
  $ sandwalk finalize --slug visual-test --directory-prefix workspace >/dev/null
  $ cat workspace/visual-test/exports/sources.md
  <!-- sandwalk-sources-v1 -->
  # Sources
  
  1. https://example.test/start

A schema-25 workspace already waiting for drafting remains readable before the
write transaction performs the visual-evidence migration.

  $ mkdir -p workspace/visual-legacy/database workspace/visual-legacy/logs \
  >   workspace/visual-legacy/exports
  $ ./inspect_workspace.exe --create-v25-evidence-review \
  >   workspace/visual-legacy/database/sandwalk.sqlite3 visual-legacy
  $ printf Fixture > fixture-excerpt.md
  $ sandwalk draft prepare --slug visual-legacy --directory-prefix workspace
  {"ok":true,"result":{"phase":"drafting","writer_pack":"workspace/visual-legacy/exports/writer-pack.md","evidence_count":1}}
  $ ./inspect_workspace.exe workspace/visual-legacy/database/sandwalk.sqlite3
  visual-legacy|drafting
  26
  wal
  ok

A retained PDF cannot escape its immutable snapshot through a symlinked parent.

  $ mkdir -p workspace/visual-symlink/database workspace/visual-symlink/logs \
  >   workspace/visual-symlink/exports workspace/visual-symlink/artifacts/temporary \
  >   workspace/visual-symlink/artifacts/visuals
  $ ./inspect_workspace.exe --create-v7 \
  >   workspace/visual-symlink/database/sandwalk.sqlite3 visual-symlink
  $ symlink_fetch=$(SANDWALK_TEST_SYMLINK_PDF_PARENT=1 PATH="$PWD/fakes:$PATH" \
  >   sandwalk fetch --slug visual-symlink --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter "$PWD/fakes/sandwalk-fetch-pdf" \
  >   hit_00000000000000000000000000000001)
  $ symlink_snapshot=$(printf '%s' "$symlink_fetch" | jq -r '.result.snapshot')
  $ PATH="$PWD/fakes:$PATH" sandwalk visual create \
  >   --slug visual-symlink --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$symlink_snapshot" --page 1 \
  >   --description-file observation.md \
  >   --adapter "$PWD/fakes/sandwalk-render-pdf-page"
  {"ok":false,"error":{"code":"VISUAL_RENDER_ARTIFACT_ERROR","message":"Retained PDF must be a regular non-symlink snapshot artifact."}}
  [1]

The 256-reference review bound is enforced before a finding becomes impossible
to review; another relation to an existing visual would not consume a slot.

  $ mkdir -p workspace/visual-limit/database workspace/visual-limit/logs \
  >   workspace/visual-limit/exports workspace/visual-limit/artifacts/temporary \
  >   workspace/visual-limit/artifacts/visuals
  $ ./inspect_workspace.exe --create-v7 \
  >   workspace/visual-limit/database/sandwalk.sqlite3 visual-limit
  $ limit_fetch=$(PATH="$PWD/fakes:$PATH" sandwalk fetch \
  >   --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --adapter "$PWD/fakes/sandwalk-fetch-pdf" \
  >   hit_00000000000000000000000000000001)
  $ limit_snapshot=$(printf '%s' "$limit_fetch" | jq -r '.result.snapshot')
  $ limit_render=$(PATH="$PWD/fakes:$PATH" sandwalk visual create \
  >   --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --snapshot "$limit_snapshot" --page 1 \
  >   --description-file observation.md \
  >   --adapter "$PWD/fakes/sandwalk-render-pdf-page")
  $ limit_visual=$(printf '%s' "$limit_render" | jq -r '.result.visual')
  $ printf 'Bounded visual bundle.\n' > limit-finding.md
  $ sandwalk finding create --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --step fixture-step --key limit-finding --claim-file limit-finding.md >/dev/null
  $ sandwalk finding attach --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/limit-finding --visual "$limit_visual" \
  >   --relation supports >/dev/null
  $ ./inspect_workspace.exe --fill-visual-limit \
  >   workspace/visual-limit/database/sandwalk.sqlite3
  $ extra_visual=$(printf 'visual_%032x' 256)
  $ sandwalk finding attach --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/limit-finding --visual "$extra_visual" \
  >   --relation supports
  {"ok":false,"error":{"code":"FINDING_VISUAL_LIMIT_EXCEEDED","message":"Finding \"fixture-step/limit-finding\" cannot attach more than 256 distinct visuals."}}
  [1]
  $ sandwalk finding attach --slug visual-limit --directory-prefix workspace \
  >   --claim claim_00000000000000000000000000000001 \
  >   --finding fixture-step/limit-finding --visual "$limit_visual" \
  >   --relation context
  {"ok":true,"result":{"finding":"fixture-step/limit-finding","revision":1,"attached":true,"revised":false}}
