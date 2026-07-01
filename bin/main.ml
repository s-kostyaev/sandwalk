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
                 | Error (Sandwalk_store.Error.Database_error _) ->
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
                   | Error (Sandwalk_store.Error.Database_error _) ->
                     print_failure_and_exit
                       ~code:"DATABASE_ERROR"
                       ~message:"Could not initialize workspace database.")))))
;;

let command =
  Async.Command.group
    ~summary:"Deterministic research orchestration for AI agents."
    [ "about", about_command; "init", init_command ]
;;

let () = Command_unix.run command
