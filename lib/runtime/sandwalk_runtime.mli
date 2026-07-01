open! Core
open! Async

module Workspace : sig
  type t

  val create_layout
    :  directory_prefix:string
    -> slug:Sandwalk_core.Slug.t
    -> t Deferred.Or_error.t

  val root : t -> string
  val database_path : t -> string
  val events_path : t -> string
end

module Audit : sig
  val append : path:string -> Yojson.Safe.t -> unit Deferred.Or_error.t
end

val default_directory_prefix : unit -> string
val resolve_directory_prefix : command_line:string option -> string
val timestamp_utc : Time_float.t -> string
val invocation_id : now:Time_float.t -> string
