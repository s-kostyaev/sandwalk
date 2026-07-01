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
