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
  val create
    :  invocation_id:string
    -> timestamp:string
    -> kind:[ `Started | `Finished | `Failed ]
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
