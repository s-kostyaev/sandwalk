open! Core

module Slug = struct
  module Error = struct
    type t =
      | Empty
      | Too_long
      | Invalid_format
    [@@deriving equal, sexp_of]

    let message = function
      | Empty -> "Slug must not be empty."
      | Too_long -> "Slug must contain at most 63 characters."
      | Invalid_format ->
        "Slug must use lowercase letters or digits, separated by single hyphens."
    ;;
  end

  type t = string

  let is_lowercase_letter_or_digit = function
    | 'a' .. 'z' | '0' .. '9' -> true
    | _ -> false
  ;;

  let has_valid_format value =
    String.for_alli value ~f:(fun index character ->
      if Char.equal character '-'
      then (
        index > 0
        && index < String.length value - 1
        && is_lowercase_letter_or_digit value.[index - 1]
        && is_lowercase_letter_or_digit value.[index + 1])
      else is_lowercase_letter_or_digit character)
  ;;

  let of_string value =
    if String.is_empty value
    then Error Error.Empty
    else if String.length value > 63
    then Error Error.Too_long
    else if not (has_valid_format value)
    then Error Error.Invalid_format
    else Ok value
  ;;

  let to_string t = t
end

module Phase = struct
  type t =
    | Initialized
    | Scoping
    | Reconnaissance
    | Planning
    | Researching
    | Evidence_review
    | Drafting
    | Draft_review
    | Finalizing
    | Completed
  [@@deriving compare, equal, sexp]

  let to_string = function
    | Initialized -> "initialized"
    | Scoping -> "scoping"
    | Reconnaissance -> "reconnaissance"
    | Planning -> "planning"
    | Researching -> "researching"
    | Evidence_review -> "evidence-review"
    | Drafting -> "drafting"
    | Draft_review -> "draft-review"
    | Finalizing -> "finalizing"
    | Completed -> "completed"
  ;;

  let of_string = function
    | "initialized" -> Some Initialized
    | "scoping" -> Some Scoping
    | "reconnaissance" -> Some Reconnaissance
    | "planning" -> Some Planning
    | "researching" -> Some Researching
    | "evidence-review" -> Some Evidence_review
    | "drafting" -> Some Drafting
    | "draft-review" -> Some Draft_review
    | "finalizing" -> Some Finalizing
    | "completed" -> Some Completed
    | _ -> None
  ;;

  let can_transition ~from ~into =
    match from, into with
    | Initialized, Scoping
    | Scoping, Reconnaissance
    | Scoping, Planning
    | Reconnaissance, Planning
    | Planning, Reconnaissance
    | Planning, Researching
    | Researching, Evidence_review
    | Evidence_review, Drafting
    | Drafting, Draft_review
    | Draft_review, Drafting
    | Draft_review, Finalizing
    | Finalizing, Completed -> true
    | _ -> false
  ;;
end

module Plan_step = struct
  module Key = struct
    type t = Slug.t

    module Error = struct
      type t =
        | Empty
        | Too_long
        | Invalid_format
      [@@deriving sexp_of]

      let message = function
        | Empty -> "Plan step key must not be empty."
        | Too_long -> "Plan step key must contain at most 63 characters."
        | Invalid_format ->
          "Plan step key must use lowercase letters or digits, separated by single hyphens."
      ;;
    end

    let of_string value =
      Slug.of_string value
      |> Result.map_error ~f:(function
        | Slug.Error.Empty -> Error.Empty
        | Too_long -> Too_long
        | Invalid_format -> Invalid_format)
    ;;

    let to_string = Slug.to_string
  end

  module Error = struct
    type t =
      | Empty_title
      | Title_too_long
    [@@deriving sexp_of]

    let message = function
      | Empty_title -> "Plan step title must not be empty."
      | Title_too_long -> "Plan step title must contain at most 200 bytes."
    ;;
  end

  type t =
    { key : Key.t
    ; title : string
    ; required : bool
    }

  let create ~key ~title ~required =
    let title = String.strip title in
    if String.is_empty title
    then Error Error.Empty_title
    else if String.length title > 200
    then Error Error.Title_too_long
    else Ok { key; title; required }
  ;;

  let key t = t.key
  let title t = t.title
  let required t = t.required
end

module Planning = struct
  module Error = struct
    type t = Wrong_phase of Phase.t [@@deriving sexp_of]
  end

  let transition_path = function
    | Phase.Initialized -> Ok [ Phase.Scoping; Planning ]
    | Scoping | Reconnaissance -> Ok [ Planning ]
    | Planning -> Ok []
    | phase -> Error (Error.Wrong_phase phase)
  ;;
end

module Plan_objective = struct
  type t = string

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  let maximum_bytes = 65_536

  let create text =
    if String.is_empty (String.strip text)
    then Error Empty
    else if String.length text > maximum_bytes
    then Error Too_large
    else Ok text
  ;;

  let text t = t
end

module Plan_extension_reason = struct
  type t = string

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  let maximum_bytes = 65_536

  let create text =
    if String.is_empty (String.strip text)
    then Error Empty
    else if String.length text > maximum_bytes
    then Error Too_large
    else Ok text
  ;;

  let text t = t
end

module Recon_document = struct
  type t = string

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  let maximum_bytes = 65_536

  let create text =
    if String.is_empty (String.strip text)
    then Error Empty
    else if String.length text > maximum_bytes
    then Error Too_large
    else Ok text
  ;;

  let text t = t
