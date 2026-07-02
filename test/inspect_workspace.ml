let check database return_code =
  if not (Sqlite3.Rc.is_success return_code)
  then failwith (Sqlite3.errmsg database)
;;

let print_query database sql =
  check
    database
    (Sqlite3.exec database sql ~cb:(fun row _headers ->
       row
       |> Array.to_list
       |> List.map (Option.value ~default:"NULL")
       |> String.concat "|"
       |> print_endline))
;;

let create_v1 database slug =
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE workspaces (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  slug TEXT NOT NULL CHECK (
    length(slug) BETWEEN 1 AND 63
    AND slug NOT GLOB '*[^a-z0-9-]*'
    AND slug NOT GLOB '-*'
    AND slug NOT GLOB '*-'
    AND slug NOT GLOB '*--*'
  ),
  phase TEXT NOT NULL CHECK (
    phase IN (
      'initialized', 'scoping', 'reconnaissance', 'planning', 'researching',
      'evidence-review', 'drafting', 'draft-review', 'finalizing', 'completed'
    )
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (1, '2026-01-01 00:00:00Z');
PRAGMA user_version = 1;
PRAGMA journal_mode = WAL;
|});
  let statement =
    Sqlite3.prepare
      database
      {|
INSERT INTO workspaces (singleton, slug, phase, created_at, updated_at)
VALUES (1, ?1, 'initialized', '2026-01-01 00:00:00Z', '2026-01-01 00:00:00Z')
|}
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    (fun () ->
      check database (Sqlite3.bind_text statement 1 slug);
      check database (Sqlite3.step statement))
;;

let create_v2 database slug =
  create_v1 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE plan_steps (
  step_key TEXT PRIMARY KEY CHECK (
    length(step_key) BETWEEN 1 AND 63
    AND step_key NOT GLOB '*[^a-z0-9-]*'
    AND step_key NOT GLOB '-*'
    AND step_key NOT GLOB '*-'
    AND step_key NOT GLOB '*--*'
  ),
  title TEXT NOT NULL CHECK (
    length(CAST(title AS BLOB)) BETWEEN 1 AND 200
    AND title = trim(title)
  ),
  position INTEGER NOT NULL UNIQUE CHECK (position >= 1),
  required INTEGER NOT NULL CHECK (required IN (0, 1)),
  created_at TEXT NOT NULL
);
CREATE TABLE plan_metadata (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  revision INTEGER NOT NULL CHECK (revision >= 0)
);
INSERT INTO plan_metadata (singleton, revision) VALUES (1, 1);
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES ('fixture-step', 'Fixture step', 1, 1, '2026-01-01 00:00:00Z');
INSERT INTO schema_migrations (version, applied_at)
VALUES (2, '2026-01-01 00:00:00Z');
UPDATE workspaces SET phase = 'planning';
PRAGMA user_version = 2;
|})
;;

let create_v3 database slug =
  create_v2 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE plan_metadata ADD COLUMN validated_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN validated_at TEXT;
UPDATE plan_metadata
SET validated_revision = 1, validated_at = '2026-01-01 00:00:00Z';
INSERT INTO schema_migrations (version, applied_at)
VALUES (3, '2026-01-01 00:00:00Z');
PRAGMA user_version = 3;
|})
;;

let create_v4 database slug =
  create_v3 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE plan_metadata ADD COLUMN sealed_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN sealed_at TEXT;
UPDATE plan_metadata
SET sealed_revision = 1, sealed_at = '2026-01-01 00:00:00Z';
UPDATE workspaces SET phase = 'researching';
INSERT INTO schema_migrations (version, applied_at)
VALUES (4, '2026-01-01 00:00:00Z');
PRAGMA user_version = 4;
|})
;;

