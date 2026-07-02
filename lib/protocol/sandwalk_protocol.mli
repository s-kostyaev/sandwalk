open! Core

module Error : sig
  type t =
    { code : string
    ; message : string
    }
end

module Envelope : sig
  type t

  val success : ?next:string -> result:Yojson.Safe.t -> unit -> t
  val failure : ?next:string -> code:string -> message:string -> unit -> t
  val to_yojson : t -> Yojson.Safe.t
  val render : t -> string
end

module Audit_event : sig
  type kind =
    [ `Started
    | `Finished
    | `Failed
    ]

  type metadata

  val metadata_of_yojson : Yojson.Safe.t -> metadata option
  val metadata_kind : metadata -> kind
  val metadata_invocation_id : metadata -> string
  val metadata_command : metadata -> string
  val metadata_outcome : metadata -> string option
  val metadata_error_code : metadata -> string option

  val create
    :  invocation_id:string
    -> timestamp:string
    -> kind:kind
    -> command:string
    -> phase:string option
    -> raw_argv:string list
    -> arguments:Yojson.Safe.t
    -> state_changes:Yojson.Safe.t list
    -> ?claim:string
    -> ?step:string
    -> ?consumed_references:string list
    -> ?created_references:string list
    -> ?duration_ms:int
    -> ?outcome:string
    -> ?error_code:string
    -> unit
    -> Yojson.Safe.t
end

module Shell_command : sig
  val quote : string -> string
  val of_words : string list -> string
end

module Search_adapter : sig
  type result

  type error =
    | Invalid_envelope
    | Unsupported_protocol
    | Too_many_results
    | Invalid_result
  [@@deriving sexp_of]

  val request : query:string -> limit:int -> Yojson.Safe.t
  val results : Yojson.Safe.t -> (result list, error) Result.t
  val url : result -> string
  val title : result -> string
  val snippet : result -> string
end

module Fetch_adapter : sig
  type manifest

  type error =
    | Invalid_manifest
    | Unsupported_protocol
    | Queryability_check_failed
  [@@deriving sexp_of]

  val request : url:string -> output_directory:string -> Yojson.Safe.t
  val manifest : Yojson.Safe.t -> (manifest, error) Result.t
  val validate_manifest : Yojson.Safe.t -> (unit, error) Result.t
  val final_url : manifest -> string
  val input_sha256 : manifest -> string
  val markdown_sha256 : manifest -> string
end

module Finding_review : sig
  type verdict =
    | Supported
    | Partially_supported
    | Unsupported
    | Contradicted

  type t

  type error =
    | Invalid_review
    | Unsupported_protocol
  [@@deriving sexp_of]

  val decode : Yojson.Safe.t -> (t, error) Result.t
  val verdict : t -> verdict
  val verdict_to_string : verdict -> string
  val summary : t -> string
  val source_quality : t -> string
  val conflicts : t -> string
  val qualifications : t -> string
end

module Report_review : sig
  type t
  type block

  type error =
    | Invalid_review
    | Unsupported_protocol
    | Too_many_blocks
    | Duplicate_ordinal
  [@@deriving sexp_of]

  val decode : Yojson.Safe.t -> (t, error) Result.t
  val report_revision : t -> int
  val blocks : t -> block list
  val ordinal : block -> int
  val block_md5 : block -> string
  val verdict : block -> Finding_review.verdict
  val summary : block -> string
end