end

module Plan_projection = struct
  let version ~revision ~validated ~sealed =
    (revision * 3) + if sealed then 2 else if validated then 1 else 0
  ;;

  let render
        ?objective
        ?(dependencies = [])
        ?(extensions = [])
        ~phase
        ~revision
        ~validated
        ~sealed
        ~steps
        ()
    =
    let step_lines =
      match steps with
      | [] -> [ "No steps." ]
      | steps ->
        List.concat_map steps ~f:(fun (key, title, required, position) ->
          [ sprintf
              "%d. `%s` (%s)"
              position
              (Plan_step.Key.to_string key)
              (if required then "required" else "optional")
          ; sprintf "   Title: %S" title
          ])
    in
    let objective_lines =
      Option.value_map objective ~default:[] ~f:(fun objective ->
        [ "## Objective"; ""; String.strip objective; "" ])
    in
    let dependency_lines =
      if List.is_empty dependencies
      then []
      else
        [ "## Dependencies"; "" ]
        @ List.map dependencies ~f:(fun (step, dependency) ->
          sprintf "- `%s` depends on `%s`" step dependency)
        @ [ "" ]
    in
    let extension_lines =
      if List.is_empty extensions
      then []
      else
        [ "## Extensions"; "" ]
        @ List.concat_map extensions ~f:(fun (revision, key, reason) ->
          [ sprintf
              "- Revision %d added `%s`"
              revision
              (Plan_step.Key.to_string key)
          ; sprintf "  Reason: %S" (String.strip reason)
          ])
        @ [ "" ]
    in
    String.concat
      ~sep:"\n"
      ([ sprintf
           "<!-- sandwalk-projection-version: %d -->"
           (version ~revision ~validated ~sealed)
       ; sprintf "<!-- sandwalk-plan-revision: %d -->" revision
       ; "# Research plan"
       ; ""
       ; sprintf "Phase: %s" (Phase.to_string phase)
       ; sprintf "Validation: %s" (if validated then "current" else "pending")
       ; sprintf "Sealed: %s" (if sealed then "yes" else "no")
       ; ""
       ]
       @ objective_lines
       @ [ "## Steps"; "" ]
       @ step_lines
       @ [ "" ]
       @ dependency_lines
       @ extension_lines
       @ [ "" ])
  ;;
end

module Claim_id = struct
  type t = string

  let has_hex_suffix value =
    String.length value = 38
    && String.is_prefix value ~prefix:"claim_"
    && String.drop_prefix value 6
       |> String.for_all ~f:(function
         | '0' .. '9' | 'a' .. 'f' -> true
         | _ -> false)
  ;;

  let of_string value = if has_hex_suffix value then Some value else None
  let to_string t = t
end

module Hit_id = struct
  type t = string

  let of_string value =
    if
      String.length value = 36
      && String.is_prefix value ~prefix:"hit_"
      && String.drop_prefix value 4
         |> String.for_all ~f:(function
           | '0' .. '9' | 'a' .. 'f' -> true
           | _ -> false)
    then Some value
    else None
  ;;

  let to_string t = t
end

module Snapshot_id = struct
  type t = string

  let of_string value =
    if
      String.length value = 37
      && String.is_prefix value ~prefix:"snap_"
      && String.drop_prefix value 5
         |> String.for_all ~f:(function
           | '0' .. '9' | 'a' .. 'f' -> true
           | _ -> false)
    then Some value
    else None
  ;;

  let to_string t = t
end

module Excerpt_id = struct
  type t = string

  let of_string value =
    if
      String.length value = 40
      && String.is_prefix value ~prefix:"excerpt_"
      && String.drop_prefix value 8
         |> String.for_all ~f:(function
           | '0' .. '9' | 'a' .. 'f' -> true
           | _ -> false)
    then Some value
    else None
  ;;

  let to_string t = t
end

