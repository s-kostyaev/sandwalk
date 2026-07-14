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
    ; timestamp : string
    ; command : string
    ; outcome : string option
    ; error_code : string option
    }

  let metadata_kind t = t.kind
  let metadata_invocation_id t = t.invocation_id
  let metadata_timestamp t = t.timestamp
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
      let%bind timestamp = string_field fields "timestamp" in
      let%map command = string_field fields "command" in
      let outcome =
        match string_field fields "outcome" with
        | Some ("success" | "failure" as outcome) -> Some outcome
        | Some _ | None -> None
      in
      { kind
      ; invocation_id
      ; timestamp
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
    let hint =
      Option.value_map error_code ~default:`Null ~f:(fun code ->
        `Assoc
          [ "identifier", `String ("repair." ^ code)
          ; "template_version", `Int 1
          ; "follow_up_correlation", `String invocation_id
          ])
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
         ; Some ("hint", hint)
         ])
  ;;
end

module Shell_command = struct
  let quote value =
    "'" ^ String.substr_replace_all value ~pattern:"'" ~with_:"'\\''" ^ "'"
  ;;

  let of_words words = words |> List.map ~f:quote |> String.concat ~sep:" "
end

module Index_adapter = struct
  type error =
    | Invalid_envelope
    | Unsupported_protocol
  [@@deriving sexp_of]

  let request_documents ~source_root ~index_directory ~embedding_model =
    `Assoc
      [ "protocol", `String "sandwalk.index.v1"
      ; "mode", `String "documents"
      ; "source_root", `String source_root
      ; "index_directory", `String index_directory
      ; "embedding_model", `String embedding_model
      ]
  ;;

  let request_info ~manual ~index_directory ~embedding_model ~emacs =
    `Assoc
      [ "protocol", `String "sandwalk.index.v1"
      ; "mode", `String "info"
      ; "manual", `String manual
      ; "index_directory", `String index_directory
      ; "embedding_model", `String embedding_model
      ; "emacs", `Bool emacs
      ]
  ;;

  let manifest = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.index-result.v1") ->
         (match List.Assoc.find fields "manifest" ~equal:String.equal with
          | Some (`String value)
            when (not (String.is_empty value)) && String.length value <= 4_096 ->
            Ok value
          | Some _ | None -> Error Invalid_envelope)
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_envelope)
    | _ -> Error Invalid_envelope
  ;;
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

  let request ?source_root ~query ~limit () =
    `Assoc
      (List.filter_opt
         [ Some ("protocol", `String "sandwalk.search.v1")
         ; Some ("query", `String query)
         ; Some ("limit", `Int limit)
         ; Option.map source_root ~f:(fun root -> "source_root", `String root)
         ])
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
         || String.is_prefix url ~prefix:"https://"
         || String.is_prefix url ~prefix:"file://"
         || String.is_prefix url ~prefix:"info://texiq/"
         || String.is_prefix url ~prefix:"qmd://")
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
    ; document_artifact : string
    ; document_media_type : string
    ; document_sha256 : string
    ; structure_artifact : string option
    ; structure_sha256 : string option
    }

  type error =
    | Invalid_manifest
    | Unsupported_protocol
    | Queryability_check_failed
  [@@deriving sexp_of]

  let request ?source_root ~url ~output_directory () =
    `Assoc
      (List.filter_opt
         [ Some ("protocol", `String "sandwalk.fetch.v1")
         ; Some ("url", `String url)
         ; Some ("output_directory", `String output_directory)
         ; Option.map source_root ~f:(fun root -> "source_root", `String root)
         ])
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

  let artifact_basename value =
    (not (String.is_empty value))
    && String.equal value (Filename.basename value)
    && not (List.mem [ "."; ".." ] value ~equal:String.equal)
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
           let document_sha256 =
             match
               string_field hashes "normalized_document_sha256",
               string_field hashes "normalized_markdown_sha256"
             with
             | Some document, Some markdown when String.equal document markdown ->
               Some document
             | Some document, None -> Some document
             | None, Some markdown -> Some markdown
             | Some _, Some _ | None, None -> None
           in
           let%bind document_sha256 in
           let artifacts = assoc_field fields "artifacts" in
           let document_artifact =
             artifacts
             |> Option.bind ~f:(fun artifacts ->
               string_field artifacts "document")
             |> Option.value ~default:"document.md"
           in
           let document_media_type =
             string_field fields "document_media_type"
             |> Option.value ~default:"text/markdown"
           in
           let structure_artifact =
             artifacts
             |> Option.bind ~f:(fun artifacts -> string_field artifacts "structure")
           in
           let structure_sha256 = string_field hashes "structure_sha256" in
           let%bind queryability = assoc_field fields "queryability_check" in
           let%bind queryable =
             match List.Assoc.find queryability "ok" ~equal:String.equal with
             | Some (`Bool value) -> Some value
             | Some _ | None -> None
           in
           Some
             ( final_url
             , input_sha256
             , document_artifact
             , document_media_type
             , document_sha256
             , structure_artifact
             , structure_sha256
             , queryable )
         in
         (match parsed with
          | Some (_, _, _, _, _, _, _, false) -> Error Queryability_check_failed
          | Some
              ( final_url
              , input_sha256
              , document_artifact
              , document_media_type
              , document_sha256
              , structure_artifact
              , structure_sha256
              , true )
            when (String.is_prefix final_url ~prefix:"http://"
                  || String.is_prefix final_url ~prefix:"https://"
                  || String.is_prefix final_url ~prefix:"file://"
                  || String.is_prefix final_url ~prefix:"info://texiq/"
                  || String.is_prefix final_url ~prefix:"qmd://")
                 && sha256 input_sha256
                 && artifact_basename document_artifact
                 && List.mem
                      [ "text/markdown"; "text/plain" ]
                      document_media_type
                      ~equal:String.equal
                 && sha256 document_sha256
                 &&
                 (match structure_artifact, structure_sha256 with
                  | None, None -> true
                  | Some artifact, Some hash ->
                    artifact_basename artifact && sha256 hash
                  | None, Some _ | Some _, None -> false)
                 &&
                 (not (String.is_prefix final_url ~prefix:"file://")
                  || String.equal document_media_type "text/plain"
                  || Option.is_some structure_artifact) ->
            Ok
              { final_url
              ; input_sha256
              ; document_artifact
              ; document_media_type
              ; document_sha256
              ; structure_artifact
              ; structure_sha256
              }
          | Some _ | None -> Error Invalid_manifest)
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_manifest)
    | _ -> Error Invalid_manifest
  ;;

  let validate_manifest json = manifest json |> Result.map ~f:ignore
  let final_url t = t.final_url
  let input_sha256 t = t.input_sha256
  let document_artifact t = t.document_artifact
  let document_media_type t = t.document_media_type
  let document_sha256 t = t.document_sha256
  let markdown_sha256 t = t.document_sha256
  let structure_artifact t = t.structure_artifact
  let structure_sha256 t = t.structure_sha256
end

module Export_adapter = struct
  type manifest =
    { format : string
    ; artifact_path : string
    ; media_type : string
    ; artifact_md5 : string
    ; inputs : (string * string) list
    }

  type error =
    | Invalid_manifest
    | Unsupported_protocol
  [@@deriving sexp_of]

  let request ~format ~inputs ~output_directory =
    `Assoc
      [ "protocol", `String "sandwalk.export.v1"
      ; "format", `String format
      ; ( "inputs"
        , `List
            (List.map inputs ~f:(fun (role, path, md5) ->
               `Assoc
                 [ "role", `String role
                 ; "path", `String path
                 ; "md5", `String md5
                 ])) )
      ; "output_directory", `String output_directory
      ]
  ;;

  let string_field fields name =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value) -> Some value
    | Some _ | None -> None
  ;;

  let assoc_field fields name =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`Assoc value) -> Some value
    | Some _ | None -> None
  ;;

  let md5 value =
    String.length value = 32
    && String.for_all value ~f:(function
      | '0' .. '9' | 'a' .. 'f' -> true
      | _ -> false)
  ;;

  let safe_name value =
    (not (String.is_empty value))
    && String.length value <= 128
    && String.equal value (Filename.basename value)
    && not (String.equal value "." || String.equal value "..")
  ;;

  let input = function
    | `Assoc fields ->
      let open Option.Let_syntax in
      let%bind role = string_field fields "role" in
      let%bind digest = string_field fields "md5" in
      if safe_name role && md5 digest then Some (role, digest) else None
    | _ -> None
  ;;

  let manifest = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.export-manifest.v1") ->
         let open Option.Let_syntax in
         let parsed =
           let%bind format = string_field fields "format" in
           let%bind artifact = assoc_field fields "artifact" in
           let%bind artifact_path = string_field artifact "path" in
           let%bind media_type = string_field artifact "media_type" in
           let%bind artifact_md5 = string_field artifact "md5" in
           let%bind inputs =
             match List.Assoc.find fields "inputs" ~equal:String.equal with
             | Some (`List values) when List.length values <= 16 ->
               values |> List.map ~f:input |> Option.all
             | Some _ | None -> None
           in
           Some
             { format
             ; artifact_path
             ; media_type
             ; artifact_md5
             ; inputs
             }
         in
         (match parsed with
          | Some manifest
            when safe_name manifest.format
                 && safe_name manifest.artifact_path
                 && (not (String.is_empty manifest.media_type))
                 && String.length manifest.media_type <= 128
                 && md5 manifest.artifact_md5
                 && not
                      (List.contains_dup
                         manifest.inputs
                         ~compare:(fun (left, _) (right, _) ->
                           String.compare left right)) ->
            Ok manifest
          | Some _ | None -> Error Invalid_manifest)
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_manifest)
    | _ -> Error Invalid_manifest
  ;;

  let format t = t.format
  let artifact_path t = t.artifact_path
  let media_type t = t.media_type
  let artifact_md5 t = t.artifact_md5
  let input_md5 t role = List.Assoc.find t.inputs role ~equal:String.equal
