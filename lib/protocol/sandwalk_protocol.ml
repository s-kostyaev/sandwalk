open! Core

module Error = struct
  type t =
    { code : string
    ; message : string
    }
end

module Envelope = struct
  type t =
    { ok : bool
    ; result : Yojson.Safe.t option
    ; error : Error.t option
    ; next : string option
    }

  let success ?next ~result () = { ok = true; result = Some result; error = None; next }

  let failure ?next ~code ~message () =
    { ok = false; result = None; error = Some { Error.code; message }; next }
  ;;

  let to_yojson { ok; result; error; next } =
    let fields = [ "ok", `Bool ok ] in
    let fields =
      match result with
      | None -> fields
      | Some value -> fields @ [ "result", value ]
    in
    let fields =
      match error with
      | None -> fields
      | Some { Error.code; message } ->
        fields
        @ [ "error", `Assoc [ "code", `String code; "message", `String message ] ]
    in
    let fields =
      match next with
      | None -> fields
      | Some command -> fields @ [ "next", `String command ]
    in
    `Assoc fields
  ;;

  let render t = t |> to_yojson |> Yojson.Safe.to_string
end

module Audit_event = struct
  let create
        ~invocation_id
        ~timestamp
        ~kind
        ~command
        ~phase
        ~raw_argv
        ~arguments
        ~state_changes
        ?duration_ms
        ?outcome
        ?error_code
        ()
    =
    let kind =
      match kind with
      | `Started -> "command.started"
      | `Finished -> "command.finished"
      | `Failed -> "command.failed"
    in
    let optional name value =
      Option.map value ~f:(fun value -> name, value)
    in
    `Assoc
      (List.filter_opt
         [ Some ("version", `Int 1)
         ; Some ("event", `String kind)
         ; Some ("invocation_id", `String invocation_id)
         ; Some ("timestamp", `String timestamp)
         ; Some ("command", `String command)
         ; Some
             ( "phase"
             , Option.value_map phase ~default:`Null ~f:(fun value -> `String value)
             )
         ; Some ("claim", `Null)
         ; Some ("step", `Null)
         ; Some
             ( "raw_argv"
             , `List (List.map raw_argv ~f:(fun argument -> `String argument)) )
         ; Some ("arguments", arguments)
         ; Some ("consumed_references", `List [])
         ; Some ("created_references", `List [])
         ; Some ("state_changes", `List state_changes)
         ; optional
             "duration_ms"
             (Option.map duration_ms ~f:(fun value -> `Int value))
         ; optional "outcome" (Option.map outcome ~f:(fun value -> `String value))
         ; optional
             "error_code"
             (Option.map error_code ~f:(fun value -> `String value))
         ; Some ("hint", `Null)
         ])
  ;;
end

let%expect_test "renders a compact failure with one next command" =
  Envelope.failure
    ~code:"PLAN_NOT_VALIDATED"
    ~message:"Plan must be validated before sealing."
    ~next:"sandwalk plan validate --slug 'typed-harness'"
    ()
  |> Envelope.render
  |> print_endline;
  [%expect
    {| {"ok":false,"error":{"code":"PLAN_NOT_VALIDATED","message":"Plan must be validated before sealing."},"next":"sandwalk plan validate --slug 'typed-harness'"} |}]
;;

let%expect_test "renders a versioned finished audit event" =
  Audit_event.create
    ~invocation_id:"internal-1"
    ~timestamp:"2026-07-01 12:00:00.000000Z"
    ~kind:`Finished
    ~command:"init"
    ~phase:(Some "initialized")
    ~raw_argv:[ "sandwalk"; "init"; "--slug"; "typed-harness" ]
    ~arguments:(`Assoc [ "slug", `String "typed-harness" ])
    ~state_changes:
      [ `Assoc
          [ "entity", `String "workspace"
          ; "from", `Null
          ; "to", `String "initialized"
          ]
      ]
    ~duration_ms:2
    ~outcome:"success"
    ()
  |> Yojson.Safe.to_string
  |> print_endline;
  [%expect
    {| {"version":1,"event":"command.finished","invocation_id":"internal-1","timestamp":"2026-07-01 12:00:00.000000Z","command":"init","phase":"initialized","claim":null,"step":null,"raw_argv":["sandwalk","init","--slug","typed-harness"],"arguments":{"slug":"typed-harness"},"consumed_references":[],"created_references":[],"state_changes":[{"entity":"workspace","from":null,"to":"initialized"}],"duration_ms":2,"outcome":"success","hint":null} |}]
;;