module Excerpt = struct
  type t =
    { text : string
    ; line_start : int
    ; line_end : int
    ; byte_start : int
    ; byte_end : int
    }

  type error =
    | Empty_document
    | Empty_excerpt
    | Invalid_line_range
    | Text_not_found
    | Ambiguous_text of int
    | Invalid_occurrence of int
    | Too_large of int
  [@@deriving sexp_of]

  let maximum_bytes = 65_536
  let text t = t.text
  let line_start t = t.line_start
  let line_end t = t.line_end
  let byte_start t = t.byte_start
  let byte_end t = t.byte_end

  let line_starts document =
    if String.is_empty document
    then [||]
    else (
      let starts = ref [ 0 ] in
      String.iteri document ~f:(fun index character ->
        if Char.equal character '\n' && index + 1 < String.length document
        then starts := (index + 1) :: !starts);
      Array.of_list_rev !starts)
  ;;

  let create document ~byte_start ~byte_end =
    let size = byte_end - byte_start in
    if size <= 0
    then Error Empty_excerpt
    else if size > maximum_bytes
    then Error (Too_large size)
    else (
      let line_at offset =
        1
        + String.foldi document ~init:0 ~f:(fun index count character ->
            if index < offset && Char.equal character '\n'
            then count + 1
            else count)
      in
      Ok
        { text = String.sub document ~pos:byte_start ~len:size
        ; line_start = line_at byte_start
        ; line_end = line_at (byte_end - 1)
        ; byte_start
        ; byte_end
        })
  ;;

  let by_lines document ~first ~last =
    let starts = line_starts document in
    let line_count = Array.length starts in
    if line_count = 0
    then Error Empty_document
    else if first < 1 || last < first || last > line_count
    then Error Invalid_line_range
    else (
      let byte_start = starts.(first - 1) in
      let byte_end =
        if last = line_count then String.length document else starts.(last)
      in
      create document ~byte_start ~byte_end)
  ;;

  let by_text document ~excerpt ~occurrence =
    if String.is_empty document
    then Error Empty_document
    else if String.is_empty excerpt
    then Error Empty_excerpt
    else if String.length excerpt > maximum_bytes
    then Error (Too_large (String.length excerpt))
    else (
      let rec find positions position =
        match String.substr_index document ~pattern:excerpt ~pos:position with
        | None -> List.rev positions
        | Some found -> find (found :: positions) (found + 1)
      in
      let positions = find [] 0 in
      match occurrence, positions with
      | _, [] -> Error Text_not_found
      | None, [ byte_start ] ->
        create
          document
          ~byte_start
          ~byte_end:(byte_start + String.length excerpt)
      | None, matches -> Error (Ambiguous_text (List.length matches))
      | Some selected, _ when selected < 1 ->
        Error (Invalid_occurrence selected)
      | Some selected, matches ->
        (match List.nth matches (selected - 1) with
         | None -> Error (Invalid_occurrence selected)
         | Some byte_start ->
           create
             document
             ~byte_start
             ~byte_end:(byte_start + String.length excerpt)))
  ;;
end

module Finding_key = struct
  type t = string

  let of_string value =
    match Plan_step.Key.of_string value with
    | Ok _ -> Some value
    | Error _ -> None
  ;;

  let to_string t = t
end

module Finding_relation = struct
  type t =
    | Supports
    | Contradicts
    | Qualifies
    | Context
  [@@deriving equal, sexp_of]

  let of_string = function
    | "supports" -> Some Supports
    | "contradicts" -> Some Contradicts
    | "qualifies" -> Some Qualifies
    | "context" -> Some Context
    | _ -> None
  ;;

  let to_string = function
    | Supports -> "supports"
    | Contradicts -> "contradicts"
    | Qualifies -> "qualifies"
    | Context -> "context"
  ;;
end

module Finding_claim = struct
  type t = string

  type error =
    | Empty
    | Too_large of int
  [@@deriving sexp_of]

  let maximum_bytes = 65_536

  let create text =
    let size = String.length text in
    if String.is_empty (String.strip text)
    then Error Empty
    else if size > maximum_bytes
    then Error (Too_large size)
    else Ok text
  ;;

  let text t = t
end

module Writer_pack = struct
  type item =
    { step : string
    ; finding : string
    ; verdict : string
    ; claim : string
    ; relation : string
    ; excerpt : string
    ; snapshot : string
    ; source_url : string
    ; line_start : int
    ; line_end : int
    ; text : string
    }

  let item
        ~step
        ~finding
        ~verdict
        ~claim
        ~relation
        ~excerpt
        ~snapshot
        ~source_url
        ~line_start
        ~line_end
        ~text
    =
    { step
    ; finding
    ; verdict
    ; claim
    ; relation
    ; excerpt
    ; snapshot
    ; source_url
    ; line_start
    ; line_end
    ; text
    }
  ;;

  let quote text =
    text
    |> String.split_lines
    |> List.map ~f:(fun line -> "> " ^ line)
    |> String.concat ~sep:"\n"
  ;;

  let render ~slug items =
    let header =
      [ "<!-- sandwalk-writer-pack-v1 -->"
      ; "# Writer Pack: " ^ slug
      ; ""
      ; "Use only current reviewed findings below. Cite a finding with its exact token:"
      ; ""
      ; "`[cite:step-key/finding-key]`"
      ; ""
      ]
    in
    let sections =
      List.concat_map items ~f:(fun item ->
        [ "## " ^ item.step ^ "/" ^ item.finding
        ; ""
        ; "- Verdict: " ^ item.verdict
        ; "- Citation: `[cite:" ^ item.step ^ "/" ^ item.finding ^ "]`"
        ; "- Claim: " ^ String.strip item.claim
        ; ""
        ; ( "### Evidence: "
            ^ item.excerpt
            ^ " ("
            ^ item.relation
            ^ ")" )
        ; ""
        ; "- Source: " ^ item.source_url
        ; "- Snapshot: " ^ item.snapshot
        ; sprintf "- Lines: %d:%d" item.line_start item.line_end
        ; ""
        ; quote item.text
        ; ""
        ])
    in
    String.concat_lines (header @ sections)
  ;;
end

