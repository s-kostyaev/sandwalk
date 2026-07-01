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

let inspect database =
  print_query database "SELECT slug, phase FROM workspaces";
  print_query database "PRAGMA user_version";
  print_query database "PRAGMA journal_mode";
  print_query database "PRAGMA integrity_check"
;;

let () =
  let version, path, slug =
    match Sys.argv with
    | [| _; "--create-v1"; path; slug |] -> Some 1, path, Some slug
    | [| _; "--create-v2"; path; slug |] -> Some 2, path, Some slug
    | [| _; path |] -> None, path, None
    | _ -> failwith "usage: inspect_workspace [--create-v1] DATABASE [SLUG]"
  in
  let database = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
    (fun () ->
      match version with
      | Some 1 -> create_v1 database (Option.get slug)
      | Some 2 -> create_v2 database (Option.get slug)
      | Some _ -> assert false
      | None -> inspect database)
;;
