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