module Report = struct
  type citation =
    { step : string
    ; finding : string
    }

  type block =
    { text : string
    ; citations : citation list
    }

  type t =
    { markdown : string
    ; blocks : block list
    }

  type error =
    | Empty
    | Too_large
    | Too_many_blocks of int
    | Block_too_large of int
    | No_citations
    | Missing_citation of int
    | Invalid_citation of string
  [@@deriving sexp_of]

  let maximum_bytes = 1_048_576
  let maximum_block_bytes = 16_384
  let maximum_blocks = 256
  let markdown t = t.markdown
  let blocks t = t.blocks
  let block_text t = t.text
  let block_citations t = t.citations
  let citation_step t = t.step
  let citation_finding t = t.finding

  let citation reference =
    match String.lsplit2 reference ~on:'/' with
    | Some (step, finding) ->
      (match
         Plan_step.Key.of_string step, Finding_key.of_string finding
       with
       | Ok _, Some _ -> Ok { step; finding }
       | _ -> Error (Invalid_citation reference))
    | None -> Error (Invalid_citation reference)
  ;;

  let citations text =
    let rec loop position found =
      match String.substr_index text ~pattern:"[cite" ~pos:position with
      | None -> Ok (List.rev found)
      | Some start ->
        if
          start + 6 > String.length text
          || not (String.equal (String.sub text ~pos:start ~len:6) "[cite:")
        then Error (Invalid_citation "[cite")
        else (
          match String.index_from text (start + 6) ']' with
          | None -> Error (Invalid_citation (String.drop_prefix text start))
          | Some finish ->
            let reference =
              String.sub text ~pos:(start + 6) ~len:(finish - start - 6)
            in
            (match citation reference with
             | Error _ as error -> error
             | Ok citation -> loop (finish + 1) (citation :: found)))
    in
    loop 0 []
  ;;

  let paragraphs markdown =
    let finish current blocks =
      if List.is_empty current
      then blocks
      else String.concat_lines (List.rev current) :: blocks
    in
    let blocks, current =
      markdown
      |> String.split_lines
      |> List.fold ~init:([], []) ~f:(fun (blocks, current) line ->
        if String.is_empty (String.strip line)
        then finish current blocks, []
        else blocks, line :: current)
    in
    finish current blocks |> List.rev
  ;;

  let create markdown =
    let size = String.length markdown in
    if String.is_empty (String.strip markdown)
    then Error Empty
    else if size > maximum_bytes
    then Error Too_large
    else (
      let paragraphs = paragraphs markdown in
      if List.length paragraphs > maximum_blocks
      then Error (Too_many_blocks (List.length paragraphs))
      else
        paragraphs
        |> List.mapi ~f:(fun index text ->
        if String.length text > maximum_block_bytes
        then Error (Block_too_large (index + 1))
        else
          let open Result.Let_syntax in
          let%bind citations = citations text in
          if
            List.is_empty citations
            && not (String.is_prefix (String.strip text) ~prefix:"#")
          then Error (Missing_citation (index + 1))
          else Ok { text; citations })
        |> Result.all
        |> Result.bind ~f:(fun blocks ->
          if
            List.for_all blocks ~f:(fun block ->
              List.is_empty block.citations)
          then Error No_citations
          else Ok { markdown; blocks }))
  ;;
end

module Final_report = struct
  type t =
    { report : string
    ; sources : string
    ; source_count : int
    }

  type error = Missing_source of string [@@deriving sexp_of]

  let report t = t.report
  let sources t = t.sources
  let source_count t = t.source_count

  let render ~markdown ~sources_by_finding =
    let mapping =
      Map.of_alist_reduce
        (module String)
        (List.map sources_by_finding ~f:(fun (reference, sources) ->
           ( reference
           , List.dedup_and_sort sources ~compare:String.compare )))
        ~f:(fun left right ->
          List.dedup_and_sort (left @ right) ~compare:String.compare)
    in
    let numbers = String.Table.create () in
    let ordered_sources = ref [] in
    let number source =
      Hashtbl.find_or_add numbers source ~default:(fun () ->
        let value = Hashtbl.length numbers + 1 in
        ordered_sources := source :: !ordered_sources;
        value)
    in
    let output = Buffer.create (String.length markdown) in
    let rec loop position =
      match String.substr_index markdown ~pattern:"[cite:" ~pos:position with
      | None ->
        Buffer.add_substring
          output
          markdown
          ~pos:position
          ~len:(String.length markdown - position);
        Ok ()
      | Some start ->
        Buffer.add_substring output markdown ~pos:position ~len:(start - position);
        (match String.index_from markdown (start + 6) ']' with
         | None -> Error (Missing_source (String.drop_prefix markdown start))
         | Some finish ->
           let reference =
             String.sub markdown ~pos:(start + 6) ~len:(finish - start - 6)
           in
           (match Map.find mapping reference with
            | None | Some [] -> Error (Missing_source reference)
            | Some sources ->
              sources
              |> List.map ~f:(fun source -> sprintf "[%d]" (number source))
              |> String.concat
              |> Buffer.add_string output;
              loop (finish + 1)))
    in
    let open Result.Let_syntax in
    let%map () = loop 0 in
    let sources = List.rev !ordered_sources in
    let bibliography =
      [ "<!-- sandwalk-sources-v1 -->"; "# Sources"; "" ]
      @ List.mapi sources ~f:(fun index source ->
        sprintf "%d. %s" (index + 1) source)
      |> String.concat_lines
    in
    { report = Buffer.contents output
    ; sources = bibliography
    ; source_count = List.length sources
    }
  ;;
end

