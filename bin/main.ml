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
  | Invalid_step_state _
  | Claim_not_found
  | Claim_not_active
  | Claim_expired _
  | Search_wrong_phase _
  | Search_requires_claim
  | Hit_id_collision
  | Hit_not_found _
  | Hit_not_owned_by_claim _
  | Fetch_wrong_phase _
  | Fetch_requires_claim
  | Snapshot_id_collision
  | Snapshot_not_found _
  | Snapshot_not_owned_by_claim _
  | Excerpt_wrong_phase _
  | Excerpt_requires_claim
  | Excerpt_id_collision
  | Finding_wrong_phase _
  | Finding_step_mismatch
  | Finding_exists _ ->
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
                let%bind ((plan_steps, active_claims), latest_checkpoint), history =
                  Deferred.both
                    (Deferred.both
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
                       (In_thread.run (fun () ->
                          Sandwalk_store.read_latest_checkpoint
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path workspace)
                            ())))
                    (Sandwalk_runtime.Audit.read_history
                       ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                       ~exclude_invocation_id:invocation_id)
                in
                (match plan_steps, active_claims, latest_checkpoint, history with
                 | Error _, _, _, _
                 | _, Error _, _, _
                 | _, _, Error _, _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_STATE_ERROR"
                     ~message:"Could not read durable recovery state."
                 | _, _, _, Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_LOG_ERROR"
                     ~message:"Could not read workspace audit history."
                 | Ok plan_steps, Ok active_claims, Ok latest_checkpoint, Ok history ->
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
                       ~latest_checkpoint:
                         (Option.map latest_checkpoint ~f:(fun checkpoint ->
                            ( Sandwalk_store.Latest_checkpoint.step_key checkpoint
                            , Sandwalk_store.Latest_checkpoint.summary checkpoint
                            , Sandwalk_store.Latest_checkpoint.next checkpoint
                            , Sandwalk_store.Latest_checkpoint.created_at
                                checkpoint )))
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
  | Claim_not_found -> "CLAIM_NOT_FOUND", "Claim does not exist."
  | Claim_not_active -> "CLAIM_NOT_ACTIVE", "Claim is no longer active."
  | Claim_expired _ -> "CLAIM_EXPIRED", "Claim lease has expired."
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
                       ~lease_duration_seconds:lease_seconds
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

let step_checkpoint_command =
  Async.Command.async
    ~summary:"Record a semantic checkpoint and renew its claim lease."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active claim capability"
     and summary_path =
       flag "--summary-file" (required string) ~doc:"PATH Checkpoint summary file"
     and next_path =
       flag "--next-file" (required string) ~doc:"PATH Next-action file"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text, Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
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
           let maximum_bytes = Sandwalk_core.Checkpoint.maximum_file_bytes in
           let%bind summary_input, next_input =
             Deferred.both
               (Sandwalk_runtime.File_input.read
                  ~path:summary_path
                  ~maximum_bytes)
               (Sandwalk_runtime.File_input.read ~path:next_path ~maximum_bytes)
           in
           match summary_input, next_input with
           | Error _, _ | _, Error _ ->
             print_failure_and_exit
               ~code:"CHECKPOINT_FILE_ERROR"
               ~message:"Could not read bounded checkpoint files."
           | Ok summary_input, Ok next_input ->
             (match
                Sandwalk_core.Checkpoint.create
                  ~summary:(Sandwalk_runtime.File_input.content summary_input)
                  ~next:(Sandwalk_runtime.File_input.content next_input)
              with
              | Error error ->
                print_failure_and_exit
                  ~code:"INVALID_CHECKPOINT"
                  ~message:(Sandwalk_core.Checkpoint.Error.message error)
              | Ok checkpoint ->
                let file_argument input =
                  `Assoc
                    [ "path", `String (Sandwalk_runtime.File_input.path input)
                    ; "size", `Int (Sandwalk_runtime.File_input.size input)
                    ; ( "hash"
                      , `Assoc
                          [ "algorithm", `String "md5"
                          ; ( "value"
                            , `String (Sandwalk_runtime.File_input.md5 input) )
                          ] )
                    ]
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; "claim", `String claim_text
                    ; "summary_file", file_argument summary_input
                    ; "next_file", file_argument next_input
                    ]
                in
                let started_at = Time_float_unix.now () in
                let now_unix_seconds =
                  Time_float.to_span_since_epoch started_at
                  |> Time_float.Span.to_sec
                  |> Float.iround_down_exn
                  |> Int64.of_int
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
                      ?step
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
                       ~command:"step checkpoint"
                       ~arguments
                       ~phase
                       ~claim:claim_text
                       ?step
                       ~consumed_references:[ claim_text ]
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit
                      ?step
                      ?(state_changes = [])
                      ~code
                      ~message
                      ()
                  =
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
                      ~phase:(Some "researching")
                      ~state_changes
                      ?step
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
                    ~phase:(Some "researching")
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind saved =
                     In_thread.run (fun () ->
                       Sandwalk_store.save_checkpoint
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~claim_id
                         ~checkpoint
                         ~summary_path:
                           (Sandwalk_runtime.File_input.path summary_input)
                         ~summary_md5:
                           (Sandwalk_runtime.File_input.md5 summary_input)
                         ~summary_size:
                           (Sandwalk_runtime.File_input.size summary_input)
                         ~next_path:(Sandwalk_runtime.File_input.path next_input)
                         ~next_md5:(Sandwalk_runtime.File_input.md5 next_input)
                         ~next_size:(Sandwalk_runtime.File_input.size next_input)
                         ~now:(Sandwalk_runtime.timestamp_utc started_at)
                         ~now_unix_seconds
                         ())
                   in
                   (match saved with
                    | Error error ->
                      let code, message = claim_error error in
                      (match error with
                       | Sandwalk_store.Error.Claim_expired step ->
                         fail_with_audit
                           ~step
                           ~state_changes:
                             [ `Assoc
                                 [ "entity", `String ("step." ^ step ^ ".state")
                                 ; "from", `String "claimed"
                                 ; "to", `String "expired"
                                 ]
                             ]
                           ~code
                           ~message
                           ()
                       | _ -> fail_with_audit ~code ~message ())
                    | Ok saved ->
                      let step_key =
                        Sandwalk_store.Save_checkpoint_result.step_key saved
                      in
                      let lease_expires_unix_seconds =
                        Sandwalk_store.Save_checkpoint_result
                        .lease_expires_unix_seconds
                          saved
                      in
                      let lease_expires_at =
                        Time_float.of_span_since_epoch
                          (Time_float.Span.of_sec
                             (Int64.to_float lease_expires_unix_seconds))
                        |> Sandwalk_runtime.timestamp_utc
                      in
                      let checkpoint_number =
                        Sandwalk_store.Save_checkpoint_result.checkpoint_number
                          saved
                      in
                      let state_changes =
                        [ `Assoc
                            [ ( "entity"
                              , `String
                                  ("step."
                                   ^ Sandwalk_core.Plan_step.Key.to_string step_key
                                   ^ ".checkpoint") )
                            ; "from", `Null
                            ; "to", `Int checkpoint_number
                            ]
                        ; `Assoc
                            [ "entity", `String "claim.lease"
                            ; "from", `Null
                            ; "to", `String lease_expires_at
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
                          ~step:
                            (Sandwalk_core.Plan_step.Key.to_string step_key)
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
                             [ ( "step"
                               , `String
                                   (Sandwalk_core.Plan_step.Key.to_string
                                      step_key) )
                             ; "checkpoint", `Int checkpoint_number
                             ; "lease_expires_at", `String lease_expires_at
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let search_error = function
  | Sandwalk_store.Error.Search_wrong_phase _ ->
    "SEARCH_NOT_ALLOWED", "Search is not allowed in the current phase."
  | Search_requires_claim ->
    "SEARCH_REQUIRES_CLAIM", "Research search requires an active claim."
  | Hit_id_collision ->
    "HIT_ID_COLLISION", "Could not allocate unique search-hit references."
  | error -> claim_error error
;;

let fetch_error = function
  | Sandwalk_store.Error.Hit_not_found reference ->
    "HIT_NOT_FOUND", sprintf "Search hit %S does not exist." reference
  | Hit_not_owned_by_claim reference ->
    "HIT_NOT_OWNED_BY_CLAIM",
    sprintf "Search hit %S belongs to another research step." reference
  | Fetch_wrong_phase _ ->
    "FETCH_NOT_ALLOWED", "Fetch is not allowed in the current phase."
  | Fetch_requires_claim ->
    "FETCH_REQUIRES_CLAIM", "Research fetch requires an active claim."
  | Snapshot_id_collision ->
    "SNAPSHOT_ID_COLLISION", "Could not allocate a unique snapshot reference."
  | error -> claim_error error
;;

let excerpt_store_error = function
  | Sandwalk_store.Error.Snapshot_not_found reference ->
    "SNAPSHOT_NOT_FOUND", sprintf "Snapshot %S does not exist." reference
  | Snapshot_not_owned_by_claim reference ->
    "SNAPSHOT_NOT_OWNED_BY_CLAIM",
    sprintf "Snapshot %S belongs to another research step." reference
  | Excerpt_wrong_phase _ ->
    "EXCERPT_NOT_ALLOWED", "Excerpt creation is not allowed in the current phase."
  | Excerpt_requires_claim ->
    "EXCERPT_REQUIRES_CLAIM", "Research excerpt creation requires an active claim."
  | Excerpt_id_collision ->
    "EXCERPT_ID_COLLISION", "Could not allocate a unique excerpt reference."
  | error -> fetch_error error
;;

let excerpt_selection_error = function
  | Sandwalk_core.Excerpt.Empty_document ->
    "EMPTY_SNAPSHOT", "Snapshot Markdown is empty."
  | Empty_excerpt -> "EMPTY_EXCERPT", "Excerpt text must not be empty."
  | Invalid_line_range ->
    "INVALID_LINE_RANGE", "Line range must identify existing inclusive lines."
  | Text_not_found ->
    "EXCERPT_TEXT_NOT_FOUND", "Excerpt text does not occur in the snapshot."
  | Ambiguous_text count ->
    ( "AMBIGUOUS_EXCERPT_TEXT"
    , sprintf "Excerpt text occurs %d times; specify --occurrence." count )
  | Invalid_occurrence occurrence ->
    "INVALID_OCCURRENCE", sprintf "Occurrence %d does not exist." occurrence
  | Too_large size ->
    ( "EXCERPT_TOO_LARGE"
    , sprintf
        "Excerpt is %d bytes; maximum size is %d bytes."
        size
        Sandwalk_core.Excerpt.maximum_bytes )
;;

let fetch_command =
  Async.Command.async
    ~summary:"Fetch one owned search hit into an immutable snapshot."
    (let%map_open.Command hit_text = anon ("HIT" %: string)
     and slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and adapter =
       flag
         "--adapter"
         (optional_with_default "sandwalk-fetch-curl-pandoc" string)
         ~doc:"PATH Fetch adapter executable"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text, Sandwalk_core.Hit_id.of_string hit_text
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_HIT"
           ~message:"Search-hit reference is invalid."
       | Ok slug, Some hit_id ->
         let claim_id =
           match claim_text with
           | None -> Ok None
           | Some value ->
             Sandwalk_core.Claim_id.of_string value
             |> Result.of_option ~error:"Claim identifier is invalid."
             |> Result.map ~f:Option.some
         in
         (match claim_id with
          | Error message ->
            print_failure_and_exit ~code:"INVALID_CLAIM" ~message
          | Ok claim_id ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
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
              let%bind hit =
                In_thread.run (fun () ->
                  Sandwalk_store.hit_for_fetch
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~hit_id
                    ())
              in
              match hit with
              | Error error ->
                let code, message = fetch_error error in
                print_failure_and_exit ~code ~message
              | Ok hit ->
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
                   print_failure_and_exit ~code ~message
                 | Ok status
                   when Sandwalk_core.Phase.equal
                          (Sandwalk_store.Workspace_status.phase status)
                          Sandwalk_core.Phase.Researching
                        && Option.is_none claim_id ->
                   print_failure_and_exit
                     ~code:"FETCH_REQUIRES_CLAIM"
                     ~message:"Research fetch requires an active claim."
                 | Ok _ ->
                   let started_at = Time_float_unix.now () in
                   let%bind invocation_id, snapshot_id =
                     Deferred.both
                       (In_thread.run (fun () ->
                          Sandwalk_runtime.invocation_id ~now:started_at))
                       (In_thread.run Sandwalk_runtime.snapshot_id)
                   in
                   let temporary_path =
                     Sandwalk_runtime.Workspace.temporary_fetch_path
                       workspace
                       ~invocation_id
                   in
                   let snapshot_path =
                     Sandwalk_runtime.Workspace.snapshot_path workspace snapshot_id
                   in
                   let url = Sandwalk_store.Hit_for_fetch.url hit in
                   let arguments =
                     `Assoc
                       [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                       ; "directory_prefix", `String directory_prefix
                       ; "hit", `String hit_text
                       ; "adapter", `String adapter
                       ; ( "claim"
                         , Option.value_map
                             claim_text
                             ~default:`Null
                             ~f:(fun value -> `String value) )
                       ]
                   in
                   let append_event
                         ~kind
                         ~timestamp
                         ~phase
                         ~state_changes
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
                          ~command:"fetch"
                          ~arguments
                          ~phase
                          ?claim:claim_text
                          ~raw_argv:(Sys.get_argv () |> Array.to_list)
                          ~state_changes
                          ~consumed_references:
                            (hit_text :: Option.to_list claim_text)
                          ?created_references
                          ?duration_ms
                          ?outcome
                          ?error_code
                          ())
                   in
                   let fail_with_audit ~code ~message =
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
                         ~phase:None
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
                   (match started with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let%bind () =
                        Unix.mkdir ~p:() (Filename.dirname snapshot_path)
                      in
                      let%bind () = Unix.mkdir ~p:() temporary_path in
                      let request =
                        Sandwalk_protocol.Fetch_adapter.request
                          ~url
                          ~output_directory:temporary_path
                      in
                      let%bind adapter_output =
                        Sandwalk_runtime.Adapter.run_json
                          ~executable:adapter
                          ~request
                          ~timeout:(Time_float.Span.of_sec 120.)
                          ~maximum_output_bytes:65_536
                      in
                      (match adapter_output with
                       | Error _ ->
                         fail_with_audit
                           ~code:"FETCH_ADAPTER_FAILED"
                           ~message:"Fetch adapter failed."
                       | Ok _ ->
                         let manifest_path =
                           Filename.concat temporary_path "manifest.json"
                         in
                         let document_path =
                           Filename.concat temporary_path "document.md"
                         in
                         let%bind manifest_input, document_input =
                           Deferred.both
                             (Sandwalk_runtime.File_input.read
                                ~path:manifest_path
                                ~maximum_bytes:262_144)
                             (Sandwalk_runtime.File_input.read
                                ~path:document_path
                                ~maximum_bytes:52_428_800)
                         in
                         (match manifest_input, document_input with
                          | Error _, _ | _, Error _ ->
                            fail_with_audit
                              ~code:"FETCH_ARTIFACT_ERROR"
                              ~message:"Fetch adapter omitted required artifacts."
                          | Ok manifest_input, Ok document_input ->
                            if Sandwalk_runtime.File_input.size document_input = 0
                            then
                              fail_with_audit
                                ~code:"FETCH_ARTIFACT_ERROR"
                                ~message:"Fetched Markdown document is empty."
                            else (
                              let manifest_json =
                                Sandwalk_runtime.File_input.content manifest_input
                              in
                              let decoded =
                                try
                                  manifest_json
                                  |> Yojson.Safe.from_string
                                  |> Sandwalk_protocol.Fetch_adapter.manifest
                                with
                                | _ ->
                                  Error
                                    Sandwalk_protocol.Fetch_adapter.Invalid_manifest
                              in
                              match decoded with
                              | Error _ ->
                                fail_with_audit
                                  ~code:"FETCH_PROTOCOL_ERROR"
                                  ~message:"Fetch manifest is invalid."
                              | Ok manifest ->
                                let%bind published =
                                  Deferred.Or_error.try_with (fun () ->
                                    Unix.rename
                                      ~src:temporary_path
                                      ~dst:snapshot_path)
                                in
                                (match published with
                                 | Error _ ->
                                   fail_with_audit
                                     ~code:"WORKSPACE_IO_ERROR"
                                     ~message:
                                       "Could not publish immutable snapshot."
                                 | Ok () ->
                                   let persisted_at = Time_float_unix.now () in
                                   let now_unix_seconds =
                                     Time_float.to_span_since_epoch persisted_at
                                     |> Time_float.Span.to_sec
                                     |> Float.iround_down_exn
                                     |> Int64.of_int
                                   in
                                   let%bind persisted =
                                     In_thread.run (fun () ->
                                       Sandwalk_store.record_snapshot
                                         ~database_path:
                                           (Sandwalk_runtime.Workspace.database_path
                                              workspace)
                                         ~expected_slug:slug
                                         ~claim_id
                                         ~hit_id
                                         ~snapshot_id
                                         ~artifact_path:snapshot_path
                                         ~final_url:
                                           (Sandwalk_protocol.Fetch_adapter.final_url
                                              manifest)
                                         ~input_sha256:
                                           (Sandwalk_protocol.Fetch_adapter
                                            .input_sha256
                                              manifest)
                                         ~markdown_sha256:
                                           (Sandwalk_protocol.Fetch_adapter
                                            .markdown_sha256
                                              manifest)
                                         ~manifest_json
                                         ~now:
                                           (Sandwalk_runtime.timestamp_utc
                                              persisted_at)
                                         ~now_unix_seconds
                                         ())
                                   in
                                   (match persisted with
                                    | Error error ->
                                      let code, message = fetch_error error in
                                      fail_with_audit ~code ~message
                                    | Ok persisted ->
                                      let reference =
                                        Sandwalk_core.Snapshot_id.to_string
                                          snapshot_id
                                      in
                                      let phase =
                                        Option.value_map
                                          (Sandwalk_store.Record_snapshot_result
                                           .step_key
                                             persisted)
                                          ~default:"reconnaissance"
                                          ~f:(Fn.const "researching")
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
                                          ~timestamp:
                                            (Sandwalk_runtime.timestamp_utc
                                               finished_at)
                                          ~phase:(Some phase)
                                          ~state_changes:
                                            [ `Assoc
                                                [ ( "entity"
                                                  , `String "snapshot" )
                                                ; "from", `Null
                                                ; "to", `String reference
                                                ]
                                            ]
                                          ~created_references:[ reference ]
                                          ~duration_ms
                                          ~outcome:"success"
                                          ()
                                      in
                                      (match logged with
                                       | Error _ ->
                                         print_failure_and_exit
                                           ~code:"AUDIT_LOG_ERROR"
                                           ~message:
                                             "Could not append workspace audit log."
                                       | Ok () ->
                                         let result =
                                           `Assoc
                                             [ "snapshot", `String reference
                                             ; ( "document_path"
                                               , `String
                                                   (Filename.concat
                                                      snapshot_path
                                                      "document.md") )
                                             ]
                                         in
                                         Sandwalk_protocol.Envelope.success
                                           ~result
                                           ()
                                         |> Sandwalk_protocol.Envelope.render
                                         |> print_endline;
                                         Deferred.unit)))))))))))
;;

let excerpt_create_command =
  Async.Command.async
    ~summary:"Create an exact excerpt from an immutable snapshot."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and snapshot_text =
       flag "--snapshot" (required string) ~doc:"SNAPSHOT Immutable snapshot"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and lines_text =
       flag "--lines" (optional string) ~doc:"FIRST:LAST Inclusive line range"
     and text_path =
       flag "--text-file" (optional string) ~doc:"PATH Exact excerpt text"
     and occurrence =
       flag "--occurrence" (optional int) ~doc:"N One-based text occurrence"
     in
     fun () ->
       let selection =
         match lines_text, text_path, occurrence with
         | Some range, None, None ->
           (match String.lsplit2 range ~on:':' with
            | Some (first, last) ->
              (match Int.of_string_opt first, Int.of_string_opt last with
               | Some first, Some last -> Ok (`Lines (first, last))
               | _ -> Error ())
            | None -> Error ())
         | None, Some path, occurrence -> Ok (`Text (path, occurrence))
         | _ -> Error ()
       in
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Snapshot_id.of_string snapshot_text,
         selection
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_SNAPSHOT"
           ~message:"Snapshot reference is invalid."
       | _, _, Error () ->
         print_failure_and_exit
           ~code:"INVALID_EXCERPT_SELECTOR"
           ~message:
             "Specify exactly one of --lines or --text-file; occurrence applies to text."
       | Ok slug, Some snapshot_id, Ok selection ->
         let claim_id =
           match claim_text with
           | None -> Ok None
           | Some value ->
             Sandwalk_core.Claim_id.of_string value
             |> Result.of_option ~error:"Claim identifier is invalid."
             |> Result.map ~f:Option.some
         in
         (match claim_id with
          | Error message ->
            print_failure_and_exit ~code:"INVALID_CLAIM" ~message
          | Ok claim_id ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
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
              let%bind snapshot =
                In_thread.run (fun () ->
                  Sandwalk_store.snapshot_for_excerpt
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~snapshot_id
                    ())
              in
              match snapshot with
              | Error error ->
                let code, message = excerpt_store_error error in
                print_failure_and_exit ~code ~message
              | Ok snapshot ->
                let document_path =
                  Filename.concat
                    (Sandwalk_store.Snapshot_for_excerpt.artifact_path snapshot)
                    "document.md"
                in
                let%bind document_input =
                  Sandwalk_runtime.File_input.read
                    ~path:document_path
                    ~maximum_bytes:52_428_800
                in
                (match document_input with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"SNAPSHOT_ARTIFACT_ERROR"
                     ~message:"Could not read bounded snapshot Markdown."
                 | Ok document_input ->
                   let%bind text_input =
                     match selection with
                     | `Lines _ -> Deferred.return (Ok None)
                     | `Text (path, _) ->
                       let%map input =
                         Sandwalk_runtime.File_input.read
                           ~path
                           ~maximum_bytes:Sandwalk_core.Excerpt.maximum_bytes
                       in
                       Result.map input ~f:Option.some
                   in
                   (match text_input with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"EXCERPT_FILE_ERROR"
                        ~message:"Could not read bounded excerpt text."
                    | Ok text_input ->
                      let selected =
                        match selection, text_input with
                        | `Lines (first, last), _ ->
                          Sandwalk_core.Excerpt.by_lines
                            (Sandwalk_runtime.File_input.content document_input)
                            ~first
                            ~last
                        | `Text (_, occurrence), Some input ->
                          Sandwalk_core.Excerpt.by_text
                            (Sandwalk_runtime.File_input.content document_input)
                            ~excerpt:
                              (Sandwalk_runtime.File_input.content input)
                            ~occurrence
                        | `Text _, None -> assert false
                      in
                      (match selected with
                       | Error error ->
                         let code, message = excerpt_selection_error error in
                         print_failure_and_exit ~code ~message
                       | Ok excerpt ->
                         let started_at = Time_float_unix.now () in
                         let%bind invocation_id, excerpt_id =
                           Deferred.both
                             (In_thread.run (fun () ->
                                Sandwalk_runtime.invocation_id ~now:started_at))
                             (In_thread.run Sandwalk_runtime.excerpt_id)
                         in
                         let artifact_path =
                           Sandwalk_runtime.Workspace.excerpt_path
                             workspace
                             excerpt_id
                         in
                         let file_argument input =
                           `Assoc
                             [ ( "path"
                               , `String
                                   (Sandwalk_runtime.File_input.path input) )
                             ; ( "size"
                               , `Int
                                   (Sandwalk_runtime.File_input.size input) )
                             ; ( "hash"
                               , `Assoc
                                   [ "algorithm", `String "md5"
                                   ; ( "value"
                                     , `String
                                         (Sandwalk_runtime.File_input.md5
                                            input) )
                                   ] )
                             ]
                         in
                         let selector_argument =
                           match selection, text_input with
                           | `Lines (first, last), _ ->
                             `Assoc
                               [ "lines", `String (sprintf "%d:%d" first last)
                               ]
                           | `Text (_, occurrence), Some input ->
                             `Assoc
                               [ "text_file", file_argument input
                               ; ( "occurrence"
                                 , Option.value_map
                                     occurrence
                                     ~default:`Null
                                     ~f:(fun value -> `Int value) )
                               ]
                           | `Text _, None -> assert false
                         in
                         let arguments =
                           `Assoc
                             [ ( "slug"
                               , `String (Sandwalk_core.Slug.to_string slug) )
                             ; "directory_prefix", `String directory_prefix
                             ; "snapshot", `String snapshot_text
                             ; ( "claim"
                               , Option.value_map
                                   claim_text
                                   ~default:`Null
                                   ~f:(fun value -> `String value) )
                             ; "selector", selector_argument
                             ]
                         in
                         let append_event
                               ~kind
                               ~timestamp
                               ~phase
                               ~state_changes
                               ?created_references
                               ?duration_ms
                               ?outcome
                               ?error_code
                               ()
                           =
                           Sandwalk_runtime.Audit.append
                             ~path:
                               (Sandwalk_runtime.Workspace.events_path
                                  workspace)
                             (Sandwalk_protocol.Audit_event.create
                                ~invocation_id
                                ~timestamp
                                ~kind
                                ~command:"excerpt create"
                                ~arguments
                                ~phase
                                ?claim:claim_text
                                ~raw_argv:(Sys.get_argv () |> Array.to_list)
                                ~state_changes
                                ~consumed_references:
                                  (snapshot_text :: Option.to_list claim_text)
                                ?created_references
                                ?duration_ms
                                ?outcome
                                ?error_code
                                ())
                         in
                         let fail_with_audit ~code ~message =
                           let finished_at = Time_float_unix.now () in
                           let duration_ms =
                             Time_float.diff finished_at started_at
                             |> Time_float.Span.to_ms
                             |> Float.iround_nearest_exn
                           in
                           let%bind logged =
                             append_event
                               ~kind:`Failed
                               ~timestamp:
                                 (Sandwalk_runtime.timestamp_utc finished_at)
                               ~phase:None
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
                               ~message:
                                 "Could not append workspace audit log."
                           | Ok () -> print_failure_and_exit ~code ~message
                         in
                         let remove_candidate () =
                           let%map _ =
                             Monitor.try_with (fun () ->
                               Unix.unlink artifact_path)
                           in
                           ()
                         in
                         let%bind started =
                           append_event
                             ~kind:`Started
                             ~timestamp:
                               (Sandwalk_runtime.timestamp_utc started_at)
                             ~phase:None
                             ~state_changes:[]
                             ()
                         in
                         (match started with
                          | Error _ ->
                            print_failure_and_exit
                              ~code:"AUDIT_LOG_ERROR"
                              ~message:"Could not append workspace audit log."
                          | Ok () ->
                            let%bind () =
                              Unix.mkdir
                                ~p:()
                                (Filename.dirname artifact_path)
                            in
                            let%bind written =
                              Sandwalk_runtime.Atomic_file.write_exclusive
                                ~path:artifact_path
                                (Sandwalk_core.Excerpt.text excerpt)
                            in
                            (match written with
                             | Error _ ->
                               fail_with_audit
                                 ~code:"WORKSPACE_IO_ERROR"
                                 ~message:"Could not publish excerpt artifact."
                             | Ok () ->
                               let persisted_at = Time_float_unix.now () in
                               let now_unix_seconds =
                                 Time_float.to_span_since_epoch persisted_at
                                 |> Time_float.Span.to_sec
                                 |> Float.iround_down_exn
                                 |> Int64.of_int
                               in
                               let%bind persisted =
                                 In_thread.run (fun () ->
                                   Sandwalk_store.record_excerpt
                                     ~database_path:
                                       (Sandwalk_runtime.Workspace.database_path
                                          workspace)
                                     ~expected_slug:slug
                                     ~claim_id
                                     ~snapshot_id
                                     ~excerpt_id
                                     ~artifact_path
                                     ~markdown_sha256:
                                       (Sandwalk_store.Snapshot_for_excerpt
                                        .markdown_sha256
                                          snapshot)
                                     ~line_start:
                                       (Sandwalk_core.Excerpt.line_start excerpt)
                                     ~line_end:
                                       (Sandwalk_core.Excerpt.line_end excerpt)
                                     ~byte_start:
                                       (Sandwalk_core.Excerpt.byte_start excerpt)
                                     ~byte_end:
                                       (Sandwalk_core.Excerpt.byte_end excerpt)
                                     ~excerpt_md5:
                                       (Md5.digest_string
                                          (Sandwalk_core.Excerpt.text excerpt)
                                        |> Md5.to_hex)
                                     ~excerpt_size:
                                       (String.length
                                          (Sandwalk_core.Excerpt.text excerpt))
                                     ~now:
                                       (Sandwalk_runtime.timestamp_utc
                                          persisted_at)
                                     ~now_unix_seconds
                                     ())
                               in
                               (match persisted with
                                | Error error ->
                                  let%bind () = remove_candidate () in
                                  let code, message =
                                    excerpt_store_error error
                                  in
                                  fail_with_audit ~code ~message
                                | Ok persisted ->
                                  let stored_id =
                                    Sandwalk_store.Record_excerpt_result
                                    .excerpt_id
                                      persisted
                                  in
                                  let created =
                                    Sandwalk_store.Record_excerpt_result.created
                                      persisted
                                  in
                                  let%bind () =
                                    if created
                                    then Deferred.unit
                                    else remove_candidate ()
                                  in
                                  let reference =
                                    Sandwalk_core.Excerpt_id.to_string stored_id
                                  in
                                  let phase =
                                    Option.value_map
                                      (Sandwalk_store.Record_excerpt_result
                                       .step_key
                                         persisted)
                                      ~default:"reconnaissance"
                                      ~f:(Fn.const "researching")
                                  in
                                  let finished_at =
                                    Time_float_unix.now ()
                                  in
                                  let duration_ms =
                                    Time_float.diff finished_at started_at
                                    |> Time_float.Span.to_ms
                                    |> Float.iround_nearest_exn
                                  in
                                  let%bind logged =
                                    append_event
                                      ~kind:`Finished
                                      ~timestamp:
                                        (Sandwalk_runtime.timestamp_utc
                                           finished_at)
                                      ~phase:(Some phase)
                                      ~state_changes:
                                        (if created
                                         then
                                           [ `Assoc
                                               [ ( "entity"
                                                 , `String "excerpt" )
                                               ; "from", `Null
                                               ; "to", `String reference
                                               ]
                                           ]
                                         else [])
                                      ~created_references:
                                        (if created then [ reference ] else [])
                                      ~duration_ms
                                      ~outcome:"success"
                                      ()
                                  in
                                  (match logged with
                                   | Error _ ->
                                     print_failure_and_exit
                                       ~code:"AUDIT_LOG_ERROR"
                                       ~message:
                                         "Could not append workspace audit log."
                                   | Ok () ->
                                     let result =
                                       `Assoc
                                         [ "excerpt", `String reference
                                         ; "created", `Bool created
                                         ; ( "lines"
                                           , `String
                                               (sprintf
                                                  "%d:%d"
                                                  (Sandwalk_core.Excerpt
                                                   .line_start
                                                     excerpt)
                                                  (Sandwalk_core.Excerpt
                                                   .line_end
                                                     excerpt)) )
                                         ; ( "bytes"
                                           , `String
                                               (sprintf
                                                  "%d:%d"
                                                  (Sandwalk_core.Excerpt
                                                   .byte_start
                                                     excerpt)
                                                  (Sandwalk_core.Excerpt
                                                   .byte_end
                                                     excerpt)) )
                                         ]
                                     in
                                     Sandwalk_protocol.Envelope.success
                                       ~result
                                       ()
                                     |> Sandwalk_protocol.Envelope.render
                                     |> print_endline;
                                     Deferred.unit))))))))))
