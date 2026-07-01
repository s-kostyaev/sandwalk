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

let () =
  let action, path =
    match Sys.argv with
    | [| _; "--create-v1"; path; slug |] -> `Create (1, slug), path
    | [| _; "--create-v2"; path; slug |] -> `Create (2, slug), path
    | [| _; "--create-v3"; path; slug |] -> `Create (3, slug), path
    | [| _; "--create-v4"; path; slug |] -> `Create (4, slug), path
    | [| _; "--create-v5"; path; slug |] -> `Create (5, slug), path
    | [| _; "--inspect-claims"; path |] -> `Inspect_claims, path
    | [| _; "--inspect-checkpoints"; path |] -> `Inspect_checkpoints, path
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
      | `Create _ -> assert false
      | `Inspect -> inspect database
      | `Inspect_claims -> inspect_claims database
      | `Inspect_checkpoints -> inspect_checkpoints database
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
