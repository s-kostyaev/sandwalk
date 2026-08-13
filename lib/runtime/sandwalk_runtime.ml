open! Core
open! Async

module Workspace = struct
  type t =
    { root : string
    ; database_path : string
    ; events_path : string
    ; resume_path : string
    ; research_plan_path : string
    ; research_plan_lock_path : string
    ; writer_pack_path : string
    ; report_path : string
    ; sources_path : string
    ; report_pdf_path : string
    ; gc_raw_plan_path : string
    ; work_packet_path : string
    ; work_input_path : string
    }

  let root t = t.root
  let database_path t = t.database_path
  let events_path t = t.events_path
  let resume_path t = t.resume_path
  let research_plan_path t = t.research_plan_path
  let research_plan_lock_path t = t.research_plan_lock_path
  let writer_pack_path t = t.writer_pack_path
  let report_path t = t.report_path
  let sources_path t = t.sources_path
  let report_pdf_path t = t.report_pdf_path
  let gc_raw_plan_path t = t.gc_raw_plan_path
  let work_packet_path t = t.work_packet_path
  let work_input_path t = t.work_input_path
  let temporary_fetch_path t ~invocation_id =
    Filename.concat t.root ("artifacts/temporary/fetch-" ^ invocation_id)
  ;;

  let temporary_export_path t ~invocation_id =
    Filename.concat t.root ("artifacts/temporary/export-" ^ invocation_id)
  ;;

  let snapshot_path t snapshot_id =
    Filename.concat
      t.root
      ("artifacts/snapshots/" ^ Sandwalk_core.Snapshot_id.to_string snapshot_id)
  ;;

  let excerpt_path t excerpt_id =
    Filename.concat
      t.root
      ("artifacts/excerpts/" ^ Sandwalk_core.Excerpt_id.to_string excerpt_id ^ ".md")
  ;;

  let resolve ~directory_prefix ~slug =
    let root =
      Filename.concat directory_prefix (Sandwalk_core.Slug.to_string slug)
    in
    { root
    ; database_path = Filename.concat root "database/sandwalk.sqlite3"
    ; events_path = Filename.concat root "logs/events.jsonl"
    ; resume_path = Filename.concat root "artifacts/resume/workspace.md"
    ; research_plan_path = Filename.concat root "exports/research-plan.md"
    ; research_plan_lock_path =
        Filename.concat root "artifacts/temporary/research-plan.lock"
    ; writer_pack_path = Filename.concat root "exports/writer-pack.md"
    ; report_path = Filename.concat root "exports/report.md"
    ; sources_path = Filename.concat root "exports/sources.md"
    ; report_pdf_path = Filename.concat root "exports/report.pdf"
    ; gc_raw_plan_path = Filename.concat root "artifacts/gc-raw-plan.json"
    ; work_packet_path = Filename.concat root "artifacts/work/current.json"
    ; work_input_path = Filename.concat root "artifacts/work/current-input"
    }
  ;;

  let create_layout ~directory_prefix ~slug =
    let t = resolve ~directory_prefix ~slug in
    let directories =
      [ "database"
      ; "artifacts/snapshots"
      ; "artifacts/excerpts"
      ; "artifacts/resume"
      ; "artifacts/work"
      ; "artifacts/temporary"
      ; "exports"
      ; "logs"
      ]
    in
    Deferred.Or_error.try_with (fun () ->
      let%bind () = Unix.mkdir ~p:() t.root in
      let%map () =
        Deferred.List.iter directories ~how:`Sequential ~f:(fun directory ->
          Unix.mkdir ~p:() (Filename.concat t.root directory))
      in
      t)
  ;;
end

module Audit = struct
  type summary =
    { command : string
    ; timestamp : string
    ; outcome : string
    ; error_code : string option
    }

  type history =
    { recent_commands : summary list
    ; unmatched_commands : string list
    }

  let recent_commands t = t.recent_commands
  let unmatched_commands t = t.unmatched_commands
  let summary_command t = t.command
  let summary_timestamp t = t.timestamp
  let summary_outcome t = t.outcome
  let summary_error_code t = t.error_code

  let write_all file_descriptor value =
    let rec loop position =
      if position = String.length value
      then ()
      else
        let written =
          Core_unix.write_substring
            file_descriptor
            ~pos:position
            ~len:(String.length value - position)
            ~buf:value
        in
        loop (position + written)
    in
    loop 0
  ;;

  let append ~path event =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let file_descriptor =
          Core_unix.openfile
            path
            ~mode:[ O_WRONLY; O_CREAT; O_APPEND; O_CLOEXEC ]
            ~perm:0o600
        in
        Exn.protect
          ~f:(fun () ->
            Core_unix.flock_blocking
              file_descriptor
              Core_unix.Flock_command.lock_exclusive;
            write_all file_descriptor (Yojson.Safe.to_string event ^ "\n"))
          ~finally:(fun () -> Core_unix.close file_descriptor)))
  ;;

  let read_history ~path ~exclude_invocation_id =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let active = String.Table.create () in
        let recent = ref [] in
        let sequence = ref 0 in
        let retain_ten values = List.take values 10 in
        let file_descriptor =
          Core_unix.openfile path ~mode:[ O_RDONLY; O_CLOEXEC ] ~perm:0
        in
        Core_unix.flock_blocking
          file_descriptor
          Core_unix.Flock_command.lock_shared;
        let channel = Core_unix.in_channel_of_descr file_descriptor in
        Exn.protect
          ~f:(fun () ->
            In_channel.iter_lines channel ~f:(fun line ->
              Int.incr sequence;
              let metadata =
                try
                  line
                  |> Yojson.Safe.from_string
                  |> Sandwalk_protocol.Audit_event.metadata_of_yojson
                with
                | _ -> None
              in
              Option.iter metadata ~f:(fun metadata ->
                let invocation_id =
                  Sandwalk_protocol.Audit_event.metadata_invocation_id metadata
                in
                if not (String.equal invocation_id exclude_invocation_id)
                then (
                  let command =
                    Sandwalk_protocol.Audit_event.metadata_command metadata
                  in
                  match Sandwalk_protocol.Audit_event.metadata_kind metadata with
                  | `Started ->
                    Hashtbl.set
                      active
                      ~key:invocation_id
                      ~data:(!sequence, command)
                  | `Finished | `Failed ->
                    Hashtbl.remove active invocation_id;
                    recent :=
                      { command
                      ; timestamp =
                          Sandwalk_protocol.Audit_event.metadata_timestamp
                            metadata
                      ; outcome =
                          (Sandwalk_protocol.Audit_event.metadata_outcome metadata
                           |> Option.value ~default:"unknown")
                      ; error_code =
                          Sandwalk_protocol.Audit_event.metadata_error_code metadata
                      }
                      :: !recent;
                    recent := retain_ten !recent))))
          ~finally:(fun () -> In_channel.close channel);
        let unmatched_commands =
          Hashtbl.data active
          |> List.sort ~compare:(fun (left, _) (right, _) -> Int.compare left right)
          |> List.rev
          |> Fn.flip List.take 10
          |> List.rev
          |> List.map ~f:snd
        in
        { recent_commands = List.rev !recent; unmatched_commands }))
  ;;