module Step_state = struct
  type t =
    | Pending
    | Claimed
    | Suspended
    | Expired
    | Blocked
    | Completed
  [@@deriving equal, sexp]

  let to_string = function
    | Pending -> "pending"
    | Claimed -> "claimed"
    | Suspended -> "suspended"
    | Expired -> "expired"
    | Blocked -> "blocked"
    | Completed -> "completed"
  ;;

  let of_string = function
    | "pending" -> Some Pending
    | "claimed" -> Some Claimed
    | "suspended" -> Some Suspended
    | "expired" -> Some Expired
    | "blocked" -> Some Blocked
    | "completed" -> Some Completed
    | _ -> None
  ;;
end

module Claim_decision = struct
  module Error = struct
    type t =
      | Active_claim
      | Step_completed
    [@@deriving sexp_of]
  end

  type t =
    { previous_state : Step_state.t
    ; expired_active_claim : bool
    }
  [@@deriving sexp_of]

  let decide ~state ~lease_expired =
    match state with
    | Step_state.Pending | Suspended | Expired | Blocked ->
      Ok { previous_state = state; expired_active_claim = false }
    | Claimed when lease_expired ->
      Ok { previous_state = Expired; expired_active_claim = true }
    | Claimed -> Error Error.Active_claim
    | Completed -> Error Error.Step_completed
  ;;
end

module Checkpoint = struct
  module Error = struct
    type t =
      | Empty_summary
      | Empty_next
      | Summary_too_large
      | Next_too_large
    [@@deriving sexp_of]

    let message = function
      | Empty_summary -> "Checkpoint summary must not be empty."
      | Empty_next -> "Checkpoint next action must not be empty."
      | Summary_too_large -> "Checkpoint summary file exceeds 65536 bytes."
      | Next_too_large -> "Checkpoint next-action file exceeds 65536 bytes."
    ;;
  end

  type t =
    { summary : string
    ; next : string
    }

  let maximum_file_bytes = 65_536

  let create ~summary ~next =
    if String.is_empty (String.strip summary)
    then Error Error.Empty_summary
    else if String.is_empty (String.strip next)
    then Error Error.Empty_next
    else if String.length summary > maximum_file_bytes
    then Error Error.Summary_too_large
    else if String.length next > maximum_file_bytes
    then Error Error.Next_too_large
    else Ok { summary; next }
  ;;

  let summary t = t.summary
  let next t = t.next
end

let%expect_test "claim decisions enforce active leases and terminal steps" =
  let check state lease_expired =
    Claim_decision.decide ~state ~lease_expired
    |> [%sexp_of: (Claim_decision.t, Claim_decision.Error.t) Result.t]
    |> print_s
  in
  check Step_state.Pending false;
  check Claimed false;
  check Claimed true;
  check Completed true;
  [%expect
    {|
    (Ok ((previous_state Pending) (expired_active_claim false)))
    (Error Active_claim)
    (Ok ((previous_state Expired) (expired_active_claim true)))
    (Error Step_completed) |}]
;;

let%test_unit "claim references require a canonical 128-bit suffix" =
  let valid = "claim_0123456789abcdef0123456789abcdef" in
  assert (Option.is_some (Claim_id.of_string valid));
  [ "claim_0123"
  ; "claim_0123456789ABCDEF0123456789ABCDEF"
  ; "other_0123456789abcdef0123456789abcdef"
  ]
  |> List.iter ~f:(fun value ->
    assert (Option.is_none (Claim_id.of_string value)))
;;

module Transition_error = struct
  type t =
    { from : Phase.t
    ; into : Phase.t
    }
  [@@deriving sexp_of]

  let message { from; into } =
    sprintf
      "Cannot transition from %s to %s."
      (Phase.to_string from)
      (Phase.to_string into)
  ;;
end

let transition ~from ~into =
  if Phase.can_transition ~from ~into
  then Ok into
  else Error { Transition_error.from; into }
;;

