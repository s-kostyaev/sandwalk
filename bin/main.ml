open! Core
open! Async

let version = "0.1.0-dev"

let about_command =
  Async.Command.async
    ~summary:"Print Sandwalk build information as a JSON response."
    (let%map_open.Command () = return () in
     fun () ->
       let result =
         `Assoc [ "name", `String "sandwalk"; "version", `String version ]
       in
       Sandwalk_protocol.Envelope.success ~result ()
       |> Sandwalk_protocol.Envelope.render
       |> print_endline;
       Deferred.unit)
;;

let parsed_arguments ~slug ~directory_prefix =
  `Assoc
    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
    ; "directory_prefix", `String directory_prefix
    ]
;;

let print_failure_and_exit ~code ~message =
  Sandwalk_protocol.Envelope.failure ~code ~message ()
  |> Sandwalk_protocol.Envelope.render
  |> print_endline;
  Shutdown.exit 1
;;

let init_command =
  Async.Command.async
    ~summary:"Create a new Sandwalk workspace."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let started_at = Time_float_unix.now () in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind invocation_id =
           In_thread.run (fun () ->
             Sandwalk_runtime.invocation_id ~now:started_at)
         in
         let%bind layout =
           Sandwalk_runtime.Workspace.create_layout ~directory_prefix ~slug
         in
         (match layout with
          | Error _ ->
            print_failure_and_exit
              ~code:"WORKSPACE_IO_ERROR"
              ~message:"Could not create workspace layout."
          | Ok workspace ->
            let%bind started =
              Sandwalk_runtime.Audit.append
                ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                (Sandwalk_protocol.Audit_event.create
                   ~invocation_id
                   ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                   ~kind:`Started
                   ~command:"init"
                   ~arguments
                   ~phase:None
                   ~raw_argv:(Sys.get_argv () |> Array.to_list)
                   ~state_changes:[]
                   ())
            in
            (match started with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () ->
               let%bind initialized =
                 In_thread.run (fun () ->
                   Sandwalk_store.initialize
                     ~database_path:
                       (Sandwalk_runtime.Workspace.database_path workspace)
                     ~slug
                     ~now:(Sandwalk_runtime.timestamp_utc started_at)
                     ())
               in
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let outcome, error_code =
                 match initialized with
                 | Ok () -> "success", None
                 | Error Sandwalk_store.Error.Already_initialized ->
                   "failure", Some "WORKSPACE_EXISTS"
                 | Error _ ->
                   "failure", Some "DATABASE_ERROR"
               in
               let%bind finished =
                 Sandwalk_runtime.Audit.append
                   ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                   (Sandwalk_protocol.Audit_event.create
                      ~invocation_id
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~kind:
                        (if String.equal outcome "success"
                         then `Finished
                         else `Failed)
                      ~command:"init"
                      ~arguments
                      ~phase:(Some "initialized")
                      ~raw_argv:(Sys.get_argv () |> Array.to_list)
                      ~state_changes:
                        (if String.equal outcome "success"
                         then
                           [ `Assoc
                               [ "entity", `String "workspace"
                               ; "from", `Null
                               ; "to", `String "initialized"
                               ]
                           ]
                         else [])
                      ~duration_ms
                      ~outcome
                      ?error_code
                      ())
               in
               (match finished with
                | Error _ ->
                  print_failure_and_exit
                    ~code:"AUDIT_LOG_ERROR"
                    ~message:"Could not append workspace audit log."
                | Ok () ->
                  (match initialized with
                   | Ok () ->
                     let result =
                       `Assoc
                         [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                         ; "phase", `String "initialized"
                         ; ( "schema_version"
                           , `Int Sandwalk_store.current_schema_version )
                         ]
                     in
                     Sandwalk_protocol.Envelope.success ~result ()
                     |> Sandwalk_protocol.Envelope.render
                     |> print_endline;
                     Deferred.unit
                   | Error Sandwalk_store.Error.Already_initialized ->
                     print_failure_and_exit
                       ~code:"WORKSPACE_EXISTS"
                       ~message:"Workspace already exists."
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"DATABASE_ERROR"
                       ~message:"Could not initialize workspace database.")))))
;;

let status_error = function
  | Sandwalk_store.Error.Not_initialized ->
    "WORKSPACE_NOT_INITIALIZED", "Workspace database is not initialized."
  | Unsupported_schema_version _ ->
    "SCHEMA_VERSION_UNSUPPORTED", "Workspace schema version is not supported."
  | Invalid_persisted_phase _ | Workspace_slug_mismatch _ ->
    "WORKSPACE_INVALID", "Workspace state is invalid."
  | Database_error _ ->
    "DATABASE_ERROR", "Could not read workspace database."
  | Already_initialized
  | Duplicate_plan_step _
  | Plan_mutation_wrong_phase _
  | Empty_plan
  | Plan_validation_wrong_phase _
  | Plan_not_validated
  | Plan_validation_stale _
  | Plan_seal_wrong_phase _
  | Plan_step_not_found _
  | Step_claim_wrong_phase _
  | Step_already_claimed _
  | Step_completed _
  | Claim_id_collision
  | Invalid_step_state _ ->
    "DATABASE_ERROR", "Could not read workspace database."
;;

let status_command =
  Async.Command.async
    ~summary:"Print the current state of a Sandwalk workspace."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let%bind started =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                  ~kind:`Started
                  ~command:"status"
                  ~arguments
                  ~phase:None
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes:[]
                  ())
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind status =
               In_thread.run (fun () ->
                 Sandwalk_store.read_status
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ())
             in
             let phase =
               Result.ok status
               |> Option.map ~f:(fun status ->
                 Sandwalk_store.Workspace_status.phase status
                 |> Sandwalk_core.Phase.to_string)
             in
             let error =
               Result.error status |> Option.map ~f:status_error
             in
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind finished =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                    ~kind:(if Result.is_ok status then `Finished else `Failed)
                    ~command:"status"
                    ~arguments
                    ~phase
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes:[]
                    ~duration_ms
                    ~outcome:
                      (if Result.is_ok status then "success" else "failure")
                    ?error_code:(Option.map error ~f:fst)
                    ())
             in
             (match finished with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                (match status with
                 | Error error ->
                   let code, message = status_error error in
                   print_failure_and_exit ~code ~message
                 | Ok status ->
                   let result =
                     `Assoc
                       [ ( "slug"
                         , `String
                             (Sandwalk_store.Workspace_status.slug status
                              |> Sandwalk_core.Slug.to_string) )
                       ; ( "phase"
                         , `String
                             (Sandwalk_store.Workspace_status.phase status
                              |> Sandwalk_core.Phase.to_string) )
                       ; ( "schema_version"
                         , `Int
                             (Sandwalk_store.Workspace_status.schema_version
                                status) )
                       ]
                   in
                   Sandwalk_protocol.Envelope.success ~result ()
                   |> Sandwalk_protocol.Envelope.render
                   |> print_endline;
                   Deferred.unit))))