let create_v5 database slug =
  create_v4 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE step_executions (
  step_key TEXT PRIMARY KEY REFERENCES plan_steps(step_key),
  state TEXT NOT NULL CHECK (
    state IN ('pending', 'claimed', 'suspended', 'expired', 'blocked', 'completed')
  ),
  active_claim_id TEXT UNIQUE,
  lease_expires_unix_seconds INTEGER,
  attempt INTEGER NOT NULL CHECK (attempt >= 0),
  CHECK (
    (state = 'claimed' AND active_claim_id IS NOT NULL
      AND lease_expires_unix_seconds IS NOT NULL)
    OR
    (state <> 'claimed' AND active_claim_id IS NULL
      AND lease_expires_unix_seconds IS NULL)
  )
);
CREATE TABLE claims (
  claim_id TEXT PRIMARY KEY CHECK (
    length(claim_id) = 38
    AND substr(claim_id, 1, 6) = 'claim_'
    AND substr(claim_id, 7) NOT GLOB '*[^a-f0-9]*'
  ),
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  attempt INTEGER NOT NULL CHECK (attempt >= 1),
  issued_at TEXT NOT NULL,
  lease_expires_at TEXT NOT NULL,
  lease_expires_unix_seconds INTEGER NOT NULL,
  ended_at TEXT,
  end_reason TEXT CHECK (
    end_reason IS NULL OR end_reason IN ('expired', 'suspended', 'blocked', 'completed')
  )
);
INSERT INTO step_executions (
  step_key, state, active_claim_id, lease_expires_unix_seconds, attempt
) VALUES (
  'fixture-step', 'claimed', 'claim_00000000000000000000000000000001',
  4102444800, 1
);
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds
) VALUES (
  'claim_00000000000000000000000000000001', 'fixture-step', 1,
  '2026-01-01 00:00:00Z', '2100-01-01 00:00:00Z', 4102444800
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (5, '2026-01-01 00:00:00Z');
PRAGMA user_version = 5;
|})
;;

let create_v6 database slug =
  create_v5 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE claims ADD COLUMN lease_duration_seconds INTEGER
  CHECK (lease_duration_seconds BETWEEN 30 AND 86400);
UPDATE claims SET lease_duration_seconds = 900;
CREATE TABLE checkpoints (
  checkpoint_id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  claim_id TEXT NOT NULL REFERENCES claims(claim_id),
  checkpoint_number INTEGER NOT NULL CHECK (checkpoint_number >= 1),
  created_at TEXT NOT NULL,
  summary TEXT NOT NULL,
  next TEXT NOT NULL,
  summary_path TEXT NOT NULL,
  summary_md5 TEXT NOT NULL,
  summary_size INTEGER NOT NULL CHECK (summary_size >= 0),
  next_path TEXT NOT NULL,
  next_md5 TEXT NOT NULL,
  next_size INTEGER NOT NULL CHECK (next_size >= 0),
  UNIQUE (step_key, checkpoint_number)
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (6, '2026-01-01 00:00:00Z');
PRAGMA user_version = 6;
|})
;;

let create_v7 database slug =
  create_v6 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE search_queries (
  query_id INTEGER PRIMARY KEY AUTOINCREMENT,
  query TEXT NOT NULL,
  phase TEXT NOT NULL,
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  adapter TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE search_hits (
  hit_ref TEXT PRIMARY KEY CHECK (
    length(hit_ref) = 36
    AND substr(hit_ref, 1, 4) = 'hit_'
    AND substr(hit_ref, 5) NOT GLOB '*[^a-f0-9]*'
  ),
  query_id INTEGER NOT NULL REFERENCES search_queries(query_id),
  position INTEGER NOT NULL CHECK (position >= 1),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  snippet TEXT NOT NULL,
  UNIQUE (query_id, position)
);
UPDATE plan_metadata
SET revision = 2, validated_revision = 2, sealed_revision = 2;
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES (
  'completed-step', 'Completed fixture step', 2, 1,
  '2026-01-01 00:00:00Z'
);
INSERT INTO step_executions (
  step_key, state, active_claim_id, lease_expires_unix_seconds, attempt
) VALUES ('completed-step', 'completed', NULL, NULL, 1);
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds, ended_at, end_reason, lease_duration_seconds
) VALUES (
  'claim_00000000000000000000000000000002', 'completed-step', 1,
  '2026-01-01 00:00:00Z', '2026-01-01 00:15:00Z', 1767226500,
  '2026-01-01 00:10:00Z', 'completed', 900
);
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
) VALUES (
  'fixture query', 'researching',
  'claim_00000000000000000000000000000001', 'fixture-step',
  'fixture-search', '2026-01-01 00:00:00Z'
);
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (
  'hit_00000000000000000000000000000001', 1, 1,
  'https://example.test/start', 'Fixture result', 'Fixture snippet.'
);
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
) VALUES (
  'completed fixture query', 'researching',
  'claim_00000000000000000000000000000002', 'completed-step',
  'fixture-search', '2026-01-01 00:00:00Z'
);
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (
  'hit_00000000000000000000000000000002', 2, 1,
  'https://example.test/completed', 'Completed result', 'Completed snippet.'
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (7, '2026-01-01 00:00:00Z');
PRAGMA user_version = 7;
|})
;;