end

module Atomic_file = struct
  let write_all file_descriptor value =
    let rec loop position =
      if position < String.length value
      then (
        let written =
          Core_unix.write_substring
            file_descriptor
            ~pos:position
            ~len:(String.length value - position)
            ~buf:value
        in
        loop (position + written))
    in
    loop 0
  ;;

  let write_blocking ~path ~temporary_suffix content =
    let temporary_path = path ^ ".tmp." ^ temporary_suffix in
    let renamed = ref false in
    Exn.protect
      ~f:(fun () ->
        let file_descriptor =
          Core_unix.openfile
            temporary_path
            ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
            ~perm:0o600
        in
        Exn.protect
          ~f:(fun () ->
            write_all file_descriptor content;
            Core_unix.fsync file_descriptor)
          ~finally:(fun () -> Core_unix.close file_descriptor);
        Core_unix.rename ~src:temporary_path ~dst:path;
        renamed := true)
      ~finally:(fun () ->
        if not !renamed
        then (
          try Core_unix.unlink temporary_path with
          | _ -> ()))
  ;;

  let write ~path ~temporary_suffix content =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () -> write_blocking ~path ~temporary_suffix content))
  ;;

  let write_exclusive ~path content =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let file_descriptor =
          Core_unix.openfile
            path
            ~mode:[ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ]
            ~perm:0o600
        in
        Exn.protect
          ~f:(fun () ->
            write_all file_descriptor content;
            Core_unix.fsync file_descriptor)
          ~finally:(fun () -> Core_unix.close file_descriptor)))
  ;;

  let persisted_version path =
    try
      In_channel.with_file path ~f:(fun channel ->
        let open Option.Let_syntax in
        let%bind line = In_channel.input_line channel in
        let%bind value =
          String.chop_prefix line ~prefix:"<!-- sandwalk-projection-version: "
        in
        let%bind value = String.chop_suffix value ~suffix:" -->" in
        Int.of_string_opt value)
      |> Option.value ~default:(-1)
    with
    | _ -> -1
  ;;

  let write_versioned
        ~path
        ~lock_path
        ~temporary_suffix
        ~version
        content
    =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let lock =
          Core_unix.openfile
            lock_path
            ~mode:[ O_RDWR; O_CREAT; O_CLOEXEC ]
            ~perm:0o600
        in
        Exn.protect
          ~f:(fun () ->
            Core_unix.flock_blocking
              lock
              Core_unix.Flock_command.lock_exclusive;
            if version >= persisted_version path
            then write_blocking ~path ~temporary_suffix content)
          ~finally:(fun () -> Core_unix.close lock)))
  ;;
