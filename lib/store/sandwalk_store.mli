open! Core

module Error : sig
  type t =
    | Already_initialized
    | Database_error of string
  [@@deriving sexp_of]
end

val current_schema_version : int

val initialize
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (unit, Error.t) Result.t
