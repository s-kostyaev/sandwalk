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
    | Plan_not_validated
    | Plan_validation_stale of
        { validated_revision : int
        ; current_revision : int
        }
    | Plan_seal_wrong_phase of Sandwalk_core.Phase.t
    | Plan_step_not_found of string
    | Step_claim_wrong_phase of Sandwalk_core.Phase.t
    | Step_already_claimed of int64
    | Step_completed of string
    | Claim_id_collision
    | Invalid_step_state of string
    | Claim_not_found
    | Claim_not_active
    | Claim_expired of string
    | Search_wrong_phase of Sandwalk_core.Phase.t
    | Search_requires_claim
    | Hit_id_collision
    | Database_error of string
  [@@deriving sexp_of]
end

module Stored_hit = struct
  type t =
    { hit_id : Sandwalk_core.Hit_id.t
    ; position : int
    ; url : string
    ; title : string
    ; snippet : string
    }

  let hit_id t = t.hit_id
  let position t = t.position
  let url t = t.url
  let title t = t.title
  let snippet t = t.snippet
end

module Record_search_result = struct
  type t =
    { previous_schema_version : int
    ; hits : Stored_hit.t list
    ; step_key : Sandwalk_core.Plan_step.Key.t option
    ; lease_expires_unix_seconds : int64 option
    }

  let previous_schema_version t = t.previous_schema_version
  let hits t = t.hits
  let step_key t = t.step_key
  let lease_expires_unix_seconds t = t.lease_expires_unix_seconds
end

module Save_checkpoint_result = struct
  type t =
    { previous_schema_version : int
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; checkpoint_number : int
    ; lease_expires_unix_seconds : int64
    }

  let previous_schema_version t = t.previous_schema_version
  let step_key t = t.step_key
  let checkpoint_number t = t.checkpoint_number
  let lease_expires_unix_seconds t = t.lease_expires_unix_seconds
end

module Latest_checkpoint = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; summary : string
    ; next : string
    ; created_at : string
    }

  let step_key t = t.step_key
  let summary t = t.summary
  let next t = t.next
  let created_at t = t.created_at
end

module Claim_step_result = struct
  type t =
    { previous_schema_version : int
    ; claim_id : Sandwalk_core.Claim_id.t
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; attempt : int
    ; previous_state : Sandwalk_core.Step_state.t
    ; expired_active_claim : bool
    }

  let previous_schema_version t = t.previous_schema_version
  let claim_id t = t.claim_id
  let step_key t = t.step_key
  let attempt t = t.attempt
  let previous_state t = t.previous_state
  let expired_active_claim t = t.expired_active_claim
end

module Active_claim = struct
  type t =
    { claim_id : Sandwalk_core.Claim_id.t
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; attempt : int
    ; lease_expires_at : string
    }

  let claim_id t = t.claim_id
  let step_key t = t.step_key
  let attempt t = t.attempt
  let lease_expires_at t = t.lease_expires_at
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

module Seal_plan_result = struct
  type t =
    { previous_schema_version : int
    ; previous_phase : Sandwalk_core.Phase.t
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; already_sealed : bool
    ; steps : Stored_plan_step.t list
    }

  let previous_schema_version t = t.previous_schema_version
  let previous_phase t = t.previous_phase
  let phase t = t.phase
  let revision t = t.revision
  let already_sealed t = t.already_sealed
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

let current_schema_version = 7

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

let migration_v4 =
  {|
ALTER TABLE plan_metadata ADD COLUMN sealed_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN sealed_at TEXT;
PRAGMA user_version = 4;
|}
;;

let migration_v5 =
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
INSERT INTO step_executions (step_key, state, attempt)
SELECT step_key, 'pending', 0 FROM plan_steps;
PRAGMA user_version = 5;
|}
;;

let migration_v6 =
  {|
ALTER TABLE claims ADD COLUMN lease_duration_seconds INTEGER
  CHECK (lease_duration_seconds BETWEEN 30 AND 86400);
UPDATE claims
SET lease_duration_seconds = 900
WHERE lease_duration_seconds IS NULL;
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
PRAGMA user_version = 6;
|}
;;

