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

module Plan_projection = struct
  let version ~revision ~validated = (revision * 2) + if validated then 1 else 0

  let render ~phase ~revision ~validated ~steps =
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
    String.concat
      ~sep:"\n"
      ([ sprintf
           "<!-- sandwalk-projection-version: %d -->"
           (version ~revision ~validated)
       ; sprintf "<!-- sandwalk-plan-revision: %d -->" revision
       ; "# Research plan"
       ; ""
       ; sprintf "Phase: %s" (Phase.to_string phase)
       ; sprintf "Validation: %s" (if validated then "current" else "pending")
       ; ""
       ]
       @ step_lines
       @ [ "" ])
  ;;
end

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
        ~recent_commands
        ~unmatched_commands
        ~events_path
        ~next_command
    =
    let recent_commands = List.take recent_commands 10 in
    let unmatched_commands = List.take unmatched_commands 10 in
    let durable_entity_lines =
      match plan_steps with
      | [] -> [ "The workspace record is initialized. No plan entities exist yet." ]
      | steps ->
        "The workspace record and these plan steps are durable:"
        :: List.map steps ~f:(fun (key, title, required, position) ->
          sprintf
            "- %d. %S: %S (%s)"
            position
            (Plan_step.Key.to_string key)
            title
            (if required then "required" else "optional"))
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
      | Planning -> "Plan validation and sealing are pending."
      | _ -> "Consult the current durable workspace state."
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
         ; "No plan step is active."
         ; ""
         ; "## Latest checkpoint"
         ; ""
         ; "None."
         ; ""
         ; "## Durable entities"
         ; ""
         ]
         @ durable_entity_lines
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
           ; ""
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

    The workspace record is initialized. No plan entities exist yet.

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
      let pending = Plan_projection.version ~revision ~validated:false in
      let validated = Plan_projection.version ~revision ~validated:true in
      [%test_pred: int] (fun value -> value < validated) pending;
      [%test_pred: int]
        (fun value ->
          value < Plan_projection.version ~revision:(revision + 1) ~validated:false)
        validated))
;;