let create_v8 database slug =
  create_v7 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE snapshots (
  snapshot_ref TEXT PRIMARY KEY CHECK (
    length(snapshot_ref) = 37
    AND substr(snapshot_ref, 1, 5) = 'snap_'
    AND substr(snapshot_ref, 6) NOT GLOB '*[^a-f0-9]*'
  ),
  hit_ref TEXT NOT NULL REFERENCES search_hits(hit_ref),
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  artifact_path TEXT NOT NULL UNIQUE,
  final_url TEXT NOT NULL,
  input_sha256 TEXT NOT NULL,
  markdown_sha256 TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  retrieved_at TEXT NOT NULL
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (8, '2026-01-01 00:00:00Z');
PRAGMA user_version = 8;
|});
  let statement =
    Sqlite3.prepare
      database
      {|
INSERT INTO snapshots (
  snapshot_ref, hit_ref, claim_id, step_key, artifact_path, final_url,
  input_sha256, markdown_sha256, manifest_json, retrieved_at
) VALUES (
  'snap_00000000000000000000000000000001',
  'hit_00000000000000000000000000000001',
  'claim_00000000000000000000000000000001',
  'fixture-step', ?1, 'https://example.test/final', ?2, ?3, '{}',
  '2026-01-01 00:00:00Z'
)
|}
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    (fun () ->
      check
        database
        (Sqlite3.bind_text
           statement
           1
           ("workspace/"
            ^ slug
            ^ "/artifacts/snapshots/snap_00000000000000000000000000000001"));
      check database (Sqlite3.bind_text statement 2 (String.make 64 'a'));
      check database (Sqlite3.bind_text statement 3 (String.make 64 'b'));
      check database (Sqlite3.step statement))
;;

let create_v9 database slug =
  create_v8 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE excerpts (
  excerpt_ref TEXT PRIMARY KEY CHECK (
    length(excerpt_ref) = 40
    AND substr(excerpt_ref, 1, 8) = 'excerpt_'
    AND substr(excerpt_ref, 9) NOT GLOB '*[^a-f0-9]*'
  ),
  snapshot_ref TEXT NOT NULL REFERENCES snapshots(snapshot_ref),
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  artifact_path TEXT NOT NULL UNIQUE,
  markdown_sha256 TEXT NOT NULL CHECK (
    length(markdown_sha256) = 64
    AND markdown_sha256 NOT GLOB '*[^a-f0-9]*'
  ),
  line_start INTEGER NOT NULL CHECK (line_start >= 1),
  line_end INTEGER NOT NULL CHECK (line_end >= line_start),
  byte_start INTEGER NOT NULL CHECK (byte_start >= 0),
  byte_end INTEGER NOT NULL CHECK (byte_end > byte_start),
  excerpt_md5 TEXT NOT NULL CHECK (
    length(excerpt_md5) = 32
    AND excerpt_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  excerpt_size INTEGER NOT NULL CHECK (excerpt_size = byte_end - byte_start),
  created_at TEXT NOT NULL,
  UNIQUE (snapshot_ref, byte_start, byte_end)
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (9, '2026-01-01 00:00:00Z');
PRAGMA user_version = 9;
|})
;;

let inspect database =
  print_query database "SELECT slug, phase FROM workspaces";
  print_query database "PRAGMA user_version";
  print_query database "PRAGMA journal_mode";
  print_query database "PRAGMA integrity_check"
;;

let inspect_claims database =
  print_query
    database
    {|
SELECT step_key, state, attempt, length(active_claim_id),
       lease_expires_unix_seconds IS NOT NULL
FROM step_executions
ORDER BY step_key
|};
  print_query
    database
    {|
SELECT step_key, attempt, COALESCE(end_reason, 'NULL')
FROM claims
ORDER BY step_key, attempt
|}
;;