end

module Finding_review = struct
  type verdict =
    | Supported
    | Partially_supported
    | Unsupported
    | Contradicted

  type t =
    { verdict : verdict
    ; summary : string
    ; source_quality : string
    ; conflicts : string
    ; qualifications : string
    }

  type error =
    | Invalid_review
    | Unsupported_protocol
  [@@deriving sexp_of]

  let bounded_string fields name =
    match List.Assoc.find fields name ~equal:String.equal with
    | Some (`String value) when String.length value <= 4_000 -> Some value
    | Some _ | None -> None
  ;;

  let verdict_of_string = function
    | "supported" -> Some Supported
    | "partially-supported" -> Some Partially_supported
    | "unsupported" -> Some Unsupported
    | "contradicted" -> Some Contradicted
    | _ -> None
  ;;

  let verdict_to_string = function
    | Supported -> "supported"
    | Partially_supported -> "partially-supported"
    | Unsupported -> "unsupported"
    | Contradicted -> "contradicted"
  ;;

  let decode = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.finding-review.v1") ->
         let open Option.Let_syntax in
         let parsed =
           let%bind verdict_text = bounded_string fields "verdict" in
           let%bind verdict = verdict_of_string verdict_text in
           let%bind summary = bounded_string fields "summary" in
           let%bind source_quality = bounded_string fields "source_quality" in
           let%bind conflicts = bounded_string fields "conflicts" in
           let%bind qualifications = bounded_string fields "qualifications" in
           if String.is_empty (String.strip summary)
           then None
           else
             Some
               { verdict; summary; source_quality; conflicts; qualifications }
         in
         Result.of_option parsed ~error:Invalid_review
       | Some (`String _) -> Error Unsupported_protocol
       | Some _ | None -> Error Invalid_review)
    | _ -> Error Invalid_review
  ;;

  let verdict t = t.verdict
  let summary t = t.summary
  let source_quality t = t.source_quality
  let conflicts t = t.conflicts
  let qualifications t = t.qualifications
