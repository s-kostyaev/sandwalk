open! Core

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