;;

let excerpt_command =
  Async.Command.group
    ~summary:"Create and manage exact snapshot excerpts."
    [ "create", excerpt_create_command ]
;;

let search_command =
  Async.Command.async
    ~summary:"Run a bounded search adapter and persist provenance-owned hits."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and query =
       flag "--query" (required string) ~doc:"QUERY Search query"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and limit =
       flag
         "--limit"
         (optional_with_default 10 int)
         ~doc:"N Maximum results from 1 to 25"
     and adapter =
       flag
         "--adapter"
         (optional_with_default "sandwalk-search-ddgr" string)
         ~doc:"PATH Search adapter executable"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         if String.is_empty query || String.length query > 2_048
         then
           print_failure_and_exit
             ~code:"INVALID_QUERY"
             ~message:"Search query must contain between 1 and 2048 bytes."
         else if limit < 1 || limit > 25
         then
           print_failure_and_exit
             ~code:"INVALID_SEARCH_LIMIT"
             ~message:"Search limit must be between 1 and 25."
         else (
           let claim_id =
             match claim_text with
             | None -> Ok None
             | Some value ->
               Sandwalk_core.Claim_id.of_string value
               |> Result.of_option ~error:"Claim identifier is invalid."
               |> Result.map ~f:Option.some
           in
           match claim_id with
           | Error message ->
             print_failure_and_exit ~code:"INVALID_CLAIM" ~message
           | Ok claim_id ->
             let directory_prefix =
               Sandwalk_runtime.resolve_directory_prefix
                 ~command_line:directory_prefix
             in
             let workspace =
               Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
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
               let%bind status =
                 In_thread.run (fun () ->
                   Sandwalk_store.read_status
                     ~database_path:
                       (Sandwalk_runtime.Workspace.database_path workspace)
                     ~expected_slug:slug
                     ())
               in
               match status with
               | Error error ->
                 let code, message = status_error error in
                 print_failure_and_exit ~code ~message
               | Ok status
                 when Sandwalk_core.Phase.equal
                        (Sandwalk_store.Workspace_status.phase status)
                        Sandwalk_core.Phase.Researching
                      && Option.is_none claim_id ->
                 print_failure_and_exit
                   ~code:"SEARCH_REQUIRES_CLAIM"
                   ~message:"Research search requires an active claim."
               | Ok _ ->
                 let arguments =
                   `Assoc
                     [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                     ; "directory_prefix", `String directory_prefix
                     ; "query", `String query
                     ; "limit", `Int limit
                     ; "adapter", `String adapter
                     ; ( "claim"
                       , Option.value_map
                           claim_text
                           ~default:`Null
                           ~f:(fun value -> `String value) )
                     ]
                 in
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
                        ~command:"search"
                        ~arguments
                        ~phase
                        ?claim:claim_text
                        ~raw_argv:(Sys.get_argv () |> Array.to_list)
                        ~state_changes
                        ~consumed_references:
                          (Option.to_list claim_text)
                        ?created_references
                        ?duration_ms
                        ?outcome
                        ?error_code
                        ())
                 in
                 let fail_with_audit ~code ~message =
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
                       ~phase:None
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
                 (match started with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let request =
                      Sandwalk_protocol.Search_adapter.request ~query ~limit
                    in
                    let%bind adapter_output =
                      Sandwalk_runtime.Adapter.run_json
                        ~executable:adapter
                        ~request
                        ~timeout:(Time_float.Span.of_sec 30.)
                        ~maximum_output_bytes:262_144
                    in
                    (match adapter_output with
                     | Error _ ->
                       fail_with_audit
                         ~code:"SEARCH_ADAPTER_FAILED"
                         ~message:"Search adapter failed."
                     | Ok adapter_output ->
                       (match
                          Sandwalk_protocol.Search_adapter.results adapter_output
                        with
                        | Error _ ->
                          fail_with_audit
                            ~code:"SEARCH_PROTOCOL_ERROR"
                            ~message:"Search adapter returned an invalid response."
                        | Ok results ->
                          let%bind hit_ids =
                            In_thread.run (fun () ->
                              List.map results ~f:(fun _ ->
                                Sandwalk_runtime.hit_id ()))
                          in
                          let hits =
                            List.map2_exn hit_ids results ~f:(fun hit_id result ->
                              ( hit_id
                              , Sandwalk_protocol.Search_adapter.url result
                              , Sandwalk_protocol.Search_adapter.title result
                              , Sandwalk_protocol.Search_adapter.snippet result ))
                          in
                          let persisted_at = Time_float_unix.now () in
                          let now_unix_seconds =
                            Time_float.to_span_since_epoch persisted_at
                            |> Time_float.Span.to_sec
                            |> Float.iround_down_exn
                            |> Int64.of_int
                          in
                          let%bind persisted =
                            In_thread.run (fun () ->
                              Sandwalk_store.record_search
                                ~database_path:
                                  (Sandwalk_runtime.Workspace.database_path
                                     workspace)
                                ~expected_slug:slug
                                ~claim_id
                                ~query
                                ~adapter
                                ~hits
                                ~now:
                                  (Sandwalk_runtime.timestamp_utc persisted_at)
                                ~now_unix_seconds
                                ())
                          in
                          (match persisted with
                           | Error error ->
                             let code, message = search_error error in
                             fail_with_audit ~code ~message
                           | Ok persisted ->
                             let stored_hits =
                               Sandwalk_store.Record_search_result.hits persisted
                             in
                             let references =
                               List.map stored_hits ~f:(fun hit ->
                                 Sandwalk_store.Stored_hit.hit_id hit
                                 |> Sandwalk_core.Hit_id.to_string)
                             in
                             let phase =
                               Option.value_map
                                 (Sandwalk_store.Record_search_result.step_key
                                    persisted)
                                 ~default:"reconnaissance"
                                 ~f:(Fn.const "researching")
                             in
                             let state_changes =
                               [ `Assoc
                                   [ "entity", `String "search.hits"
                                   ; "from", `Int 0
                                   ; "to", `Int (List.length references)
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
                                 ~timestamp:
                                   (Sandwalk_runtime.timestamp_utc finished_at)
                                 ~phase:(Some phase)
                                 ~state_changes
                                 ~created_references:references
                                 ~duration_ms
                                 ~outcome:"success"
                                 ()
                             in
                             (match logged with
                              | Error _ ->
                                print_failure_and_exit
                                  ~code:"AUDIT_LOG_ERROR"
                                  ~message:
                                    "Could not append workspace audit log."
                              | Ok () ->
                                let result =
                                  `Assoc
                                    [ "count", `Int (List.length references)
                                    ; ( "hits"
                                      , `List
                                          (List.map references ~f:(fun reference ->
                                             `String reference)) )
                                    ]
                                in
                                Sandwalk_protocol.Envelope.success ~result ()
                                |> Sandwalk_protocol.Envelope.render
                                |> print_endline;
                                Deferred.unit))))))))
;;

let finding_error = function
  | Sandwalk_store.Error.Finding_wrong_phase _ ->
    "FINDING_NOT_ALLOWED", "Finding creation is not allowed in the current phase."
  | Finding_step_mismatch ->
    "FINDING_STEP_MISMATCH", "Active claim belongs to another plan step."
  | Finding_exists reference ->
    "FINDING_EXISTS", sprintf "Finding %S already exists." reference
  | error -> claim_error error
;;

let finding_create_command =
  Async.Command.async
    ~summary:"Create a draft finding for one claimed plan step."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and step_text =
       flag "--step" (required string) ~doc:"STEP Plan-step key"
     and key_text =
       flag "--key" (required string) ~doc:"KEY Finding key"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     and claim_path =
       flag "--claim-file" (required string) ~doc:"PATH Finding statement"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Plan_step.Key.of_string step_text,
         Sandwalk_core.Finding_key.of_string key_text,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_STEP"
           ~message:"Plan-step key is invalid."
       | _, _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_FINDING_KEY"
           ~message:"Finding key is invalid."
       | _, _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Ok step_key, Some finding_key, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
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
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:claim_path
               ~maximum_bytes:Sandwalk_core.Finding_claim.maximum_bytes
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"FINDING_FILE_ERROR"
               ~message:"Could not read bounded finding statement."
           | Ok input ->
             (match
                Sandwalk_core.Finding_claim.create
                  (Sandwalk_runtime.File_input.content input)
              with
              | Error Empty ->
                print_failure_and_exit
                  ~code:"EMPTY_FINDING"
                  ~message:"Finding statement must not be empty."
              | Error (Too_large _) ->
                print_failure_and_exit
                  ~code:"FINDING_TOO_LARGE"
                  ~message:"Finding statement exceeds 65,536 bytes."
              | Ok finding_claim ->
                let started_at = Time_float_unix.now () in
                let now_unix_seconds =
                  Time_float.to_span_since_epoch started_at
                  |> Time_float.Span.to_sec
                  |> Float.iround_down_exn
                  |> Int64.of_int
                in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let reference = step_text ^ "/" ^ key_text in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; "step", `String step_text
                    ; "key", `String key_text
                    ; "claim", `String claim_text
                    ; ( "claim_file"
                      , `Assoc
                          [ "path", `String claim_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~state_changes
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
                       ~command:"finding create"
                       ~arguments
                       ~phase:(Some "researching")
                       ~step:step_text
                       ~claim:claim_text
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ~consumed_references:[ claim_text ]
                       ?created_references
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind created =
                     In_thread.run (fun () ->
                       Sandwalk_store.create_finding
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~claim_id
                         ~step_key
                         ~finding_key
                         ~claim_text:
                           (Sandwalk_core.Finding_claim.text finding_claim)
                         ~claim_md5:(Sandwalk_runtime.File_input.md5 input)
                         ~claim_size:(Sandwalk_runtime.File_input.size input)
                         ~now:(Sandwalk_runtime.timestamp_utc started_at)
                         ~now_unix_seconds
                         ())
                   in
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   (match created with
                    | Error error ->
                      let code, message = finding_error error in
                      let%bind logged =
                        append_event
                          ~kind:`Failed
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:[]
                          ~duration_ms
                          ~outcome:"failure"
                          ~error_code:code
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () -> print_failure_and_exit ~code ~message)
                    | Ok created ->
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:
                            [ `Assoc
                                [ "entity", `String "finding"
                                ; "from", `Null
                                ; "to", `String reference
                                ]
                            ]
                          ~created_references:[ reference ]
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
                             [ "finding", `String reference
                             ; ( "revision"
                               , `Int
                                   (Sandwalk_store.Create_finding_result.revision
                                      created) )
                             ; "state", `String "draft"
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let finding_command =
  Async.Command.group
    ~summary:"Create and manage evidence-backed findings."
    [ "create", finding_create_command ]
;;

let step_command =
  Async.Command.group
    ~summary:"Manage durable plan-step execution."
    [ "checkpoint", step_checkpoint_command; "claim", step_claim_command ]
;;

let command =
  Async.Command.group
    ~summary:"Deterministic research orchestration for AI agents."
    [ "about", about_command
    ; "excerpt", excerpt_command
    ; "fetch", fetch_command
    ; "finding", finding_command
    ; "init", init_command
    ; "plan", plan_command
    ; "resume", resume_command
    ; "search", search_command
    ; "status", status_command
    ; "step", step_command
    ]
;;

let () = Command_unix.run command
