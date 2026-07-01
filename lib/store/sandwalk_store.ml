open! Core

module Error = struct
  type t =
    | Already_initialized
    | Not_initialized
    | Unsupported_schema_version of int
    | Invalid_persisted_phase of string
    | Workspace_slug_mismatch of
        { expected : string
        ; actual : string
        }
    | Duplicate_plan_step of string
    | Plan_mutation_wrong_phase of Sandwalk_core.Phase.t
    | Empty_plan
    | Plan_validation_wrong_phase of Sandwalk_core.Phase.t
    | Database_error of string
  [@@deriving sexp_of]
end

module Stored_plan_step = struct
  type t =
    { key : Sandwalk_core.Plan_step.Key.t
    ; title : string
    ; required : bool
    ; position : int
    }

  let key t = t.key
  let title t = t.title
  let required t = t.required
  let position t = t.position
end

module Validate_plan_result = struct
  type t =
    { previous_schema_version : int
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; already_validated : bool
    ; steps : Stored_plan_step.t list
    }

  let previous_schema_version t = t.previous_schema_version
  let phase t = t.phase
  let revision t = t.revision
  let already_validated t = t.already_validated
  let steps t = t.steps
end

module Add_plan_step_result = struct
  type t =
    { previous_schema_version : int
    ; previous_phase : Sandwalk_core.Phase.t
    ; phase_path : Sandwalk_core.Phase.t list
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; steps : Stored_plan_step.t list
    }

  let previous_schema_version t = t.previous_schema_version
  let previous_phase t = t.previous_phase
  let phase_path t = t.phase_path
  let phase t = t.phase
  let revision t = t.revision
  let steps t = t.steps
end

module Workspace_status = struct
  type t =
    { slug : Sandwalk_core.Slug.t
    ; phase : Sandwalk_core.Phase.t
    ; schema_version : int
    }

  let slug t = t.slug
  let phase t = t.phase
  let schema_version t = t.schema_version
end

let current_schema_version = 3

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

let migration_v1 =
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

let migration_v2 =
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
INSERT INTO plan_metadata (singleton, revision) VALUES (1, 0);
PRAGMA user_version = 2;
|}
;;

let migration_v3 =
  {|
ALTER TABLE plan_metadata ADD COLUMN validated_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN validated_at TEXT;
PRAGMA user_version = 3;
|}
;;

let insert_migration database ~version ~now =
  with_statement
    database
    "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?1, ?2)"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = check database (Sqlite3.bind_int statement 1 version) in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let query_schema_version database =
  with_statement database "PRAGMA user_version" ~f:(fun statement ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
    | Sqlite3.Rc.DONE -> Error Error.Not_initialized
    | return_code ->
      check database return_code
      |> Result.map ~f:(fun () -> current_schema_version))
;;

let migrate database ~from_version ~now =
  let open Result.Let_syntax in
  if from_version < 0 || from_version > current_schema_version
  then Error (Error.Unsupported_schema_version from_version)
  else (
    let%bind () =
      if from_version < 1
      then (
        let%bind () = execute database migration_v1 in
        insert_migration database ~version:1 ~now)
      else Ok ()
    in
    if from_version < 2
    then (
      let%bind () = execute database migration_v2 in
      let%bind () = insert_migration database ~version:2 ~now in
      let%bind () = execute database migration_v3 in
      insert_migration database ~version:3 ~now)
    else if from_version < 3
    then (
      let%bind () = execute database migration_v3 in
      insert_migration database ~version:3 ~now)
    else Ok ())
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
          let%bind schema_version = query_schema_version database in
          let%bind () = migrate database ~from_version:schema_version ~now in
          let%bind exists = workspace_exists database in
          if exists
          then Error Error.Already_initialized
          else insert_workspace database ~slug ~now
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

let query_workspace database =
  with_statement
    database
    "SELECT slug, phase FROM workspaces WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        Ok (Sqlite3.column_text statement 0, Sqlite3.column_text statement 1)
      | Sqlite3.Rc.DONE -> Error Error.Not_initialized
      | return_code ->
        check database return_code
        |> Result.map ~f:(fun () -> assert false))
;;

let read_status
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          let%bind () =
            if schema_version >= 1 && schema_version <= current_schema_version
            then Ok ()
            else Error (Error.Unsupported_schema_version schema_version)
          in
          let%bind slug_text, phase_text = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind phase =
            Sandwalk_core.Phase.of_string phase_text
            |> Result.of_option
                 ~error:(Error.Invalid_persisted_phase phase_text)
          in
          Ok
            { Workspace_status.slug = expected_slug
            ; phase
            ; schema_version
            }
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let plan_step_exists database key =
  with_statement
    database
    "SELECT 1 FROM plan_steps WHERE step_key = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = bind_text database statement 1 key in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok true
      | Sqlite3.Rc.DONE -> Ok false
      | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let next_plan_position database =
  with_statement
    database
    "SELECT COALESCE(MAX(position), 0) + 1 FROM plan_steps"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE -> Ok 1
      | return_code -> check database return_code |> Result.map ~f:(Fn.const 1))
