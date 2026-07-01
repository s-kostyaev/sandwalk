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
  type kind =
    [ `Started
    | `Finished
    | `Failed
    ]

  type metadata =
    { kind : kind
    ; invocation_id : string
    ; command : string
    ; outcome : string option
    ; error_code : string option
    }

  let metadata_kind t = t.kind
  let metadata_invocation_id t = t.invocation_id
  let metadata_command t = t.command
  let metadata_outcome t = t.outcome
  let metadata_error_code t = t.error_code

  let metadata_of_yojson json =
    let string_field fields name =
      List.Assoc.find fields name ~equal:String.equal
      |> Option.bind ~f:(function
        | `String value -> Some value
        | _ -> None)
    in
    match json with
    | `Assoc fields ->
      let open Option.Let_syntax in
      let%bind version =
        List.Assoc.find fields "version" ~equal:String.equal
        |> Option.bind ~f:(function
          | `Int value -> Some value
          | _ -> None)
      in
      let%bind () = if version = 1 then Some () else None in
      let%bind event = string_field fields "event" in
      let%bind kind =
        match event with
        | "command.started" -> Some `Started
        | "command.finished" -> Some `Finished
        | "command.failed" -> Some `Failed
        | _ -> None
      in
      let%bind invocation_id = string_field fields "invocation_id" in
      let%map command = string_field fields "command" in
      let outcome =
        match string_field fields "outcome" with
        | Some ("success" | "failure" as outcome) -> Some outcome
        | Some _ | None -> None
      in
      { kind
      ; invocation_id
      ; command
      ; outcome
      ; error_code = string_field fields "error_code"
      }
    | _ -> None
  ;;

  let create
        ~invocation_id
        ~timestamp
        ~kind
        ~command
        ~phase
        ~raw_argv
        ~arguments
        ~state_changes
        ?claim
        ?step
        ?(consumed_references = [])
        ?(created_references = [])
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
         ; Some
             ( "claim"
             , Option.value_map claim ~default:`Null ~f:(fun value -> `String value)
             )
         ; Some
             ( "step"
             , Option.value_map step ~default:`Null ~f:(fun value -> `String value)
             )
         ; Some
             ( "raw_argv"
             , `List (List.map raw_argv ~f:(fun argument -> `String argument)) )
         ; Some ("arguments", arguments)
         ; Some
             ( "consumed_references"
             , `List
                 (List.map consumed_references ~f:(fun value -> `String value)) )
         ; Some
             ( "created_references"
             , `List
                 (List.map created_references ~f:(fun value -> `String value)) )
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

module Shell_command = struct
  let quote value =
    "'" ^ String.substr_replace_all value ~pattern:"'" ~with_:"'\\''" ^ "'"
  ;;

  let of_words words = words |> List.map ~f:quote |> String.concat ~sep:" "
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

let%test_unit "audit metadata decodes recovery fields" =
  let json =
    Audit_event.create
      ~invocation_id:"invocation-1"
      ~timestamp:"2026-07-01 12:00:00Z"
      ~kind:`Failed
      ~command:"status"
      ~phase:None
      ~raw_argv:[]
      ~arguments:(`Assoc [])
      ~state_changes:[]
      ~outcome:"failure"
      ~error_code:"DATABASE_ERROR"
      ()
  in
  let metadata = Audit_event.metadata_of_yojson json |> Option.value_exn in
  [%test_eq: string]
    (Audit_event.metadata_invocation_id metadata)
    "invocation-1";
  [%test_eq: string option]
    (Audit_event.metadata_error_code metadata)
    (Some "DATABASE_ERROR")
;;

let%expect_test "shell commands quote every word" =
  Shell_command.of_words [ "sandwalk"; "status"; "--slug"; "researcher's-notes" ]
  |> print_endline;
  [%expect
    {| 'sandwalk' 'status' '--slug' 'researcher'\''s-notes' |}]
;;

let%test_unit "claim audit events carry capability and step context" =
  let claim = "claim_0123456789abcdef0123456789abcdef" in
  let json =
    Audit_event.create
      ~invocation_id:"invocation-1"
      ~timestamp:"2026-07-02 12:00:00Z"
      ~kind:`Finished
      ~command:"step claim"
      ~phase:(Some "researching")
      ~claim
      ~step:"primary"
      ~raw_argv:[]
      ~arguments:(`Assoc [])
      ~state_changes:[]
      ~created_references:[ claim ]
      ()
  in
  let open Yojson.Safe.Util in
  [%test_eq: string] (json |> member "claim" |> to_string) claim;
  [%test_eq: string] (json |> member "step" |> to_string) "primary";
  [%test_eq: string]
    (json |> member "created_references" |> to_list |> List.hd_exn |> to_string)
    claim
;;
