open! Core

let version = "0.1.0-dev"

let about_command =
  Command.basic
    ~summary:"Print Sandwalk build information as a JSON response."
    (let%map_open.Command () = return () in
     fun () ->
       let result =
         `Assoc [ "name", `String "sandwalk"; "version", `String version ]
       in
       Sandwalk_protocol.Envelope.success ~result ()
       |> Sandwalk_protocol.Envelope.render
       |> print_endline)
;;

let command =
  Command.group
    ~summary:"Deterministic research orchestration for AI agents."
    [ "about", about_command ]
;;

let () = Command_unix.run command