let migration_v7 =
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
PRAGMA user_version = 7;
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
    let%bind () =
      if from_version < 2
      then (
        let%bind () = execute database migration_v2 in
        insert_migration database ~version:2 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 3
      then (
        let%bind () = execute database migration_v3 in
        insert_migration database ~version:3 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 4
      then (
        let%bind () = execute database migration_v4 in
        insert_migration database ~version:4 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 5
      then (
        let%bind () = execute database migration_v5 in
        insert_migration database ~version:5 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 6
      then (
        let%bind () = execute database migration_v6 in
        insert_migration database ~version:6 ~now)
      else Ok ()
    in
    if from_version < 7
    then (
      let%bind () = execute database migration_v7 in
      insert_migration database ~version:7 ~now)
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

let insert_step_execution database ~step =
  with_statement
    database
    {|
INSERT INTO step_executions (step_key, state, attempt)
VALUES (?1, 'pending', 0)
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

let query_plan_seal database =
  with_statement
    database
    {|
SELECT revision, validated_revision, sealed_revision
FROM plan_metadata
WHERE singleton = 1
|}
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let optional_int column =
          if Sqlite3.column_is_null statement column
          then None
          else Some (Sqlite3.column_int statement column)
        in
        Ok
          ( Sqlite3.column_int statement 0
          , optional_int 1
          , optional_int 2 )
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code
        |> Result.map ~f:(Fn.const (0, None, None)))
;;

let mark_plan_sealed database ~revision ~now =
  with_statement
    database
    {|
UPDATE plan_metadata
SET sealed_revision = ?1, sealed_at = ?2
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
            let%bind () = insert_step_execution database ~step in
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

let seal_plan
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
            let%bind previous_phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind steps = query_plan_steps database in
            let%bind () =
              if List.is_empty steps then Error Error.Empty_plan else Ok ()
            in
            let%bind revision, validated_revision, sealed_revision =
              query_plan_seal database
            in
            let already_sealed =
              Sandwalk_core.Phase.equal previous_phase Researching
              && Option.value_map
                   sealed_revision
                   ~default:false
                   ~f:(Int.equal revision)
            in
            let%bind () =
              if already_sealed
              then Ok ()
              else if not (Sandwalk_core.Phase.equal previous_phase Planning)
              then Error (Error.Plan_seal_wrong_phase previous_phase)
              else (
                match validated_revision with
                | None -> Error Error.Plan_not_validated
                | Some validated_revision
                  when not (Int.equal validated_revision revision) ->
                  Error
                    (Error.Plan_validation_stale
                       { validated_revision; current_revision = revision })
                | Some _ -> Ok ())
            in
            let phase = Sandwalk_core.Phase.Researching in
            let%bind () =
              if already_sealed
              then Ok ()
              else (
                let%bind _ =
                  Sandwalk_core.transition
                    ~from:previous_phase
                    ~into:phase
                  |> Result.map_error ~f:(fun _ ->
                    Error.Plan_seal_wrong_phase previous_phase)
                in
                let%bind () = mark_plan_sealed database ~revision ~now in
                update_phase database ~phase ~now)
            in
            Ok
              { Seal_plan_result.previous_schema_version
              ; previous_phase
              ; phase
              ; revision
              ; already_sealed
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

let query_step_execution database ~step_key =
  with_statement
    database
    {|
SELECT state, active_claim_id, lease_expires_unix_seconds, attempt
FROM step_executions
WHERE step_key = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let key = Sandwalk_core.Plan_step.Key.to_string step_key in
      let%bind () = bind_text database statement 1 key in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let state_text = Sqlite3.column_text statement 0 in
        let%map state =
          Sandwalk_core.Step_state.of_string state_text
          |> Result.of_option ~error:(Error.Invalid_step_state state_text)
        in
        let active_claim_id =
          if Sqlite3.column_is_null statement 1
          then None
          else Some (Sqlite3.column_text statement 1)
        in
        let lease_expires =
          if Sqlite3.column_is_null statement 2
          then None
          else Some (Sqlite3.column_int64 statement 2)
        in
        state, active_claim_id, lease_expires, Sqlite3.column_int statement 3
      | Sqlite3.Rc.DONE -> Error (Error.Plan_step_not_found key)
      | return_code ->
        check database return_code
        |> Result.map
             ~f:
               (Fn.const
                  (Sandwalk_core.Step_state.Pending, None, None, 0)))
;;

let claim_id_exists database claim_id =
  with_statement
    database
    "SELECT 1 FROM claims WHERE claim_id = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok true
      | Sqlite3.Rc.DONE -> Ok false
      | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let expire_claim database ~claim_id ~now =
  with_statement
    database
    {|
UPDATE claims
SET ended_at = ?1, end_reason = 'expired'
WHERE claim_id = ?2 AND ended_at IS NULL
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = bind_text database statement 1 now in
      let%bind () = bind_text database statement 2 claim_id in
      step_done database statement)
;;

let insert_claim
      database
      ~claim_id
      ~step_key
      ~attempt
      ~now
      ~lease_expires_at
      ~lease_expires_unix_seconds
      ~lease_duration_seconds
  =
  with_statement
    database
    {|
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds, lease_duration_seconds
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      let%bind () = check database (Sqlite3.bind_int statement 3 attempt) in
      let%bind () = bind_text database statement 4 now in
      let%bind () = bind_text database statement 5 lease_expires_at in
      let%bind () =
        check
          database
          (Sqlite3.bind_int64 statement 6 lease_expires_unix_seconds)
      in
      let%bind () =
        check database (Sqlite3.bind_int statement 7 lease_duration_seconds)
      in
      step_done database statement)
;;

let activate_claim
      database
      ~claim_id
      ~step_key
      ~attempt
      ~lease_expires_unix_seconds
  =
  with_statement
    database
    {|
UPDATE step_executions
SET state = 'claimed',
    active_claim_id = ?1,
    lease_expires_unix_seconds = ?2,
    attempt = ?3
WHERE step_key = ?4
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () =
        check
          database
          (Sqlite3.bind_int64 statement 2 lease_expires_unix_seconds)
      in
      let%bind () = check database (Sqlite3.bind_int statement 3 attempt) in
      let%bind () =
        bind_text
          database
          statement
          4
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      step_done database statement)
;;

let claim_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step_key
      ~claim_id
      ~now
      ~now_unix_seconds
      ~lease_expires_at
      ~lease_expires_unix_seconds
      ~lease_duration_seconds
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
              if
                Sandwalk_core.Phase.equal
                  phase
                  Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Step_claim_wrong_phase phase)
            in
            let%bind state, active_claim_id, active_expiry, previous_attempt =
              query_step_execution database ~step_key
            in
            let lease_expired =
              Option.value_map
                active_expiry
                ~default:false
                ~f:(fun expiry -> Int64.(expiry <= now_unix_seconds))
            in
            let%bind decision =
              Sandwalk_core.Claim_decision.decide ~state ~lease_expired
              |> Result.map_error ~f:(function
                | Sandwalk_core.Claim_decision.Error.Active_claim ->
                  Error.Step_already_claimed (Option.value_exn active_expiry)
                | Sandwalk_core.Claim_decision.Error.Step_completed ->
                  Error.Step_completed
                    (Sandwalk_core.Plan_step.Key.to_string step_key))
            in
            let%bind collision = claim_id_exists database claim_id in
            let%bind () =
              if collision then Error Error.Claim_id_collision else Ok ()
            in
            let%bind () =
              if decision.expired_active_claim
              then
                expire_claim
                  database
                  ~claim_id:(Option.value_exn active_claim_id)
                  ~now
              else Ok ()
            in
            let attempt = previous_attempt + 1 in
            let%bind () =
              insert_claim
                database
                ~claim_id
                ~step_key
                ~attempt
                ~now
                ~lease_expires_at
                ~lease_expires_unix_seconds
                ~lease_duration_seconds
            in
            let%bind () =
              activate_claim
                database
                ~claim_id
                ~step_key
                ~attempt
                ~lease_expires_unix_seconds
            in
            Ok
              { Claim_step_result.previous_schema_version
              ; claim_id
              ; step_key
              ; attempt
              ; previous_state = decision.previous_state
              ; expired_active_claim = decision.expired_active_claim
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

let query_active_claims database =
  let claims = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT c.claim_id, c.step_key, c.attempt, c.lease_expires_at
FROM step_executions e
JOIN claims c ON c.claim_id = e.active_claim_id
WHERE e.state = 'claimed'
ORDER BY c.step_key
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some claim_id; Some step_key; Some attempt; Some lease_expires_at |] ->
             let claim_id =
               Sandwalk_core.Claim_id.of_string claim_id |> Option.value_exn
             in
             let step_key =
               match Sandwalk_core.Plan_step.Key.of_string step_key with
               | Ok step_key -> step_key
               | Error _ -> failwith "Invalid persisted plan step key"
             in
             claims :=
               { Active_claim.claim_id = claim_id
               ; step_key
               ; attempt = Int.of_string attempt
               ; lease_expires_at
               }
               :: !claims
           | _ -> failwith "Invalid persisted active claim row"))
  in
  List.rev !claims
;;

let read_active_claims ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 5
          then Ok []
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_active_claims database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_claim_for_checkpoint database claim_id =
  with_statement
    database
    {|
SELECT c.step_key, e.state, e.active_claim_id,
       e.lease_expires_unix_seconds, c.lease_duration_seconds
FROM claims c
JOIN step_executions e ON e.step_key = c.step_key
WHERE c.claim_id = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let step_key_text = Sqlite3.column_text statement 0 in
        let%bind step_key =
          Sandwalk_core.Plan_step.Key.of_string step_key_text
          |> Result.map_error ~f:(fun _ ->
            Error.Database_error "Invalid persisted checkpoint step key")
        in
        let state_text = Sqlite3.column_text statement 1 in
        let%map state =
          Sandwalk_core.Step_state.of_string state_text
          |> Result.of_option ~error:(Error.Invalid_step_state state_text)
        in
        let active_claim_id =
          if Sqlite3.column_is_null statement 2
          then None
          else Some (Sqlite3.column_text statement 2)
        in
        let lease_expires =
          if Sqlite3.column_is_null statement 3
          then None
          else Some (Sqlite3.column_int64 statement 3)
        in
        let lease_duration =
          if Sqlite3.column_is_null statement 4
          then 900
          else Sqlite3.column_int statement 4
        in
        step_key, state, active_claim_id, lease_expires, lease_duration
      | Sqlite3.Rc.DONE -> Error Error.Claim_not_found
      | return_code ->
        check database return_code
        |> Result.map ~f:(fun () -> assert false))
;;

let expire_step_execution database ~step_key =
  with_statement
    database
    {|
UPDATE step_executions
SET state = 'expired',
    active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE step_key = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      step_done database statement)
;;

let next_checkpoint_number database ~step_key =
  with_statement
    database
    {|
SELECT COALESCE(MAX(checkpoint_number), 0) + 1
FROM checkpoints
WHERE step_key = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE -> Ok 1
      | return_code -> check database return_code |> Result.map ~f:(Fn.const 1))
;;

let insert_checkpoint
      database
      ~step_key
      ~claim_id
      ~checkpoint_number
      ~checkpoint
      ~summary_path
      ~summary_md5
      ~summary_size
      ~next_path
      ~next_md5
      ~next_size
      ~now
  =
  with_statement
    database
    {|
INSERT INTO checkpoints (
  step_key, claim_id, checkpoint_number, created_at, summary, next,
  summary_path, summary_md5, summary_size, next_path, next_md5, next_size
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let bind_int index value =
        check database (Sqlite3.bind_int statement index value)
      in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () = bind_int 3 checkpoint_number in
      let%bind () = bind_text database statement 4 now in
      let%bind () =
        bind_text database statement 5 (Sandwalk_core.Checkpoint.summary checkpoint)
      in
      let%bind () =
        bind_text database statement 6 (Sandwalk_core.Checkpoint.next checkpoint)
      in
      let%bind () = bind_text database statement 7 summary_path in
      let%bind () = bind_text database statement 8 summary_md5 in
      let%bind () = bind_int 9 summary_size in
      let%bind () = bind_text database statement 10 next_path in
      let%bind () = bind_text database statement 11 next_md5 in
      let%bind () = bind_int 12 next_size in
      step_done database statement)
;;

let renew_claim database ~claim_id ~step_key ~lease_expires_unix_seconds =
  let open Result.Let_syntax in
  let%bind () =
    with_statement
      database
      {|
UPDATE claims
SET lease_expires_unix_seconds = ?1,
    lease_expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', ?1, 'unixepoch')
WHERE claim_id = ?2
|}
      ~f:(fun statement ->
        let%bind () =
          check
            database
            (Sqlite3.bind_int64 statement 1 lease_expires_unix_seconds)
        in
        let%bind () =
          bind_text
            database
            statement
            2
            (Sandwalk_core.Claim_id.to_string claim_id)
        in
        step_done database statement)
  in
  with_statement
    database
    {|
UPDATE step_executions
SET lease_expires_unix_seconds = ?1
WHERE step_key = ?2 AND active_claim_id = ?3
|}
    ~f:(fun statement ->
      let%bind () =
        check
          database
          (Sqlite3.bind_int64 statement 1 lease_expires_unix_seconds)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      let%bind () =
        bind_text
          database
          statement
          3
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      step_done database statement)
;;

let save_checkpoint
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~checkpoint
      ~summary_path
      ~summary_md5
      ~summary_size
      ~next_path
      ~next_md5
      ~next_size
      ~now
      ~now_unix_seconds
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
            let%bind slug_text, _phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind step_key, state, active_claim_id, lease_expires, duration =
              query_claim_for_checkpoint database claim_id
            in
            let claim_text = Sandwalk_core.Claim_id.to_string claim_id in
            let%bind () =
              if
                Sandwalk_core.Step_state.equal
                  state
                  Sandwalk_core.Step_state.Claimed
                && Option.value_map
                     active_claim_id
                     ~default:false
                     ~f:(String.equal claim_text)
              then Ok ()
              else Error Error.Claim_not_active
            in
            let lease_expires = Option.value_exn lease_expires in
            if Int64.(lease_expires <= now_unix_seconds)
            then (
              let%bind () = expire_claim database ~claim_id:claim_text ~now in
              let%map () = expire_step_execution database ~step_key in
              `Expired step_key)
            else (
              let%bind checkpoint_number =
                next_checkpoint_number database ~step_key
              in
              let%bind () =
                insert_checkpoint
                  database
                  ~step_key
                  ~claim_id
                  ~checkpoint_number
                  ~checkpoint
                  ~summary_path
                  ~summary_md5
                  ~summary_size
                  ~next_path
                  ~next_md5
                  ~next_size
                  ~now
              in
              let lease_expires_unix_seconds =
                Int64.(now_unix_seconds + of_int duration)
              in
              let%map () =
                renew_claim
                  database
                  ~claim_id
                  ~step_key
                  ~lease_expires_unix_seconds
              in
              `Saved
                { Save_checkpoint_result.previous_schema_version
                ; step_key
                ; checkpoint_number
                ; lease_expires_unix_seconds
                })
          in
          (match outcome with
           | Ok (`Saved result) ->
             let%map () = execute database "COMMIT" in
             Ok result
           | Ok (`Expired step_key) ->
             let%map () = execute database "COMMIT" in
             Error
               (Error.Claim_expired
                  (Sandwalk_core.Plan_step.Key.to_string step_key))
           | Error error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             Ok (Error error))
          |> Result.join
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_latest_checkpoint database =
  with_statement
    database
    {|
SELECT step_key, summary, next, created_at
FROM checkpoints
ORDER BY checkpoint_id DESC
LIMIT 1
|}
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let step_key =
          Sqlite3.column_text statement 0
          |> Sandwalk_core.Plan_step.Key.of_string
          |> Result.ok
          |> Option.value_exn
        in
        Ok
          (Some
             { Latest_checkpoint.step_key
             ; summary = Sqlite3.column_text statement 1
             ; next = Sqlite3.column_text statement 2
             ; created_at = Sqlite3.column_text statement 3
             })
      | Sqlite3.Rc.DONE -> Ok None
      | return_code -> check database return_code |> Result.map ~f:(Fn.const None))
;;

let read_latest_checkpoint ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 6
          then Ok None
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_latest_checkpoint database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let insert_search_query
      database
      ~query
      ~phase
      ~claim_id
      ~step_key
      ~adapter
      ~now
  =
  with_statement
    database
    {|
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let bind_optional_text index value =
        check
          database
          (Sqlite3.bind
             statement
             index
             (Sqlite3.Data.opt_text value))
      in
      let%bind () = bind_text database statement 1 query in
      let%bind () =
        bind_text database statement 2 (Sandwalk_core.Phase.to_string phase)
      in
      let%bind () =
        bind_optional_text
          3
          (Option.map claim_id ~f:Sandwalk_core.Claim_id.to_string)
      in
      let%bind () =
        bind_optional_text
          4
          (Option.map step_key ~f:Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () = bind_text database statement 5 adapter in
      let%bind () = bind_text database statement 6 now in
      let%map () = step_done database statement in
      Sqlite3.last_insert_rowid database)
;;

let hit_id_exists database hit_id =
  with_statement database "SELECT 1 FROM search_hits WHERE hit_ref = ?1" ~f:(fun statement ->
    let open Result.Let_syntax in
    let%bind () =
      bind_text database statement 1 (Sandwalk_core.Hit_id.to_string hit_id)
    in
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok true
    | Sqlite3.Rc.DONE -> Ok false
    | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let insert_search_hit database ~query_id ~position (hit_id, url, title, snippet) =
  with_statement
    database
    {|
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Hit_id.to_string hit_id)
      in
      let%bind () = check database (Sqlite3.bind_int64 statement 2 query_id) in
      let%bind () = check database (Sqlite3.bind_int statement 3 position) in
      let%bind () = bind_text database statement 4 url in
      let%bind () = bind_text database statement 5 title in
      let%bind () = bind_text database statement 6 snippet in
      let%map () = step_done database statement in
      { Stored_hit.hit_id = hit_id; position; url; title; snippet })
;;

let record_search
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~query
      ~adapter
      ~hits
      ~now
      ~now_unix_seconds
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
            let%bind step_key, lease_expires_unix_seconds =
              match phase, claim_id with
              | Sandwalk_core.Phase.Reconnaissance, None -> Ok (None, None)
              | Sandwalk_core.Phase.Researching, None ->
                Error Error.Search_requires_claim
              | Sandwalk_core.Phase.Researching, Some claim_id ->
                let%bind step_key, state, active_claim_id, expiry, duration =
                  query_claim_for_checkpoint database claim_id
                in
                let claim_text = Sandwalk_core.Claim_id.to_string claim_id in
                let%bind () =
                  if
                    Sandwalk_core.Step_state.equal
                      state
                      Sandwalk_core.Step_state.Claimed
                    && Option.value_map
                         active_claim_id
                         ~default:false
                         ~f:(String.equal claim_text)
                  then Ok ()
                  else Error Error.Claim_not_active
                in
                let expiry = Option.value_exn expiry in
                let%bind () =
                  if Int64.(expiry <= now_unix_seconds)
                  then
                    Error
                      (Error.Claim_expired
                         (Sandwalk_core.Plan_step.Key.to_string step_key))
                  else Ok ()
                in
                Ok
                  ( Some step_key
                  , Some Int64.(now_unix_seconds + of_int duration) )
              | Sandwalk_core.Phase.Reconnaissance, Some _ ->
                Error Error.Claim_not_active
              | _ -> Error (Error.Search_wrong_phase phase)
            in
            let%bind () =
              List.fold_result hits ~init:() ~f:(fun () (hit_id, _, _, _) ->
                let%bind exists = hit_id_exists database hit_id in
                if exists then Error Error.Hit_id_collision else Ok ())
            in
            let%bind query_id =
              insert_search_query
                database
                ~query
                ~phase
                ~claim_id
                ~step_key
                ~adapter
                ~now
            in
            let%bind stored_hits =
              List.mapi hits ~f:(fun index hit ->
                insert_search_hit database ~query_id ~position:(index + 1) hit)
              |> Result.all
            in
            let%bind () =
              match claim_id, step_key, lease_expires_unix_seconds with
              | Some claim_id, Some step_key, Some expiry ->
                renew_claim
                  database
                  ~claim_id
                  ~step_key
                  ~lease_expires_unix_seconds:expiry
              | _ -> Ok ()
            in
            Ok
              { Record_search_result.previous_schema_version
              ; hits = stored_hits
              ; step_key
              ; lease_expires_unix_seconds
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
