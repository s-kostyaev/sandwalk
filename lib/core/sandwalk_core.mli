open! Core

module Slug : sig
  type t

  module Error : sig
    type t =
      | Empty
      | Too_long
      | Invalid_format
    [@@deriving equal, sexp_of]

    val message : t -> string
  end

  val of_string : string -> (t, Error.t) Result.t
  val to_string : t -> string
end

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
  val of_string : string -> t option
  val can_transition : from:t -> into:t -> bool
end

module Plan_step : sig
  module Key : sig
    type t

    module Error : sig
      type t =
        | Empty
        | Too_long
        | Invalid_format
      [@@deriving sexp_of]

      val message : t -> string
    end

    val of_string : string -> (t, Error.t) Result.t
    val to_string : t -> string
  end

  module Error : sig
    type t =
      | Empty_title
      | Title_too_long
    [@@deriving sexp_of]

    val message : t -> string
  end

  type t

  val create
    :  key:Key.t
    -> title:string
    -> required:bool
    -> (t, Error.t) Result.t

  val key : t -> Key.t
  val title : t -> string
  val required : t -> bool
end

module Planning : sig
  module Error : sig
    type t = Wrong_phase of Phase.t [@@deriving sexp_of]
  end

  val transition_path : Phase.t -> (Phase.t list, Error.t) Result.t
end

module Plan_projection : sig
  val version : revision:int -> validated:bool -> sealed:bool -> int

  val render
    :  phase:Phase.t
    -> revision:int
    -> validated:bool
    -> sealed:bool
    -> steps:(Plan_step.Key.t * string * bool * int) list
    -> string
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

module Resume_pack : sig
  module Error : sig
    type t = Too_large [@@deriving sexp_of]
  end

  val render
    :  slug:Slug.t
    -> phase:Phase.t
    -> schema_version:int
    -> plan_steps:(Plan_step.Key.t * string * bool * int) list
    -> recent_commands:(string * string * string option) list
    -> unmatched_commands:string list
    -> events_path:string
    -> next_command:string
    -> (string, Error.t) Result.t
end
