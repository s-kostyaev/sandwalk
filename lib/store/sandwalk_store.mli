open! Core

module Error : sig
  type t =
    | Already_initialized
    | Not_initialized
    | Unsupported_schema_version of int
    | Invalid_persisted_phase of string
    | Workspace_slug_mismatch of
        { expected : string
        ; actual : string
        }
    | Database_error of string
  [@@deriving sexp_of]
end

module Workspace_status : sig
  type t

  val slug : t -> Sandwalk_core.Slug.t
  val phase : t -> Sandwalk_core.Phase.t
  val schema_version : t -> int
end

val current_schema_version : int

val initialize
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (unit, Error.t) Result.t

val read_status
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Workspace_status.t, Error.t) Result.t
