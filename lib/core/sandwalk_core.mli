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

module Plan_objective : sig
  type t

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  val maximum_bytes : int
  val create : string -> (t, error) Result.t
  val text : t -> string
end

module Plan_extension_reason : sig
  type t

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  val maximum_bytes : int
  val create : string -> (t, error) Result.t
  val text : t -> string
end

module Recon_document : sig
  type t

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  val maximum_bytes : int
  val create : string -> (t, error) Result.t
  val text : t -> string
end

module Plan_projection : sig
  val version : revision:int -> validated:bool -> sealed:bool -> int

  val render
    :  ?objective:string
    -> ?dependencies:(string * string) list
    -> ?extensions:(int * Plan_step.Key.t * string) list
    -> phase:Phase.t
    -> revision:int
    -> validated:bool
    -> sealed:bool
    -> steps:(Plan_step.Key.t * string * bool * int) list
    -> unit
    -> string
end

module Claim_id : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
end

module Hit_id : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
end

module Snapshot_id : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
end

module Excerpt_id : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
end

module Visual_id : sig
  type t

  val maximum_per_finding : int
  val of_string : string -> t option
  val to_string : t -> string
end

module Visual_description : sig
  type t

  type error =
    | Empty
    | Too_large
  [@@deriving sexp_of]

  val maximum_bytes : int
  val create : string -> (t, error) Result.t
  val text : t -> string
end

module Excerpt : sig
  type t

  type error =
    | Empty_document
    | Empty_excerpt
    | Invalid_line_range
    | Text_not_found
    | Ambiguous_text of int
    | Invalid_occurrence of int
    | Too_large of int
  [@@deriving sexp_of]

  val maximum_bytes : int
  val by_lines : string -> first:int -> last:int -> (t, error) Result.t

  val by_text
    :  string
    -> excerpt:string
    -> occurrence:int option
    -> (t, error) Result.t

  val text : t -> string
  val line_start : t -> int
  val line_end : t -> int
  val byte_start : t -> int
  val byte_end : t -> int
end

module Finding_key : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
end

module Finding_relation : sig
  type t =
    | Supports
    | Contradicts
    | Qualifies
    | Context
  [@@deriving equal, sexp_of]

  val of_string : string -> t option
  val to_string : t -> string
end

module Finding_claim : sig
  type t

  type error =
    | Empty
    | Too_large of int
  [@@deriving sexp_of]

  val maximum_bytes : int
  val create : string -> (t, error) Result.t
  val text : t -> string
end

module Writer_pack : sig
  type item

  val item
    :  step:string
    -> finding:string
    -> verdict:string
    -> claim:string
    -> relation:string
    -> excerpt:string
    -> snapshot:string
    -> source_url:string
    -> line_start:int
    -> line_end:int
    -> text:string
    -> item

  val visual_item
    :  step:string
    -> finding:string
    -> verdict:string
    -> claim:string
    -> relation:string
    -> visual:string
    -> snapshot:string
    -> source_url:string
    -> source_format:string
    -> page:int
    -> image_path:string
    -> description:string
    -> item

  val render : slug:string -> item list -> string
end

module Report : sig
  type t
  type block
  type citation

  type error =
    | Empty
    | Too_large
    | Too_many_blocks of int
    | Block_too_large of int
    | No_citations
    | Missing_citation of int * string
    | Invalid_citation of string
  [@@deriving sexp_of]

  val maximum_bytes : int
  val maximum_block_bytes : int
  val maximum_blocks : int
  val create : string -> (t, error) Result.t
  val markdown : t -> string
  val blocks : t -> block list
  val block_text : block -> string
  val block_citations : block -> citation list
  val citation_step : citation -> string
  val citation_finding : citation -> string
end

module Final_report : sig
  type t
  type error = Missing_source of string [@@deriving sexp_of]

  val render
    :  markdown:string
    -> sources_by_finding:(string * string list) list
    -> (t, error) Result.t

  val report : t -> string
  val sources : t -> string
  val source_count : t -> int
end

module Step_state : sig
  type t =
    | Pending
    | Claimed
    | Suspended
    | Blocked
    | Completed
  [@@deriving equal, sexp]

  val to_string : t -> string
  val of_string : string -> t option
end

module Candidate_kind : sig
  type t =
    | Hit
    | Snapshot
    | Excerpt
  [@@deriving equal, sexp]

  val to_string : t -> string
  val of_string : string -> t option
end

module Claim_decision : sig
  module Error : sig
    type t =
      | Active_claim
      | Step_completed
    [@@deriving sexp_of]
  end

  type t =
    { previous_state : Step_state.t }
  [@@deriving sexp_of]

  val decide
    :  state:Step_state.t
    -> (t, Error.t) Result.t
end

module Checkpoint : sig
  module Error : sig
    type t =
      | Empty_summary
      | Empty_next
      | Summary_too_large
      | Next_too_large
    [@@deriving sexp_of]

    val message : t -> string
  end

  type t

  val maximum_file_bytes : int
  val create : summary:string -> next:string -> (t, Error.t) Result.t
  val summary : t -> string
  val next : t -> string
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
    -> durable_entities:(string * string * string option * string) list
    -> active_claims:(Plan_step.Key.t * Claim_id.t * int) list
    -> latest_checkpoint:(Plan_step.Key.t * string * string * string) option
    -> recent_commands:(string * string * string option) list
    -> unmatched_commands:string list
    -> events_path:string
    -> next_action:string
    -> next_command:string
    -> (string, Error.t) Result.t
end
