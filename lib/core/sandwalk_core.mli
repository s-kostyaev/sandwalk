open! Core

module Phase : sig
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

  val to_string : t -> string
  val can_transition : from:t -> into:t -> bool
end

module Transition_error : sig
  type t =
    { from : Phase.t
    ; into : Phase.t
    }
  [@@deriving sexp_of]

  val message : t -> string
end

val transition
  :  from:Phase.t
  -> into:Phase.t
  -> (Phase.t, Transition_error.t) Result.t