end

module File_input = struct
  type t =
    { path : string
    ; content : string
    ; size : int
    ; md5 : string
    }

  let path t = t.path
  let content t = t.content
  let size t = t.size
  let md5 t = t.md5

  let read ~path ~maximum_bytes =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let content = In_channel.read_all path in
        let size = String.length content in
        if size > maximum_bytes
        then
          failwithf
            "File %s exceeds the %d-byte limit"
            path
            maximum_bytes
            ();
        { path; content; size; md5 = Md5.digest_string content |> Md5.to_hex }))
  ;;
end

module Adapter = struct
  let run_json ~executable ?(env = []) ~request ~timeout ~maximum_output_bytes () =
    Deferred.Or_error.try_with (fun () ->
      let search_path =
        Sys.getenv "PATH"
        |> Option.value ~default:""
        |> String.split ~on:':'
      in
      let%bind process =
        Process.create_exn
          ~env:(`Extend env)
          ~prog_search_path:search_path
          ~stdin:(Yojson.Safe.to_string request)
          ~prog:executable
          ~args:[]
          ()
      in
      let output = Process.collect_output_and_wait process in
      let%bind timed = Clock.with_timeout timeout output in
      let%bind output =
        match timed with
        | `Result output -> Deferred.return output
        | `Timeout ->
          Process.send_signal process Signal.kill;
          let%map _ = output in
          failwith "Adapter process timed out"
      in
      Core_unix.Exit_or_signal.or_error output.exit_status |> Or_error.ok_exn;
      if String.length output.stdout > maximum_output_bytes
      then failwith "Adapter output exceeded its byte limit";
      Yojson.Safe.from_string output.stdout |> Deferred.return)
  ;;
end

module Searxng = struct
  type search_guard =
    { lifecycle : Core_unix.File_descr.t
    ; activity : Core_unix.File_descr.t
    ; mutable lifecycle_released : bool
    ; mutable released : bool
    }

  type connection =
    { endpoint : string
    ; mode : string
    ; image_digest : string
    ; profile : string
    ; config_sha256 : string
    ; language : string
    ; safe_search : int
    }

  let state_directory () =
    match Sys.getenv "SANDWALK_SEARXNG_STATE_DIRECTORY" with
    | Some directory -> directory
    | None ->
      let home = Sys.getenv "HOME" |> Option.value ~default:"." in
      (match Sys.getenv "XDG_STATE_HOME" with
       | Some directory -> Filename.concat directory "sandwalk/searxng"
       | None ->
         if String.equal (Core_unix.uname () |> Core_unix.Utsname.sysname) "Darwin"
         then Filename.concat home "Library/Application Support/sandwalk/state/searxng"
         else Filename.concat home ".local/state/sandwalk/searxng")
  ;;

  let open_lock path =
    Core_unix.openfile
      path
      ~mode:[ O_RDWR; O_CREAT; O_CLOEXEC ]
      ~perm:0o600
  ;;

  let acquire_search_guard () =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        let directory = state_directory () in
        Core_unix.mkdir_p ~perm:0o700 directory;
        let lifecycle = open_lock (Filename.concat directory "lifecycle.lock") in
        let activity = open_lock (Filename.concat directory "activity.lock") in
        try
          Core_unix.flock_blocking
            lifecycle
            Core_unix.Flock_command.lock_exclusive;
          Core_unix.flock_blocking
            activity
            Core_unix.Flock_command.lock_shared;
          { lifecycle; activity; lifecycle_released = false; released = false }
        with
        | exn ->
          Core_unix.close lifecycle;
          Core_unix.close activity;
          raise exn))
  ;;

  let release_lifecycle guard =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        if not guard.lifecycle_released
        then (
          Core_unix.flock
            guard.lifecycle
            Core_unix.Flock_command.unlock
          |> ignore;
          Core_unix.close guard.lifecycle;
          guard.lifecycle_released <- true)))
  ;;

  let release_search_guard guard =
    Deferred.Or_error.try_with (fun () ->
      In_thread.run (fun () ->
        if not guard.released
        then (
          if not guard.lifecycle_released
          then (
            Core_unix.flock
              guard.lifecycle
              Core_unix.Flock_command.unlock
            |> ignore;
            Core_unix.close guard.lifecycle;
            guard.lifecycle_released <- true);
          Core_unix.flock guard.activity Core_unix.Flock_command.unlock |> ignore;
          Core_unix.close guard.activity;
          guard.released <- true)))
  ;;

  let service
        ?(environment = [])
        ~action
        ~arguments
        ~locks_held
        ()
    =
    let search_path =
      Sys.getenv "PATH"
      |> Option.value ~default:""
      |> String.split ~on:':'
    in
    let environment =
      if locks_held
      then ("SANDWALK_SEARXNG_LOCKS_HELD", "1") :: environment
      else ("SANDWALK_SEARXNG_LOCKS_HELD", "0") :: environment
    in
    let%bind started =
      Deferred.Or_error.try_with (fun () ->
        let%bind process =
          Process.create_exn
            ~env:(`Extend environment)
            ~prog_search_path:search_path
            ~prog:"sandwalk-searxng-service"
            ~args:
              (action
               :: "--state-directory"
               :: state_directory ()
               :: arguments)
            ()
        in
        Process.collect_output_and_wait process)
    in
    match started with
    | Error _ as error -> Deferred.return error
    | Ok output ->
      (match Core_unix.Exit_or_signal.or_error output.exit_status with
       | Error _ ->
         let detail =
           output.stderr
           |> String.split ~on:'\n'
           |> List.concat_map ~f:(String.split ~on:' ')
           |> List.filter ~f:(Fn.non String.is_empty)
           |> String.concat ~sep:" "
         in
         let detail =
           if String.is_empty detail then "SearXNG service helper failed" else detail
         in
         let detail =
           if String.length detail > 1_000
           then String.sub detail ~pos:0 ~len:1_000
           else detail
         in
         Deferred.return (Or_error.error_string detail)
       | Ok () ->
         Deferred.return
           (Or_error.try_with (fun () ->
              if String.length output.stdout > 262_144
              then failwith "SearXNG service response exceeded its byte limit";
              let response = Yojson.Safe.from_string output.stdout in
              match response with
              | `Assoc fields ->
                (match
                   List.Assoc.find fields "protocol" ~equal:String.equal,
                   List.Assoc.find fields "result" ~equal:String.equal
                 with
                 | ( Some (`String "sandwalk.searxng-service-result.v1")
                   , Some result ) -> result
                 | _ -> failwith "SearXNG service returned an invalid response")
              | _ -> failwith "SearXNG service returned an invalid response")))
  ;;

  let required_string fields name maximum =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value)
      when (not (String.is_empty value)) && String.length value <= maximum ->
      value
    | _ -> failwith ("SearXNG service omitted " ^ name)
  ;;

  let optional_string fields name maximum =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value) when String.length value <= maximum -> value
    | Some `Null | None -> ""
    | _ -> failwith ("SearXNG service returned an invalid " ^ name)
  ;;

  let required_int fields name ~minimum ~maximum =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`Int value) when value >= minimum && value <= maximum -> value
    | _ -> failwith ("SearXNG service omitted " ^ name)
  ;;

  let prepare ~search_guard:_ =
    service ~action:"prepare" ~arguments:[] ~locks_held:true ()
    >>| Or_error.map ~f:(function
      | `Assoc fields ->
        { endpoint = required_string fields "endpoint" 2_048
        ; mode = required_string fields "mode" 64
        ; image_digest = optional_string fields "image_digest" 128
        ; profile = required_string fields "profile" 128
        ; config_sha256 = required_string fields "config_sha256" 64
        ; language = required_string fields "language" 32
        ; safe_search = required_int fields "safe_search" ~minimum:0 ~maximum:2
        }
      | _ -> failwith "SearXNG service returned an invalid active configuration")
  ;;

  let touch ~search_guard:_ =
    service ~action:"touch" ~arguments:[] ~locks_held:true ()
    >>| Or_error.map ~f:(Fn.const ())
  ;;

  let endpoint t = t.endpoint
  let mode t = t.mode
  let image_digest t = t.image_digest
  let profile t = t.profile
  let config_sha256 t = t.config_sha256
  let language t = t.language
  let safe_search t = t.safe_search
end

let default_directory_prefix () =
  match Sys.getenv "XDG_DATA_HOME" with
  | Some directory -> Filename.concat directory "sandwalk"
  | None ->
    let home = Sys.getenv "HOME" |> Option.value ~default:"." in
    if String.equal (Core_unix.uname () |> Core_unix.Utsname.sysname) "Darwin"
    then Filename.concat home "Library/Application Support/sandwalk"
    else Filename.concat home ".local/share/sandwalk"
;;

let resolve_directory_prefix ~command_line =
  match command_line with
  | Some path -> path
  | None ->
    Sys.getenv "SANDWALK_DIRECTORY_PREFIX"
    |> Option.value ~default:(default_directory_prefix ())
;;

let timestamp_utc time =
  Time_float_unix.to_string_abs time ~zone:Time_float.Zone.utc
;;

let random_bits () =
    let file_descriptor =
      Core_unix.openfile "/dev/urandom" ~mode:[ O_RDONLY; O_CLOEXEC ] ~perm:0
    in
    Exn.protect
      ~f:(fun () ->
        let bytes = Bytes.create 16 in
        let rec read_all position =
          if position < Bytes.length bytes
          then (
            let count =
              Core_unix.read
                file_descriptor
                ~buf:bytes
                ~pos:position
                ~len:(Bytes.length bytes - position)
            in
            if count = 0 then failwith "Unexpected end of random source";
            read_all (position + count))
        in
        read_all 0;
        Bytes.to_string bytes)
      ~finally:(fun () -> Core_unix.close file_descriptor)
;;

let invocation_id ~now =
  let random_bits = random_bits () in
  Md5.digest_string
    (Float.to_string
       (Time_float.to_span_since_epoch now |> Time_float.Span.to_sec)
     ^ random_bits)
  |> Md5.to_hex
;;

let claim_id () =
  let suffix =
    random_bits ()
    |> String.concat_map ~f:(fun character ->
      sprintf "%02x" (Char.to_int character))
  in
  Sandwalk_core.Claim_id.of_string ("claim_" ^ suffix) |> Option.value_exn
;;

let hit_id () =
  let suffix =
    random_bits ()
    |> String.concat_map ~f:(fun character ->
      sprintf "%02x" (Char.to_int character))
  in
  Sandwalk_core.Hit_id.of_string ("hit_" ^ suffix) |> Option.value_exn
;;

let snapshot_id () =
  let suffix =
    random_bits ()
    |> String.concat_map ~f:(fun character ->
      sprintf "%02x" (Char.to_int character))
  in
  Sandwalk_core.Snapshot_id.of_string ("snap_" ^ suffix) |> Option.value_exn
;;

let excerpt_id () =
  let suffix =
    random_bits ()
    |> String.concat_map ~f:(fun character ->
      sprintf "%02x" (Char.to_int character))
  in
  Sandwalk_core.Excerpt_id.of_string ("excerpt_" ^ suffix) |> Option.value_exn
;;