let inspect_checkpoints database =
  print_query
    database
    {|
SELECT step_key, checkpoint_number, summary, next,
       length(summary_md5), summary_size, length(next_md5), next_size
FROM checkpoints
ORDER BY checkpoint_id
|}
;;

let inspect_hits database =
  print_query
    database
    {|
SELECT length(hit_ref), position, url, title, snippet
FROM search_hits
ORDER BY position
|}
;;

let inspect_snapshots database =
  print_query
    database
    {|
SELECT length(snapshot_ref), hit_ref, final_url,
       length(input_sha256), length(markdown_sha256), artifact_path
FROM snapshots
ORDER BY retrieved_at, snapshot_ref
|}
;;

let inspect_excerpts database =
  print_query
    database
    {|
SELECT length(excerpt_ref), snapshot_ref, line_start, line_end,
       byte_start, byte_end, length(excerpt_md5), excerpt_size
FROM excerpts
ORDER BY byte_start, byte_end
|}
;;

let inspect_findings database =
  print_query
    database
    {|
SELECT f.step_key, f.finding_key, f.current_revision, f.state,
       length(r.claim_md5), r.claim_size, r.claim_text
FROM findings AS f
JOIN finding_revisions AS r
  ON r.step_key = f.step_key AND r.finding_key = f.finding_key
ORDER BY f.step_key, f.finding_key, r.revision
|}
;;

let () =
  let action, path =
    match Sys.argv with
    | [| _; "--create-v1"; path; slug |] -> `Create (1, slug), path
    | [| _; "--create-v2"; path; slug |] -> `Create (2, slug), path
    | [| _; "--create-v3"; path; slug |] -> `Create (3, slug), path
    | [| _; "--create-v4"; path; slug |] -> `Create (4, slug), path
    | [| _; "--create-v5"; path; slug |] -> `Create (5, slug), path
    | [| _; "--create-v6"; path; slug |] -> `Create (6, slug), path
    | [| _; "--create-v7"; path; slug |] -> `Create (7, slug), path
    | [| _; "--create-v8"; path; slug |] -> `Create (8, slug), path
    | [| _; "--create-v9"; path; slug |] -> `Create (9, slug), path
    | [| _; "--inspect-claims"; path |] -> `Inspect_claims, path
    | [| _; "--inspect-checkpoints"; path |] -> `Inspect_checkpoints, path
    | [| _; "--inspect-hits"; path |] -> `Inspect_hits, path
    | [| _; "--inspect-snapshots"; path |] -> `Inspect_snapshots, path
    | [| _; "--inspect-excerpts"; path |] -> `Inspect_excerpts, path
    | [| _; "--inspect-findings"; path |] -> `Inspect_findings, path
    | [| _; "--expire-claim"; path; step |] -> `Expire_claim step, path
    | [| _; path |] -> `Inspect, path
    | _ -> failwith "usage: inspect_workspace [--create-v1] DATABASE [SLUG]"
  in
  let database = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
    (fun () ->
      match action with
      | `Create (1, slug) -> create_v1 database slug
      | `Create (2, slug) -> create_v2 database slug
      | `Create (3, slug) -> create_v3 database slug
      | `Create (4, slug) -> create_v4 database slug
      | `Create (5, slug) -> create_v5 database slug
      | `Create (6, slug) -> create_v6 database slug
      | `Create (7, slug) -> create_v7 database slug
      | `Create (8, slug) -> create_v8 database slug
      | `Create (9, slug) -> create_v9 database slug
      | `Create _ -> assert false
      | `Inspect -> inspect database
      | `Inspect_claims -> inspect_claims database
      | `Inspect_checkpoints -> inspect_checkpoints database
      | `Inspect_hits -> inspect_hits database
      | `Inspect_snapshots -> inspect_snapshots database
      | `Inspect_excerpts -> inspect_excerpts database
      | `Inspect_findings -> inspect_findings database
      | `Expire_claim step ->
        let statement =
          Sqlite3.prepare
            database
            {|
UPDATE step_executions
SET lease_expires_unix_seconds = 0
WHERE state = 'claimed' AND step_key = ?1
|}
        in
        Fun.protect
          ~finally:(fun () ->
            ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
          (fun () ->
            check database (Sqlite3.bind_text statement 1 step);
            check database (Sqlite3.step statement)))
;;