module Resume_pack = struct
  module Error = struct
    type t = Too_large [@@deriving sexp_of]
  end

  let maximum_bytes = 32 * 1024

  let render
        ~slug
        ~phase
        ~schema_version
        ~plan_steps
        ~durable_entities
        ~active_claims
        ~latest_checkpoint
        ~recent_commands
        ~unmatched_commands
        ~events_path
        ~next_command
    =
    let recent_commands = List.take recent_commands 10 in
    let unmatched_commands = List.take unmatched_commands 10 in
    let bounded value =
      if String.length value <= 4_096
      then value
      else String.prefix value 4_096 ^ "\n[truncated]"
    in
    let step_scope_lines =
      match active_claims, latest_checkpoint with
      | (step_key, claim_id, _, _) :: _, _ ->
        let title =
          List.find_map plan_steps ~f:(fun (key, title, _, _) ->
            if
              String.equal
                (Plan_step.Key.to_string key)
                (Plan_step.Key.to_string step_key)
            then Some title
            else None)
          |> Option.value ~default:"Untitled step"
        in
        [ sprintf "- Step: %S" (Plan_step.Key.to_string step_key)
        ; sprintf "- Title: %S" title
        ; sprintf "- Active claim: %S" (Claim_id.to_string claim_id)
        ]
      | [], Some (step_key, _, _, _) ->
        [ sprintf
            "The latest checkpoint belongs to step %S; no claim is currently active."
            (Plan_step.Key.to_string step_key)
        ]
      | [], None ->
        if List.is_empty plan_steps
        then [ "No plan step is active." ]
        else
          [ sprintf
              "The plan contains %d step(s); no claim is currently active."
              (List.length plan_steps)
          ]
    in
    let durable_entity_lines =
      let plan_lines =
        match plan_steps with
        | [] -> [ "The workspace record is initialized. No plan steps exist yet." ]
        | steps ->
          "Plan steps:"
          :: List.map steps ~f:(fun (key, title, required, position) ->
            sprintf
              "- %d. %S: %S (%s)"
              position
              (Plan_step.Key.to_string key)
              title
              (if required then "required" else "optional"))
      in
      let entity_lines =
        match List.take durable_entities 40 with
        | [] -> [ "Created research entities: none." ]
        | entities ->
          "Created research entities:"
          :: List.map entities ~f:(fun (kind, reference, step, detail) ->
            let ownership =
              Option.value_map step ~default:"" ~f:(fun step ->
                sprintf ", step %S" step)
            in
            sprintf
              "- %s %S%s: %S"
              kind
              reference
              ownership
              (bounded detail))
      in
      plan_lines @ entity_lines
    in
    let active_claim_lines =
      match List.take active_claims 10 with
      | [] -> [ "- None." ]
      | claims ->
        List.map claims ~f:(fun (step_key, claim_id, attempt, expires_at) ->
          sprintf
            "- Step %S: %S, attempt %d, expires %S"
            (Plan_step.Key.to_string step_key)
            (Claim_id.to_string claim_id)
            attempt
            expires_at)
    in
    let latest_checkpoint_lines =
      match latest_checkpoint with
      | None -> [ "None." ]
      | Some (step_key, summary, next, created_at) ->
        [ sprintf "- Step: %S" (Plan_step.Key.to_string step_key)
        ; sprintf "- Created: %S" created_at
        ; sprintf "- Summary: %S" (bounded summary)
        ; sprintf "- Next: %S" (bounded next)
        ]
    in
    let command_lines =
      match recent_commands with
      | [] -> [ "- None." ]
      | commands ->
        List.map commands ~f:(fun (command, outcome, error_code) ->
          match error_code with
          | None -> sprintf "- %S: %s" command outcome
          | Some code -> sprintf "- %S: %s (%S)" command outcome code)
    in
    let unmatched_lines =
      match unmatched_commands with
      | [] -> [ "- None." ]
      | commands ->
        List.map commands ~f:(fun command -> sprintf "- %S" command)
    in
    let last_error =
      List.find_map (List.rev recent_commands) ~f:(fun (command, _, error_code) ->
        Option.map error_code ~f:(fun code -> sprintf "%S (%S)" command code))
      |> Option.value ~default:"None."
    in
    let unresolved =
      match phase with
      | Phase.Initialized -> "Workspace scope and plan are not yet defined."
      | Scoping | Reconnaissance -> "Reconnaissance has not been finished."
      | Planning -> "Plan validation and sealing are pending."
      | Researching -> "One or more plan steps remain incomplete."
      | Evidence_review -> "The drafting gate has not been run."
      | Drafting -> "A current cited report revision has not been submitted."
      | Draft_review -> "The current report blocks have not passed review."
      | Finalizing -> "Final citation rendering has not completed."
      | Completed -> "None."
    in
    let artifact_lines =
      durable_entities
      |> List.filter_map ~f:(fun (kind, reference, _, detail) ->
        if String.equal kind "snapshot" || String.equal kind "excerpt"
        then Some (sprintf "- %s %S: %S" kind reference detail)
        else None)
      |> fun paths -> List.take paths 20
    in
    let maximum_backtick_run =
      String.fold next_command ~init:(0, 0) ~f:(fun (maximum, current) character ->
        if Char.equal character '`'
        then maximum, current + 1
        else Int.max maximum current, 0)
      |> fun (maximum, current) -> Int.max maximum current
    in
    let command_fence = String.make (Int.max 3 (maximum_backtick_run + 1)) '`' in
    let content =
      String.concat
        ~sep:"\n"
        ([ "# Sandwalk resume pack"
         ; ""
         ; sprintf "- Workspace: %S" (Slug.to_string slug)
         ; sprintf "- Phase: %s" (Phase.to_string phase)
         ; sprintf "- Schema version: %d" schema_version
         ; ""
         ; "## Step objective and scope"
         ; ""
         ]
         @ step_scope_lines
         @ [ ""
           ; "## Latest checkpoint"
           ; ""
           ]
         @ latest_checkpoint_lines
         @ [ ""
           ; "## Durable entities"
         ; ""
         ]
         @ durable_entity_lines
         @ [ ""
           ; "## Active claims"
           ; ""
           ]
         @ active_claim_lines
         @ [ ""
           ; "## Recent commands"
         ; ""
         ]
         @ command_lines
         @ [ ""
           ; "## Unmatched command starts"
           ; ""
           ]
         @ unmatched_lines
         @ [ ""
           ; "## Last error or blocker"
           ; ""
           ; last_error
           ; ""
           ; "## Unresolved items"
           ; ""
           ; unresolved
           ; ""
           ; "## Relevant artifact paths"
           ; ""
           ; sprintf "- Event log: %S" events_path
           ]
         @ artifact_lines
         @ [ ""
           ; "## Recommended next command"
           ; ""
           ; command_fence ^ "console"
           ; next_command
           ; command_fence
           ; ""
           ])
    in
    if String.length content > maximum_bytes
    then Error Error.Too_large
    else Ok content
  ;;