;;

let resume_command =
  Async.Command.async
    ~summary:"Regenerate a bounded recovery pack from durable workspace state."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"resume"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes:[]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind status =
               In_thread.run (fun () ->
                 Sandwalk_store.read_status
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ())
             in
             (match status with
              | Error error ->
                let code, message = status_error error in
                fail_with_audit ~phase:None ~code ~message
              | Ok status ->
                let phase =
                  Sandwalk_store.Workspace_status.phase status
                in
                let%bind (plan_steps, active_claims), history =
                  Deferred.both
                    (Deferred.both
                       (In_thread.run (fun () ->
                          Sandwalk_store.read_plan_steps
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path workspace)
                            ()))
                       (In_thread.run (fun () ->
                          Sandwalk_store.read_active_claims
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path workspace)
                            ())))
                    (Sandwalk_runtime.Audit.read_history
                       ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                       ~exclude_invocation_id:invocation_id)
                in
                (match plan_steps, active_claims, history with
                 | Error _, _, _ | _, Error _, _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_STATE_ERROR"
                     ~message:"Could not read durable recovery state."
                 | _, _, Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_LOG_ERROR"
                     ~message:"Could not read workspace audit history."
                 | Ok plan_steps, Ok active_claims, Ok history ->
                   let recent_commands =
                     Sandwalk_runtime.Audit.recent_commands history
                     |> List.map ~f:(fun summary ->
                       ( Sandwalk_runtime.Audit.summary_command summary
                       , Sandwalk_runtime.Audit.summary_outcome summary
                       , Sandwalk_runtime.Audit.summary_error_code summary ))
                   in
                   let next_command =
                     sprintf
                       "sandwalk status --slug %s --directory-prefix %s"
                       (Sandwalk_protocol.Shell_command.quote
                          (Sandwalk_core.Slug.to_string slug))
                       (Sandwalk_protocol.Shell_command.quote directory_prefix)
                   in
                   let pack =
                     Sandwalk_core.Resume_pack.render
                       ~slug
                       ~phase
                       ~schema_version:
                         (Sandwalk_store.Workspace_status.schema_version status)
                       ~plan_steps:
                         (List.map plan_steps ~f:(fun stored ->
                            ( Sandwalk_store.Stored_plan_step.key stored
                            , Sandwalk_store.Stored_plan_step.title stored
                            , Sandwalk_store.Stored_plan_step.required stored
                            , Sandwalk_store.Stored_plan_step.position stored )))
                       ~active_claims:
                         (List.map active_claims ~f:(fun active ->
                            ( Sandwalk_store.Active_claim.step_key active
                            , Sandwalk_store.Active_claim.claim_id active
                            , Sandwalk_store.Active_claim.attempt active
                            , Sandwalk_store.Active_claim.lease_expires_at
                                active )))
                       ~recent_commands
                       ~unmatched_commands:
                         (Sandwalk_runtime.Audit.unmatched_commands history)
                       ~events_path:
                         (Sandwalk_runtime.Workspace.events_path workspace)
                       ~next_command
                   in
                   (match pack with
                    | Error Sandwalk_core.Resume_pack.Error.Too_large ->
                      fail_with_audit
                        ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                        ~code:"RESUME_PACK_TOO_LARGE"
                        ~message:"Recovery data exceeds the resume pack limit."
                    | Ok pack ->
                      let resume_path =
                        Sandwalk_runtime.Workspace.resume_path workspace
                      in
                      let%bind written =
                        Sandwalk_runtime.Atomic_file.write
                          ~path:resume_path
                          ~temporary_suffix:invocation_id
                          pack
                      in
                      (match written with
                       | Error _ ->
                         fail_with_audit
                           ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                           ~code:"WORKSPACE_IO_ERROR"
                           ~message:"Could not write workspace resume pack."
                       | Ok () ->
                         let finished_at = Time_float_unix.now () in
                         let duration_ms =
                           Time_float.diff finished_at started_at
                           |> Time_float.Span.to_ms
                           |> Float.iround_nearest_exn
                         in
                         let%bind logged =
                           append_event
                             ~kind:`Finished
                             ~timestamp:
                               (Sandwalk_runtime.timestamp_utc finished_at)
                             ~phase:
                               (Some (Sandwalk_core.Phase.to_string phase))
                             ~duration_ms
                             ~outcome:"success"
                             ()
                         in
                         (match logged with
                          | Error _ ->
                            print_failure_and_exit
                              ~code:"AUDIT_LOG_ERROR"
                              ~message:"Could not append workspace audit log."
                          | Ok () ->
                            let result =
                              `Assoc
                                [ ( "slug"
                                  , `String
                                      (Sandwalk_core.Slug.to_string slug) )
                                ; ( "phase"
                                  , `String
                                      (Sandwalk_core.Phase.to_string phase) )
                                ; "resume_path", `String resume_path
                                ]
                            in
                            Sandwalk_protocol.Envelope.success ~result ()
                            |> Sandwalk_protocol.Envelope.render
                            |> print_endline;
                            Deferred.unit)))))))
;;

let plan_error = function
  | Sandwalk_store.Error.Duplicate_plan_step key ->
    "PLAN_STEP_EXISTS", sprintf "Plan step %S already exists." key
  | Plan_mutation_wrong_phase _ ->
    "PLAN_MUTATION_NOT_ALLOWED", "Plan cannot be changed in the current phase."
  | Empty_plan -> "PLAN_EMPTY", "Plan must contain at least one step."
  | Plan_validation_wrong_phase _ ->
    "PLAN_VALIDATION_NOT_ALLOWED", "Plan cannot be validated in the current phase."
  | Plan_not_validated ->
    "PLAN_NOT_VALIDATED", "Plan must be validated before sealing."
  | Plan_validation_stale _ ->
    "PLAN_VALIDATION_STALE", "Plan changed after its last validation."
  | Plan_seal_wrong_phase _ ->
    "PLAN_SEAL_NOT_ALLOWED", "Plan cannot be sealed in the current phase."
  | error -> status_error error
;;

let plan_add_step_command =
  Async.Command.async
    ~summary:"Append a step to the workspace research plan."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and key_text =
       flag "--key" (required string) ~doc:"KEY Human-readable plan step key"
     and title =
       flag "--title" (required string) ~doc:"TITLE Plan step title"
     and optional =
       flag "--optional" no_arg ~doc:" Mark this plan step as optional"
     in
     fun () ->
       match
         ( Sandwalk_core.Slug.of_string slug_text
         , Sandwalk_core.Plan_step.Key.of_string key_text )
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok key ->
         (match Sandwalk_core.Plan_step.create ~key ~title ~required:(not optional) with
          | Error error ->
            print_failure_and_exit
              ~code:"INVALID_PLAN_STEP"
              ~message:(Sandwalk_core.Plan_step.Error.message error)
          | Ok step ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
            in
            let arguments =
              `Assoc
                [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                ; "directory_prefix", `String directory_prefix
                ; ( "key"
                  , `String
                      (Sandwalk_core.Plan_step.Key.to_string
                         (Sandwalk_core.Plan_step.key step)) )
                ; "title", `String (Sandwalk_core.Plan_step.title step)
                ; "required", `Bool (Sandwalk_core.Plan_step.required step)
                ]
            in
            let%bind database_exists =
              Async.Sys.file_exists_exn
                (Sandwalk_runtime.Workspace.database_path workspace)
            in
            if not database_exists
            then
              print_failure_and_exit
                ~code:"WORKSPACE_NOT_FOUND"
                ~message:"Workspace does not exist."
            else (
              let started_at = Time_float_unix.now () in
              let%bind invocation_id =
                In_thread.run (fun () ->
                  Sandwalk_runtime.invocation_id ~now:started_at)
              in
              let append_event
                    ~kind
                    ~timestamp
                    ~phase
                    ~state_changes
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ()
                =
                Sandwalk_runtime.Audit.append
                  ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                  (Sandwalk_protocol.Audit_event.create
                     ~invocation_id
                     ~timestamp
                     ~kind
                     ~command:"plan add-step"
                     ~arguments
                     ~phase
                     ~raw_argv:(Sys.get_argv () |> Array.to_list)
                     ~state_changes
                     ?duration_ms
                     ?outcome
                     ?error_code
                     ())
              in
              let fail_with_audit ~phase ~state_changes ~code ~message =
                let finished_at = Time_float_unix.now () in
                let duration_ms =
                  Time_float.diff finished_at started_at
                  |> Time_float.Span.to_ms
                  |> Float.iround_nearest_exn
                in
                let%bind logged =
                  append_event
                    ~kind:`Failed
                    ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                    ~phase
                    ~state_changes
                    ~duration_ms
                    ~outcome:"failure"
                    ~error_code:code
                    ()
                in
                match logged with
                | Error _ ->
                  print_failure_and_exit
                    ~code:"AUDIT_LOG_ERROR"
                    ~message:"Could not append workspace audit log."
                | Ok () -> print_failure_and_exit ~code ~message
              in
              let%bind started =
                append_event
                  ~kind:`Started
                  ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                  ~phase:None
                  ~state_changes:[]
                  ()
              in
              match started with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                let%bind added =
                  In_thread.run (fun () ->
                    Sandwalk_store.add_plan_step
                      ~database_path:
                        (Sandwalk_runtime.Workspace.database_path workspace)
                      ~expected_slug:slug
                      ~step
                      ~now:(Sandwalk_runtime.timestamp_utc started_at)
                      ())
                in
                (match added with
                 | Error error ->
                   let code, message = plan_error error in
                   let phase =
                     match error with
                     | Sandwalk_store.Error.Plan_mutation_wrong_phase phase ->
                       Some (Sandwalk_core.Phase.to_string phase)
                     | _ -> None
                   in
                   fail_with_audit ~phase ~state_changes:[] ~code ~message
                 | Ok added ->
                   let previous_phase =
                     Sandwalk_store.Add_plan_step_result.previous_phase added
                   in
                   let _, phase_changes =
                     Sandwalk_store.Add_plan_step_result.phase_path added
                     |> List.fold
                          ~init:(previous_phase, [])
                          ~f:(fun (from, changes) into ->
                            ( into
                            , changes
                              @ [ `Assoc
                                    [ "entity", `String "workspace.phase"
                                    ; ( "from"
                                      , `String
                                          (Sandwalk_core.Phase.to_string from) )
                                    ; ( "to"
                                      , `String
                                          (Sandwalk_core.Phase.to_string into) )
                                    ]
                                ] ))
                   in
                   let state_changes =
                     let previous_schema_version =
                       Sandwalk_store.Add_plan_step_result.previous_schema_version
                         added
                     in
                     (if previous_schema_version
                         < Sandwalk_store.current_schema_version
                      then
                        [ `Assoc
                            [ "entity", `String "workspace.schema"
                            ; "from", `Int previous_schema_version
                            ; ( "to"
                              , `Int Sandwalk_store.current_schema_version )
                            ]
                        ]
                      else [])
                     @ phase_changes
                     @ [ `Assoc
                           [ "entity", `String "plan.step"
                           ; "from", `Null
                           ; ( "to"
                             , `String
                                 (Sandwalk_core.Plan_step.Key.to_string
                                    (Sandwalk_core.Plan_step.key step)) )
                           ]
                       ]
                   in
                   let phase =
                     Sandwalk_store.Add_plan_step_result.phase added
                   in
                   let steps =
                     Sandwalk_store.Add_plan_step_result.steps added
                   in
                   let revision =
                     Sandwalk_store.Add_plan_step_result.revision added
                   in
                   let projection =
                     Sandwalk_core.Plan_projection.render
                       ~phase
                       ~revision
                       ~validated:false
                       ~sealed:false
                       ~steps:
                         (List.map steps ~f:(fun stored ->
                            ( Sandwalk_store.Stored_plan_step.key stored
                            , Sandwalk_store.Stored_plan_step.title stored
                            , Sandwalk_store.Stored_plan_step.required stored
                            , Sandwalk_store.Stored_plan_step.position stored )))
                   in
                   let plan_path =
                     Sandwalk_runtime.Workspace.research_plan_path workspace
                   in
                   let%bind written =
                     Sandwalk_runtime.Atomic_file.write_versioned
                       ~path:plan_path
                       ~lock_path:
                         (Sandwalk_runtime.Workspace.research_plan_lock_path
                            workspace)
                       ~temporary_suffix:invocation_id
                       ~version:
                         (Sandwalk_core.Plan_projection.version
                            ~revision
                            ~validated:false
                            ~sealed:false)
                       projection
                   in
                   (match written with
                    | Error _ ->
                      fail_with_audit
                        ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                        ~state_changes
                        ~code:"WORKSPACE_IO_ERROR"
                        ~message:"Could not write research plan projection."
                    | Ok () ->
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                          ~state_changes
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let stored =
                           List.find_exn steps ~f:(fun stored ->
                             String.equal
                               (Sandwalk_store.Stored_plan_step.key stored
                                |> Sandwalk_core.Plan_step.Key.to_string)
                               (Sandwalk_core.Plan_step.key step
                                |> Sandwalk_core.Plan_step.Key.to_string))
                         in
                         let result =
                           `Assoc
                             [ ( "key"
                               , `String
                                   (Sandwalk_core.Plan_step.key step
                                    |> Sandwalk_core.Plan_step.Key.to_string) )
                             ; ( "title"
                               , `String
                                   (Sandwalk_core.Plan_step.title step) )
                             ; ( "required"
                               , `Bool
                                   (Sandwalk_core.Plan_step.required step) )
                             ; ( "position"
                               , `Int
                                   (Sandwalk_store.Stored_plan_step.position
                                      stored) )
                             ; ( "phase"
                               , `String
                                   (Sandwalk_core.Phase.to_string phase) )
                             ; "plan_path", `String plan_path
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let plan_validate_command =
  Async.Command.async
    ~summary:"Validate and record the current plan revision."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan validate"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~state_changes:[]
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ~state_changes:[]
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind validated =
               In_thread.run (fun () ->
                 Sandwalk_store.validate_plan
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ~now:(Sandwalk_runtime.timestamp_utc started_at)
                   ())
             in
             (match validated with
              | Error error ->
                let code, message = plan_error error in
                let phase =
                  match error with
                  | Sandwalk_store.Error.Plan_validation_wrong_phase phase ->
                    Some (Sandwalk_core.Phase.to_string phase)
                  | _ -> None
                in
                fail_with_audit ~phase ~code ~message
              | Ok validated ->
                let phase =
                  Sandwalk_store.Validate_plan_result.phase validated
                in
                let revision =
                  Sandwalk_store.Validate_plan_result.revision validated
                in
                let already_validated =
                  Sandwalk_store.Validate_plan_result.already_validated validated
                in
                let previous_schema_version =
                  Sandwalk_store.Validate_plan_result.previous_schema_version
                    validated
                in
                let state_changes =
                  (if previous_schema_version
                      < Sandwalk_store.current_schema_version
                   then
                     [ `Assoc
                         [ "entity", `String "workspace.schema"
                         ; "from", `Int previous_schema_version
                         ; "to", `Int Sandwalk_store.current_schema_version
                         ]
                     ]
                   else [])
                  @ if already_validated
                    then []
                    else
                      [ `Assoc
                          [ "entity", `String "plan.validation"
                          ; "from", `Null
                          ; "to", `Int revision
                          ]
                      ]
                in
                let steps =
                  Sandwalk_store.Validate_plan_result.steps validated
                in
                let projection =
                  Sandwalk_core.Plan_projection.render
                    ~phase
                    ~revision
                    ~validated:true
                    ~sealed:false
                    ~steps:
                      (List.map steps ~f:(fun stored ->
                         ( Sandwalk_store.Stored_plan_step.key stored
                         , Sandwalk_store.Stored_plan_step.title stored
                         , Sandwalk_store.Stored_plan_step.required stored
                         , Sandwalk_store.Stored_plan_step.position stored )))
                in
                let plan_path =
                  Sandwalk_runtime.Workspace.research_plan_path workspace
                in
                let%bind written =
                  Sandwalk_runtime.Atomic_file.write_versioned
                    ~path:plan_path
                    ~lock_path:
                      (Sandwalk_runtime.Workspace.research_plan_lock_path workspace)
                    ~temporary_suffix:invocation_id
                    ~version:
                      (Sandwalk_core.Plan_projection.version
                         ~revision
                         ~validated:true
                         ~sealed:false)
                    projection
                in
                (match written with
                 | Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"WORKSPACE_IO_ERROR"
                     ~message:"Could not write research plan projection."
                 | Ok () ->
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                       ~state_changes
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let result =
                        `Assoc
                          [ "revision", `Int revision
                          ; "validated", `Bool true
                          ; "already_validated", `Bool already_validated
                          ; "phase", `String (Sandwalk_core.Phase.to_string phase)
                          ; "plan_path", `String plan_path
                          ]
                      in
                      Sandwalk_protocol.Envelope.success ~result ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let plan_seal_command =
  Async.Command.async
    ~summary:"Seal the validated plan and begin research."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan seal"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~state_changes ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~state_changes
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ~state_changes:[]
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind sealed =
               In_thread.run (fun () ->
                 Sandwalk_store.seal_plan
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ~now:(Sandwalk_runtime.timestamp_utc started_at)
                   ())
             in
             (match sealed with
              | Error error ->
                let code, message = plan_error error in
                let phase =
                  match error with
                  | Sandwalk_store.Error.Plan_seal_wrong_phase phase ->
                    Some (Sandwalk_core.Phase.to_string phase)
                  | _ -> None
                in
                fail_with_audit ~phase ~state_changes:[] ~code ~message
              | Ok sealed ->
                let previous_schema_version =
                  Sandwalk_store.Seal_plan_result.previous_schema_version sealed
                in
                let previous_phase =
                  Sandwalk_store.Seal_plan_result.previous_phase sealed
                in
                let phase = Sandwalk_store.Seal_plan_result.phase sealed in
                let revision =
                  Sandwalk_store.Seal_plan_result.revision sealed
                in
                let already_sealed =
                  Sandwalk_store.Seal_plan_result.already_sealed sealed
                in
                let state_changes =
                  (if previous_schema_version
                      < Sandwalk_store.current_schema_version
                   then
                     [ `Assoc
                         [ "entity", `String "workspace.schema"
                         ; "from", `Int previous_schema_version
                         ; "to", `Int Sandwalk_store.current_schema_version
                         ]
                     ]
                   else [])
                  @ if already_sealed
                    then []
                    else
                      [ `Assoc
                          [ "entity", `String "plan.sealed"
                          ; "from", `Null
                          ; "to", `Int revision
                          ]
                      ; `Assoc
                          [ "entity", `String "workspace.phase"
                          ; ( "from"
                            , `String
                                (Sandwalk_core.Phase.to_string previous_phase) )
                          ; "to", `String (Sandwalk_core.Phase.to_string phase)
                          ]
                      ]
                in
                let steps = Sandwalk_store.Seal_plan_result.steps sealed in
                let projection =
                  Sandwalk_core.Plan_projection.render
                    ~phase
                    ~revision
                    ~validated:true
                    ~sealed:true
                    ~steps:
                      (List.map steps ~f:(fun stored ->
                         ( Sandwalk_store.Stored_plan_step.key stored
                         , Sandwalk_store.Stored_plan_step.title stored
                         , Sandwalk_store.Stored_plan_step.required stored
                         , Sandwalk_store.Stored_plan_step.position stored )))
                in
                let plan_path =
                  Sandwalk_runtime.Workspace.research_plan_path workspace
                in
                let projection_version =
                  Sandwalk_core.Plan_projection.version
                    ~revision
                    ~validated:true
                    ~sealed:true
                in
                let%bind written =
                  Sandwalk_runtime.Atomic_file.write_versioned
                    ~path:plan_path
                    ~lock_path:
                      (Sandwalk_runtime.Workspace.research_plan_lock_path workspace)
                    ~temporary_suffix:invocation_id
                    ~version:projection_version
                    projection
                in
                (match written with
                 | Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~state_changes
                     ~code:"WORKSPACE_IO_ERROR"
                     ~message:"Could not write research plan projection."
                 | Ok () ->
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                       ~state_changes
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let result =
                        `Assoc
                          [ "revision", `Int revision
                          ; "sealed", `Bool true
                          ; "already_sealed", `Bool already_sealed
                          ; "phase", `String (Sandwalk_core.Phase.to_string phase)
                          ; "plan_path", `String plan_path
                          ]
                      in
                      Sandwalk_protocol.Envelope.success ~result ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let plan_command =
  Async.Command.group
    ~summary:"Manage the canonical research plan."
    [ "add-step", plan_add_step_command
    ; "seal", plan_seal_command
    ; "validate", plan_validate_command
    ]
;;

let claim_error = function
  | Sandwalk_store.Error.Plan_step_not_found key ->
    "PLAN_STEP_NOT_FOUND", sprintf "Plan step %S does not exist." key
  | Step_claim_wrong_phase _ ->
    "STEP_CLAIM_NOT_ALLOWED", "Steps can only be claimed while researching."
  | Step_already_claimed _ ->
    "STEP_ALREADY_CLAIMED", "Plan step already has an active claim."
  | Step_completed key ->
    "STEP_COMPLETED", sprintf "Plan step %S is already completed." key
  | Claim_id_collision ->
    "CLAIM_ID_COLLISION", "Could not allocate a unique claim identifier."
  | error -> status_error error
;;

let step_claim_command =
  Async.Command.async
    ~summary:"Acquire a temporary lease for one plan step."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and step_text =
       flag "--step" (required string) ~doc:"KEY Plan step key"
     and lease_seconds =
       flag
         "--lease-seconds"
         (optional_with_default 900 int)
         ~doc:"SECONDS Lease duration from 30 to 86400 seconds"
     in
     fun () ->
       match
         ( Sandwalk_core.Slug.of_string slug_text
         , Sandwalk_core.Plan_step.Key.of_string step_text )
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok step_key ->
         if lease_seconds < 30 || lease_seconds > 86_400
         then
           print_failure_and_exit
             ~code:"INVALID_LEASE"
             ~message:"Lease duration must be between 30 and 86400 seconds."
         else (
           let directory_prefix =
             Sandwalk_runtime.resolve_directory_prefix
               ~command_line:directory_prefix
           in
           let workspace =
             Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; ( "step"
                 , `String
                     (Sandwalk_core.Plan_step.Key.to_string step_key) )
               ; "lease_seconds", `Int lease_seconds
               ]
           in
           let%bind database_exists =
             Async.Sys.file_exists_exn
               (Sandwalk_runtime.Workspace.database_path workspace)
           in
           if not database_exists
           then
             print_failure_and_exit
               ~code:"WORKSPACE_NOT_FOUND"
               ~message:"Workspace does not exist."
           else (
             let started_at = Time_float_unix.now () in
             let lease_expires =
               Time_float.add
                 started_at
                 (Time_float.Span.of_sec (Float.of_int lease_seconds))
             in
             let now_unix_seconds =
               Time_float.to_span_since_epoch started_at
               |> Time_float.Span.to_sec
               |> Float.iround_down_exn
               |> Int64.of_int
             in
             let lease_expires_unix_seconds =
               Int64.(now_unix_seconds + of_int lease_seconds)
             in
             let lease_expires_at =
               Sandwalk_runtime.timestamp_utc lease_expires
             in
             let%bind invocation_id =
               In_thread.run (fun () ->
                 Sandwalk_runtime.invocation_id ~now:started_at)
             in
             let append_event
                   ~kind
                   ~timestamp
                   ~phase
                   ~state_changes
                   ?claim
                   ?created_references
                   ?duration_ms
                   ?outcome
                   ?error_code
                   ()
               =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp
                    ~kind
                    ~command:"step claim"
                    ~arguments
                    ~phase
                    ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes
                    ?claim
                    ?created_references
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ())
             in
             let fail_with_audit ~phase ~code ~message =
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let%bind logged =
                 append_event
                   ~kind:`Failed
                   ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                   ~phase
                   ~state_changes:[]
                   ~duration_ms
                   ~outcome:"failure"
                   ~error_code:code
                   ()
               in
               match logged with
               | Error _ ->
                 print_failure_and_exit
                   ~code:"AUDIT_LOG_ERROR"
                   ~message:"Could not append workspace audit log."
               | Ok () -> print_failure_and_exit ~code ~message
             in
             let%bind started =
               append_event
                 ~kind:`Started
                 ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                 ~phase:None
                 ~state_changes:[]
                 ()
             in
             match started with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () ->
               let rec allocate retries =
                 let%bind claim_id =
                   In_thread.run Sandwalk_runtime.claim_id
                 in
                 let%bind result =
                   In_thread.run (fun () ->
                     Sandwalk_store.claim_step
                       ~database_path:
                         (Sandwalk_runtime.Workspace.database_path workspace)
                       ~expected_slug:slug
                       ~step_key
                       ~claim_id
                       ~now:(Sandwalk_runtime.timestamp_utc started_at)
                       ~now_unix_seconds
                       ~lease_expires_at
                       ~lease_expires_unix_seconds
                       ())
                 in
                 match result with
                 | Error Sandwalk_store.Error.Claim_id_collision
                   when retries > 0 -> allocate (retries - 1)
                 | result -> Deferred.return result
               in
               let%bind claimed = allocate 2 in
               (match claimed with
                | Error error ->
                  let code, message = claim_error error in
                  let phase =
                    match error with
                    | Sandwalk_store.Error.Step_claim_wrong_phase phase ->
                      Some (Sandwalk_core.Phase.to_string phase)
                    | _ -> Some "researching"
                  in
                  fail_with_audit ~phase ~code ~message
                | Ok claimed ->
                  let claim_id =
                    Sandwalk_store.Claim_step_result.claim_id claimed
                    |> Sandwalk_core.Claim_id.to_string
                  in
                  let previous_state =
                    Sandwalk_store.Claim_step_result.previous_state claimed
                  in
                  let previous_schema_version =
                    Sandwalk_store.Claim_step_result.previous_schema_version
                      claimed
                  in
                  let state_changes =
                    (if previous_schema_version
                        < Sandwalk_store.current_schema_version
                     then
                       [ `Assoc
                           [ "entity", `String "workspace.schema"
                           ; "from", `Int previous_schema_version
                           ; "to", `Int Sandwalk_store.current_schema_version
                           ]
                       ]
                     else [])
                    @ [ `Assoc
                          [ ( "entity"
                            , `String
                                ("step."
                                 ^ Sandwalk_core.Plan_step.Key.to_string step_key
                                 ^ ".state") )
                          ; ( "from"
                            , `String
                                (Sandwalk_core.Step_state.to_string previous_state)
                            )
                          ; "to", `String "claimed"
                          ]
                      ]
                  in
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Finished
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "researching")
                      ~state_changes
                      ~claim:claim_id
                      ~created_references:[ claim_id ]
                      ~duration_ms
                      ~outcome:"success"
                      ()
                  in
                  (match logged with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () ->
                     let result =
                       `Assoc
                         [ "claim", `String claim_id
                         ; ( "step"
                           , `String
                               (Sandwalk_core.Plan_step.Key.to_string step_key) )
                         ; ( "attempt"
                           , `Int
                               (Sandwalk_store.Claim_step_result.attempt
                                  claimed) )
                         ; "lease_expires_at", `String lease_expires_at
                         ]
                     in
                     Sandwalk_protocol.Envelope.success ~result ()
                     |> Sandwalk_protocol.Envelope.render
                     |> print_endline;
                     Deferred.unit)))))
;;

let step_command =
  Async.Command.group
    ~summary:"Manage durable plan-step execution."
    [ "claim", step_claim_command ]
;;

let command =
  Async.Command.group
    ~summary:"Deterministic research orchestration for AI agents."
    [ "about", about_command
    ; "init", init_command
    ; "plan", plan_command
    ; "resume", resume_command
    ; "status", status_command
    ; "step", step_command
    ]
;;

let () = Command_unix.run command
