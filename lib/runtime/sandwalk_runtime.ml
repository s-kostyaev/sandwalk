open! Core
open! Async

module Workspace = struct
  type t =
    { root : string
    ; database_path : string
    ; events_path : string
    }

  let root t = t.root
  let database_path t = t.database_path
  let events_path t = t.events_path

  let create_layout ~directory_prefix ~slug =
    let root =
      Filename.concat directory_prefix (Sandwalk_core.Slug.to_string slug)
    in
    let directories =
      [ "database"
      ; "artifacts/snapshots"
      ; "artifacts/excerpts"
      ; "artifacts/resume"
      ; "artifacts/temporary"
      ; "exports"
      ; "logs"
      ]
    in
    Deferred.Or_error.try_with (fun () ->
      let%bind () = Unix.mkdir ~p:() root in
      let%map () =
        Deferred.List.iter directories ~how:`Sequential ~f:(fun directory ->
          Unix.mkdir ~p:() (Filename.concat root directory))
      in
      { root
      ; database_path = Filename.concat root "database/sandwalk.sqlite3"
      ; events_path = Filename.concat root "logs/events.jsonl"
      })
  ;;
end

module Audit = struct
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

let invocation_id ~now =
  let random_bits =
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
  in
  Md5.digest_string
    (Float.to_string
       (Time_float.to_span_since_epoch now |> Time_float.Span.to_sec)
     ^ random_bits)
  |> Md5.to_hex
;;