end

let%expect_test "renders a bounded mechanical resume pack" =
  let slug =
    match Slug.of_string "typed-harness" with
    | Ok slug -> slug
    | Error _ -> assert false
  in
  let pack =
    match
      Resume_pack.render
        ~slug
        ~phase:Phase.Initialized
        ~schema_version:1
        ~plan_steps:[]
        ~durable_entities:[]
        ~active_claims:[]
        ~latest_checkpoint:None
        ~recent_commands:[ "init", "success", None ]
        ~unmatched_commands:[]
        ~events_path:"workspace/logs/events.jsonl"
        ~next_command:"sandwalk status --slug 'typed-harness'"
    with
    | Ok pack -> pack
    | Error _ -> assert false
  in
  print_endline pack;
  [%expect
    {|
    # Sandwalk resume pack

    - Workspace: "typed-harness"
    - Phase: initialized
    - Schema version: 1

    ## Step objective and scope

    No plan step is active.

    ## Latest checkpoint

    None.

    ## Durable entities

    The workspace record is initialized. No plan steps exist yet.
    Created research entities: none.

    ## Active claims

    - None.

    ## Recent commands

    - "init": success

    ## Unmatched command starts

    - None.

    ## Last error or blocker

    None.

    ## Unresolved items

    Workspace scope and plan are not yet defined.

    ## Relevant artifact paths

    - Event log: "workspace/logs/events.jsonl"

    ## Recommended next command

    ```console
    sandwalk status --slug 'typed-harness'
    ```
    |}]
;;

let%expect_test "slug validation protects canonical workspace paths" =
  [ ""; "a"; "typed-harness"; "-bad"; "bad-"; "bad--slug"; "Bad"; "../escape" ]
  |> List.iter ~f:(fun value ->
    match Slug.of_string value with
    | Ok slug -> printf "%S -> %s\n" value (Slug.to_string slug)
    | Error error -> printf "%S -> %s\n" value (Slug.Error.message error));
  [%expect
    {|
    "" -> Slug must not be empty.
    "a" -> a
    "typed-harness" -> typed-harness
    "-bad" -> Slug must use lowercase letters or digits, separated by single hyphens.
    "bad-" -> Slug must use lowercase letters or digits, separated by single hyphens.
    "bad--slug" -> Slug must use lowercase letters or digits, separated by single hyphens.
    "Bad" -> Slug must use lowercase letters or digits, separated by single hyphens.
    "../escape" -> Slug must use lowercase letters or digits, separated by single hyphens. |}]
;;

let%test_unit "accepted slugs contain no path separators" =
  Quickcheck.test String.quickcheck_generator ~f:(fun value ->
    match Slug.of_string value with
    | Error _ -> ()
    | Ok slug ->
      let value = Slug.to_string slug in
      [%test_pred: string]
        (fun value -> not (String.is_substring value ~substring:"/"))
        value;
      [%test_pred: string]
        (fun value -> not (String.is_substring value ~substring:"\\"))
        value;
      [%test_eq: string] value (Filename.basename value))
;;

let%expect_test "allows the planning and reconnaissance loop" =
  let check from into =
    transition ~from ~into
    |> Result.map ~f:Phase.to_string
    |> [%sexp_of: (string, Transition_error.t) Result.t]
    |> print_s
  in
  check Phase.Reconnaissance Phase.Planning;
  check Phase.Planning Phase.Reconnaissance;
  check Phase.Completed Phase.Planning;
  [%expect
    {|
    (Ok planning)
    (Ok reconnaissance)
    (Error ((from Completed) (into Planning))) |}]
;;

let%test_unit "phase persistence strings round-trip" =
  [ Phase.Initialized
  ; Scoping
  ; Reconnaissance
  ; Planning
  ; Researching
  ; Evidence_review
  ; Drafting
  ; Draft_review
  ; Finalizing
  ; Completed
  ]
  |> List.iter ~f:(fun phase ->
    [%test_eq: Phase.t option]
      (Some phase)
      (Phase.of_string (Phase.to_string phase)))
;;

let%expect_test "plan mutation follows only legal phase transitions" =
  [ Phase.Initialized; Scoping; Reconnaissance; Planning; Researching ]
  |> List.iter ~f:(fun phase ->
    match Planning.transition_path phase with
    | Error _ -> printf "%s -> rejected\n" (Phase.to_string phase)
    | Ok path ->
      printf
        "%s -> %s\n"
        (Phase.to_string phase)
        (path |> List.map ~f:Phase.to_string |> String.concat ~sep:","));
  [%expect
    {|
    initialized -> scoping,planning
    scoping -> planning
    reconnaissance -> planning
    planning ->
    researching -> rejected |}]
;;

let%test_unit "validated projections outrank pending projections at one revision" =
  Quickcheck.test Int.quickcheck_generator ~f:(fun revision ->
    if revision >= 0 && revision < Int.max_value / 2
    then (
      let pending =
        Plan_projection.version ~revision ~validated:false ~sealed:false
      in
      let validated =
        Plan_projection.version ~revision ~validated:true ~sealed:false
      in
      let sealed =
        Plan_projection.version ~revision ~validated:true ~sealed:true
      in
      [%test_pred: int] (fun value -> value < validated) pending;
      [%test_pred: int] (fun value -> value < sealed) validated;
      [%test_pred: int]
        (fun value ->
          value
          < Plan_projection.version
              ~revision:(revision + 1)
              ~validated:false
              ~sealed:false)
        sealed))