end

module Report_review = struct
  type block =
    { ordinal : int
    ; block_md5 : string
    ; verdict : Finding_review.verdict
    ; summary : string
    }

  type t =
    { report_revision : int
    ; blocks : block list
    }

  type error =
    | Invalid_review
    | Unsupported_protocol
    | Too_many_blocks
    | Duplicate_ordinal
  [@@deriving sexp_of]

  let md5 value =
    String.length value = 32
    && String.for_all value ~f:(function
      | '0' .. '9' | 'a' .. 'f' -> true
      | _ -> false)
  ;;

  let block = function
    | `Assoc fields ->
      let open Option.Let_syntax in
      let%bind ordinal =
        match List.Assoc.find fields "ordinal" ~equal:String.equal with
        | Some (`Int value) when value >= 1 -> Some value
        | _ -> None
      in
      let%bind block_md5 =
        match List.Assoc.find fields "block_md5" ~equal:String.equal with
        | Some (`String value) when md5 value -> Some value
        | _ -> None
      in
      let%bind verdict =
        match List.Assoc.find fields "verdict" ~equal:String.equal with
        | Some (`String value) -> Finding_review.verdict_of_string value
        | _ -> None
      in
      let%bind summary =
        match List.Assoc.find fields "summary" ~equal:String.equal with
        | Some (`String value)
          when (not (String.is_empty (String.strip value)))
               && String.length value <= 4_000 ->
          Some value
        | _ -> None
      in
      Some { ordinal; block_md5; verdict; summary }
    | _ -> None
  ;;

  let decode = function
    | `Assoc fields ->
      (match List.Assoc.find fields "protocol" ~equal:String.equal with
       | Some (`String "sandwalk.report-review.v1") ->
         let open Result.Let_syntax in
         let%bind report_revision =
           match List.Assoc.find fields "report_revision" ~equal:String.equal with
           | Some (`Int value) when value >= 1 -> Ok value
           | _ -> Error Invalid_review
         in
         let%bind blocks =
           match List.Assoc.find fields "blocks" ~equal:String.equal with
           | Some (`List values) when List.length values <= 256 ->
             values
             |> List.map ~f:block
             |> Option.all
             |> Result.of_option ~error:Invalid_review
           | Some (`List _) -> Error Too_many_blocks
           | _ -> Error Invalid_review
         in
         let ordinals =
           List.map blocks ~f:(fun block -> block.ordinal)
         in
         if
           List.length ordinals
           <> List.length (List.dedup_and_sort ordinals ~compare:Int.compare)
         then Error Duplicate_ordinal
         else Ok { report_revision; blocks }
       | Some (`String _) -> Error Unsupported_protocol
       | _ -> Error Invalid_review)
    | _ -> Error Invalid_review
  ;;

  let report_revision t = t.report_revision
  let blocks t = t.blocks
  let ordinal t = t.ordinal
  let block_md5 t = t.block_md5
  let verdict t = t.verdict
  let summary t = t.summary
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
    (Some "DATABASE_ERROR");
  match Yojson.Safe.Util.member "hint" json with
  | `Assoc fields ->
    (match List.Assoc.find fields "identifier" ~equal:String.equal with
     | Some (`String identifier) ->
       [%test_eq: string] identifier "repair.DATABASE_ERROR"
     | _ -> failwith "expected internal hint identifier")
  | _ -> failwith "expected internal hint metadata"
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

let%expect_test "index adapters have explicit document and Info requests" =
  Index_adapter.request_documents
    ~source_root:"/tmp/docs"
    ~index_directory:"/tmp/index"
    ~embedding_model:"hf:model"
  |> Yojson.Safe.to_string
  |> print_endline;
  Index_adapter.request_info
    ~manual:"ellama"
    ~index_directory:"/tmp/info-index"
    ~embedding_model:"hf:model"
    ~emacs:true
  |> Yojson.Safe.to_string
  |> print_endline;
  `Assoc
    [ "protocol", `String "sandwalk.index-result.v1"
    ; "manifest", `String "/tmp/index/manifest.json"
    ]
  |> Index_adapter.manifest
  |> [%sexp_of: (string, Index_adapter.error) Result.t]
  |> print_s;
  [%expect
    {|
    {"protocol":"sandwalk.index.v1","mode":"documents","source_root":"/tmp/docs","index_directory":"/tmp/index","embedding_model":"hf:model"}
    {"protocol":"sandwalk.index.v1","mode":"info","manual":"ellama","index_directory":"/tmp/info-index","embedding_model":"hf:model","emacs":true}
    (Ok /tmp/index/manifest.json) |}]
;;

let%expect_test "search protocol accepts semantic index locators" =
  `Assoc
    [ "protocol", `String "sandwalk.search-results.v1"
    ; ( "results"
      , `List
          [ `Assoc
              [ "url", `String "qmd://0123456789abcdef0123456789abcdef/fedcba9876543210fedcba9876543210"
              ; "title", `String "Indexed document"
              ; "snippet", `String "Discovery-only text"
              ]
          ] )
    ]
  |> Search_adapter.results
  |> Result.map ~f:List.length
  |> [%sexp_of: (int, Search_adapter.error) Result.t]
  |> print_s;
  [%expect {| (Ok 1) |}]
;;

let%expect_test "search and fetch protocols accept texiq Info locators" =
  let locator = "info://texiq/L3RtcC9lbGxhbWEuaW5mbw==#VXNpbmcgQmx1ZXByaW50cw==" in
  `Assoc
    [ "protocol", `String "sandwalk.search-results.v1"
    ; ( "results"
      , `List
          [ `Assoc
              [ "url", `String locator
              ; "title", `String "ellama — Using Blueprints"
              ; "snippet", `String "Reusable prompt templates."
              ]
          ] )
    ]
  |> Search_adapter.results
  |> Result.map ~f:List.length
  |> [%sexp_of: (int, Search_adapter.error) Result.t]
  |> print_s;
  `Assoc
    [ "protocol", `String "sandwalk.fetch-manifest.v1"
    ; "final_url", `String locator
    ; "document_media_type", `String "text/plain"
    ; ( "hashes"
      , `Assoc
          [ "input_sha256", `String (String.make 64 'a')
          ; "normalized_document_sha256", `String (String.make 64 'b')
          ] )
    ; "artifacts", `Assoc [ "document", `String "document.txt" ]
    ; "queryability_check", `Assoc [ "ok", `Bool true ]
    ]
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  [%expect
    {|
    (Ok 1)
    (Ok ()) |}]
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

let%expect_test "local fetch manifests require a structured artifact" =
  let manifest artifacts structure_hash =
    `Assoc
      [ "protocol", `String "sandwalk.fetch-manifest.v1"
      ; "final_url", `String "file:///documents/report.pdf"
      ; ( "hashes"
        , `Assoc
            (List.filter_opt
               [ Some ("input_sha256", `String (String.make 64 'a'))
               ; Some
                   ( "normalized_markdown_sha256"
                   , `String (String.make 64 'b') )
               ; Option.map structure_hash ~f:(fun hash ->
                   "structure_sha256", `String hash)
               ]) )
      ; "artifacts", `Assoc artifacts
      ; "queryability_check", `Assoc [ "ok", `Bool true ]
      ]
  in
  manifest [] None
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  manifest
    [ "structure", `String "document.json" ]
    (Some (String.make 64 'c'))
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  [%expect
    {|
    (Error Invalid_manifest)
    (Ok ()) |}]
;;

let%expect_test "fetch manifests can declare a plain-text primary document" =
  let manifest ?(final_url = "https://example.test/transcript") artifact media_type =
    `Assoc
      [ "protocol", `String "sandwalk.fetch-manifest.v1"
      ; "final_url", `String final_url
      ; "document_media_type", `String media_type
      ; ( "hashes"
        , `Assoc
            [ "input_sha256", `String (String.make 64 'a')
            ; "normalized_document_sha256", `String (String.make 64 'b')
            ] )
      ; "artifacts", `Assoc [ "document", `String artifact ]
      ; "queryability_check", `Assoc [ "ok", `Bool true ]
      ]
  in
  manifest "transcript.txt" "text/plain"
  |> Fetch_adapter.manifest
  |> Result.map ~f:(fun value ->
    Fetch_adapter.document_artifact value, Fetch_adapter.document_media_type value)
  |> [%sexp_of: ((string * string), Fetch_adapter.error) Result.t]
  |> print_s;
  manifest "../transcript.txt" "text/plain"
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  manifest
    ~final_url:"file:///documents/source.el"
    "document.txt"
    "text/plain"
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  manifest "transcript.txt" "application/octet-stream"
  |> Fetch_adapter.validate_manifest
  |> [%sexp_of: (unit, Fetch_adapter.error) Result.t]
  |> print_s;
  [%expect
    {|
    (Ok (transcript.txt text/plain))
    (Error Invalid_manifest)
    (Ok ())
    (Error Invalid_manifest) |}]
;;

let%expect_test "finding reviews are versioned and agent-authored" =
  `Assoc
    [ "protocol", `String "sandwalk.finding-review.v1"
    ; "verdict", `String "partially-supported"
    ; "summary", `String "The exact excerpt supports the narrow claim."
    ; "source_quality", `String "Primary source."
    ; "conflicts", `String ""
    ; "qualifications", `String "Keep the claim narrow."
    ]
  |> Finding_review.decode
  |> Result.map ~f:(fun review ->
    Finding_review.verdict review |> Finding_review.verdict_to_string)
  |> [%sexp_of: (string, Finding_review.error) Result.t]
  |> print_s;
  [%expect {| (Ok partially-supported) |}]
;;

let%expect_test "report reviews bind verdicts to exact block hashes" =
  `Assoc
    [ "protocol", `String "sandwalk.report-review.v1"
    ; "report_revision", `Int 1
    ; ( "blocks"
      , `List
          [ `Assoc
              [ "ordinal", `Int 1
              ; "block_md5", `String (String.make 32 'a')
              ; "verdict", `String "supported"
              ; "summary", `String "Exact support."
              ]
          ] )
    ]
  |> Report_review.decode
  |> Result.map ~f:(fun review -> List.length (Report_review.blocks review))
  |> [%sexp_of: (int, Report_review.error) Result.t]
  |> print_s;
  [%expect {| (Ok 1) |}]
;;
