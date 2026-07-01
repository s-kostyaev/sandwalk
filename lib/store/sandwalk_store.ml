open! Core

module Error = struct
  type t =
    | Already_initialized
    | Database_error of string
  [@@deriving sexp_of]
end

let current_schema_version = 1

let check database return_code =
  if Sqlite3.Rc.is_success return_code
  then Ok ()
  else
    Error
      (Error.Database_error
         (sprintf
            "%s: %s"
            (Sqlite3.Rc.to_string return_code)
            (Sqlite3.errmsg database)))
;;

let execute database sql = check database (Sqlite3.exec database sql)

let with_statement database sql ~f =
  let statement = Sqlite3.prepare database sql in
  Exn.protect
    ~f:(fun () -> f statement)
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
;;

let bind_text database statement index value =
  check database (Sqlite3.bind_text statement index value)
;;

let step_done database statement =
  match Sqlite3.step statement with
  | Sqlite3.Rc.DONE -> Ok ()
  | return_code -> check database return_code
;;

let workspace_exists database =
  with_statement database "SELECT 1 FROM workspaces WHERE singleton = 1" ~f:(fun statement ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok true
    | Sqlite3.Rc.DONE -> Ok false
    | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let migration =
  {|
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS workspaces (
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
PRAGMA user_version = 1;
|}
;;

let insert_migration database ~now =
  with_statement
    database
    "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (1, ?1)"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = bind_text database statement 1 now in
      step_done database statement)
;;

let insert_workspace database ~slug ~now =
  with_statement
    database
    {|
INSERT INTO workspaces (singleton, slug, phase, created_at, updated_at)
VALUES (1, ?1, 'initialized', ?2, ?2)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Slug.to_string slug)
      in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let initialize ?(busy_timeout_ms = 5_000) ~database_path ~slug ~now () =
  let database = Sqlite3.db_open database_path in
  Exn.protect
    ~f:(fun () ->
      try
        Sqlite3.busy_timeout database busy_timeout_ms;
        let open Result.Let_syntax in
        let%bind () = execute database "PRAGMA journal_mode = WAL" in
        let%bind () = execute database "PRAGMA foreign_keys = ON" in
        let%bind () = execute database "BEGIN IMMEDIATE" in
        let outcome =
          let%bind () = execute database migration in
          let%bind exists = workspace_exists database in
          if exists
          then Error Error.Already_initialized
          else (
            let%bind () = insert_migration database ~now in
            insert_workspace database ~slug ~now)
        in
        (match outcome with
         | Ok () ->
           let%map () = execute database "COMMIT" in
           ()
         | Error _ as error ->
           ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
           error)
      with
      | exn -> Error (Error.Database_error (Exn.to_string exn)))
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
;;
