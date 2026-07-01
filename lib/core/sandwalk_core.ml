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