;;

let%test_unit "plan extension reasons are bounded and non-empty" =
  (match Plan_extension_reason.create "  " with
   | Error Empty -> ()
   | _ -> failwith "expected empty extension reason rejection");
  (match
     Plan_extension_reason.create
       (String.make (Plan_extension_reason.maximum_bytes + 1) 'x')
   with
   | Error Too_large -> ()
   | _ -> failwith "expected oversized extension reason rejection");
  (match Plan_extension_reason.create "New evidence gap." with
   | Ok reason ->
     [%test_eq: string] "New evidence gap." (Plan_extension_reason.text reason)
   | Error _ -> failwith "expected valid extension reason")
;;

let%test_unit "line excerpts preserve exact snapshot bytes" =
  let excerpt =
    match Excerpt.by_lines "one\ntwo\nthree" ~first:2 ~last:2 with
    | Ok excerpt -> excerpt
    | Error _ -> failwith "expected valid line excerpt"
  in
  [%test_eq: string] "two\n" (Excerpt.text excerpt);
  [%test_eq: int] 2 (Excerpt.line_start excerpt);
  [%test_eq: int] 2 (Excerpt.line_end excerpt);
  [%test_eq: int] 4 (Excerpt.byte_start excerpt);
  [%test_eq: int] 8 (Excerpt.byte_end excerpt)
;;

let%test_unit "text excerpts require an occurrence when matches are ambiguous" =
  (match Excerpt.by_text "same\nx\nsame" ~excerpt:"same" ~occurrence:None with
   | Error (Excerpt.Ambiguous_text 2) -> ()
   | _ -> failwith "expected two ambiguous matches");
  let excerpt =
    match
      Excerpt.by_text "same\nx\nsame" ~excerpt:"same" ~occurrence:(Some 2)
    with
    | Ok excerpt -> excerpt
    | Error _ -> failwith "expected selected text occurrence"
  in
  [%test_eq: string] "same" (Excerpt.text excerpt);
  [%test_eq: int] 7 (Excerpt.byte_start excerpt);
  [%test_eq: int] 11 (Excerpt.byte_end excerpt)
;;

let%test_unit "exact text ranges round-trip snapshot bytes" =
  Quickcheck.test
    [%quickcheck.generator: string * string]
    ~trials:500
    ~f:(fun (prefix, suffix) ->
      let remove_marker =
        String.map ~f:(fun character ->
          if Char.equal character '\000' then '\001' else character)
      in
      let prefix = remove_marker prefix in
      let suffix = remove_marker suffix in
      let document = prefix ^ "\000" ^ suffix in
      match Excerpt.by_text document ~excerpt:"\000" ~occurrence:None with
      | Error _ -> failwith "unique marker must be selectable"
      | Ok excerpt ->
        [%test_eq: string] "\000" (Excerpt.text excerpt);
        [%test_eq: int] (String.length prefix) (Excerpt.byte_start excerpt);
        [%test_eq: int] (String.length prefix + 1) (Excerpt.byte_end excerpt))
;;

let%test_unit "report blocks require canonical typed citations" =
  let report =
    Report.create
      "# Heading\n\nSupported statement. [cite:fixture-step/small-claim]\n"
  in
  (match report with
   | Error _ -> failwith "expected a valid cited report"
   | Ok report ->
     [%test_eq: int] 2 (List.length (Report.blocks report));
     let citation =
       Report.blocks report
       |> List.last_exn
       |> Report.block_citations
       |> List.hd_exn
     in
     [%test_eq: string] "fixture-step" (Report.citation_step citation);
     [%test_eq: string] "small-claim" (Report.citation_finding citation));
  (match Report.create "Uncited statement." with
   | Error (Report.Missing_citation 1) -> ()
   | _ -> failwith "expected uncited prose rejection");
  (match Report.create "Bad. [cite:../escape]" with
   | Error (Report.Invalid_citation _) -> ()
   | _ -> failwith "expected invalid citation rejection")
;;

let%test_unit "final citation numbering is stable and deduplicates sources" =
  let markdown =
    "First [cite:step-one/finding-one]. Second [cite:step-two/finding-two]."
  in
  let first =
    Final_report.render
      ~markdown
      ~sources_by_finding:
        [ "step-one/finding-one", [ "https://b.test"; "https://a.test" ]
        ; "step-two/finding-two", [ "https://b.test" ]
        ]
  in
  let second =
    Final_report.render
      ~markdown
      ~sources_by_finding:
        [ "step-two/finding-two", [ "https://b.test" ]
        ; "step-one/finding-one", [ "https://a.test"; "https://b.test" ]
        ]
  in
  match first, second with
  | Ok first, Ok second ->
    [%test_eq: string]
      "First [1][2]. Second [2]."
      (Final_report.report first);
    [%test_eq: string]
      (Final_report.report first)
      (Final_report.report second);
    [%test_eq: string]
      (Final_report.sources first)
      (Final_report.sources second);
    [%test_eq: int] 2 (Final_report.source_count first)
  | _ -> failwith "expected stable final citation rendering"
;;
