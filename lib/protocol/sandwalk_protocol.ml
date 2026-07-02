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

module Search_adapter = struct
  type result =
    { url : string
    ; title : string
    ; snippet : string
    }

  type error =
    | Invalid_envelope
    | Unsupported_protocol
    | Too_many_results
    | Invalid_result
  [@@deriving sexp_of]

  let request ~query ~limit =
    `Assoc
      [ "protocol", `String "sandwalk.search.v1"
      ; "query", `String query
      ; "limit", `Int limit
      ]
  ;;

  let string_field fields name maximum =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value) when String.length value <= maximum -> Some value
    | Some _ | None -> None
  ;;

  let result = function
    | `Assoc fields ->
      let open Option.Let_syntax in
      let%bind url = string_field fields "url" 2048 in
      let%bind title = string_field fields "title" 500 in
      let%bind snippet = string_field fields "snippet" 1000 in
      if
        (String.is_prefix url ~prefix:"http://"
         || String.is_prefix url ~prefix:"https://")
        && not (String.is_empty title)
      then Some { url; title; snippet }
      else None
    | _ -> None
  ;;

  let results = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.search-results.v1") ->
         (match List.Assoc.find fields "results" ~equal:String.equal with
          | Some (`List values) when List.length values <= 25 ->
            values
            |> List.map ~f:result
            |> Option.all
            |> Result.of_option ~error:Invalid_result
          | Some (`List _) -> Error Too_many_results
          | Some _ | None -> Error Invalid_envelope)
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_envelope)
    | _ -> Error Invalid_envelope
  ;;

  let url t = t.url
  let title t = t.title
  let snippet t = t.snippet
end

module Fetch_adapter = struct
  type manifest =
    { final_url : string
    ; input_sha256 : string
    ; markdown_sha256 : string
    }

  type error =
    | Invalid_manifest
    | Unsupported_protocol
    | Queryability_check_failed
  [@@deriving sexp_of]

  let request ~url ~output_directory =
    `Assoc
      [ "protocol", `String "sandwalk.fetch.v1"
      ; "url", `String url
      ; "output_directory", `String output_directory
      ]
  ;;

  let assoc_field fields name =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`Assoc value) -> Some value
    | Some _ | None -> None
  ;;

  let string_field fields name =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value) -> Some value
    | Some _ | None -> None
  ;;

  let sha256 value =
    String.length value = 64
    && String.for_all value ~f:(function
      | '0' .. '9' | 'a' .. 'f' -> true
      | _ -> false)
  ;;

  let manifest = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.fetch-manifest.v1") ->
         let open Option.Let_syntax in
         let parsed =
           let%bind final_url = string_field fields "final_url" in
           let%bind hashes = assoc_field fields "hashes" in
           let%bind input_sha256 = string_field hashes "input_sha256" in
           let%bind markdown_sha256 =
             string_field hashes "normalized_markdown_sha256"
           in
           let%bind queryability = assoc_field fields "queryability_check" in
           let%bind queryable =
             match List.Assoc.find queryability "ok" ~equal:String.equal with
             | Some (`Bool value) -> Some value
             | Some _ | None -> None
           in
           Some (final_url, input_sha256, markdown_sha256, queryable)
         in
         (match parsed with
          | Some (_, _, _, false) -> Error Queryability_check_failed
          | Some (final_url, input_sha256, markdown_sha256, true)
            when (String.is_prefix final_url ~prefix:"http://"
                  || String.is_prefix final_url ~prefix:"https://")
                 && sha256 input_sha256
                 && sha256 markdown_sha256 ->
            Ok { final_url; input_sha256; markdown_sha256 }
          | Some _ | None -> Error Invalid_manifest)
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_manifest)
    | _ -> Error Invalid_manifest
  ;;

  let validate_manifest json = manifest json |> Result.map ~f:ignore
  let final_url t = t.final_url
  let input_sha256 t = t.input_sha256
  let markdown_sha256 t = t.markdown_sha256
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

let%expect_test "search adapter responses are versioned and bounded" =
  let response =
    `Assoc
      [ "protocol", `String "sandwalk.search-results.v1"
      ; ( "results"
        , `List
            [ `Assoc
                [ "url", `String "https://example.test"
                ; "title", `String "Example"
                ; "snippet", `String "Bounded"
                ]
            ] )
      ]
  in
  Search_adapter.results response
  |> Result.map ~f:(fun results -> List.length results)
  |> [%sexp_of: (int, Search_adapter.error) Result.t]
  |> print_s;
  [%expect {| (Ok 1) |}]
;;

let%expect_test "fetch manifests require a successful mq gate" =
  `Assoc
    [ "protocol", `String "sandwalk.fetch-manifest.v1"
    ; "final_url", `String "https://example.test"
    ; ( "hashes"
      , `Assoc
          [ "input_sha256", `String (String.make 64 'a')
          ; "normalized_markdown_sha256", `String (String.make 64 'b')
          ] )
    ; "queryability_check", `Assoc [ "ok", `Bool false ]
    ]
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  [%expect {| (Error Queryability_check_failed) |}]
;;