;;

let insert_plan_step database ~step ~position ~now =
  with_statement
    database
    {|
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES (?1, ?2, ?3, ?4, ?5)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.key step
           |> Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () =
        bind_text database statement 2 (Sandwalk_core.Plan_step.title step)
      in
      let%bind () = check database (Sqlite3.bind_int statement 3 position) in
      let%bind () =
        check
          database
          (Sqlite3.bind_int
             statement
             4
             (if Sandwalk_core.Plan_step.required step then 1 else 0))
      in
      let%bind () = bind_text database statement 5 now in
      step_done database statement)
;;

let update_phase database ~phase ~now =
  with_statement
    database
    "UPDATE workspaces SET phase = ?1, updated_at = ?2 WHERE singleton = 1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Phase.to_string phase)
      in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let increment_plan_revision database =
  let open Result.Let_syntax in
  let%bind () =
    execute
      database
      "UPDATE plan_metadata SET revision = revision + 1 WHERE singleton = 1"
  in
  with_statement
    database
    "SELECT revision FROM plan_metadata WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const 0))
;;

let query_plan_validation database =
  with_statement
    database
    "SELECT revision, validated_revision FROM plan_metadata WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        Ok
          ( Sqlite3.column_int statement 0
          , if Sqlite3.column_is_null statement 1
            then None
            else Some (Sqlite3.column_int statement 1) )
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const (0, None)))
;;

let mark_plan_validated database ~revision ~now =
  with_statement
    database
    {|
UPDATE plan_metadata
SET validated_revision = ?1, validated_at = ?2
WHERE singleton = 1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = check database (Sqlite3.bind_int statement 1 revision) in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let query_plan_steps database =
  let steps = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT step_key, title, required, position
FROM plan_steps
ORDER BY position
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some key; Some title; Some required; Some position |] ->
             let key =
               match Sandwalk_core.Plan_step.Key.of_string key with
               | Ok key -> key
               | Error _ -> failwith "Invalid persisted plan step key"
             in
             steps :=
               { Stored_plan_step.key = key
               ; title
               ; required = String.equal required "1"
               ; position = Int.of_string position
               }
               :: !steps
           | _ -> failwith "Invalid persisted plan step row"))
  in
  List.rev !steps
;;

let read_plan_steps ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 2
          then Ok []
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_plan_steps database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let add_plan_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind current_phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind phase_path =
              Sandwalk_core.Planning.transition_path current_phase
              |> Result.map_error ~f:(function
                | Sandwalk_core.Planning.Error.Wrong_phase phase ->
                  Error.Plan_mutation_wrong_phase phase)
            in
            let key =
              Sandwalk_core.Plan_step.key step
              |> Sandwalk_core.Plan_step.Key.to_string
            in
            let%bind exists = plan_step_exists database key in
            let%bind () =
              if exists
              then Error (Error.Duplicate_plan_step key)
              else Ok ()
            in
            let%bind position = next_plan_position database in
            let%bind () = insert_plan_step database ~step ~position ~now in
            let phase =
              List.last phase_path |> Option.value ~default:current_phase
            in
            let%bind () =
              List.fold_result
                phase_path
                ~init:current_phase
                ~f:(fun from into ->
                  Sandwalk_core.transition ~from ~into
                  |> Result.map_error ~f:(fun _ ->
                    Error.Plan_mutation_wrong_phase from))
              |> Result.map ~f:ignore
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase current_phase
              then Ok ()
              else update_phase database ~phase ~now
            in
            let%bind revision = increment_plan_revision database in
            let%map steps = query_plan_steps database in
            { Add_plan_step_result.previous_schema_version
            ; previous_phase = current_phase
            ; phase_path
            ; phase
            ; revision
            ; steps
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let validate_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Planning
              then Ok ()
              else Error (Error.Plan_validation_wrong_phase phase)
            in
            let%bind steps = query_plan_steps database in
            let%bind () =
              if List.is_empty steps then Error Error.Empty_plan else Ok ()
            in
            let%bind revision, validated_revision =
              query_plan_validation database
            in
            let already_validated =
              Option.value_map
                validated_revision
                ~default:false
                ~f:(Int.equal revision)
            in
            let%bind () =
              if already_validated
              then Ok ()
              else mark_plan_validated database ~revision ~now
            in
            Ok
              { Validate_plan_result.previous_schema_version
              ; phase
              ; revision
              ; already_validated
              ; steps
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;
