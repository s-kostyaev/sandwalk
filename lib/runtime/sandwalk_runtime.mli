open! Core
open! Async

module Workspace : sig
  type t

  val resolve
    :  directory_prefix:string
    -> slug:Sandwalk_core.Slug.t
    -> t

  val create_layout
    :  directory_prefix:string
    -> slug:Sandwalk_core.Slug.t
    -> t Deferred.Or_error.t

  val root : t -> string
  val database_path : t -> string
  val events_path : t -> string
  val resume_path : t -> string
  val research_plan_path : t -> string
  val research_plan_lock_path : t -> string
end

module Audit : sig
  type summary
  type history

  val append : path:string -> Yojson.Safe.t -> unit Deferred.Or_error.t

  val read_history
    :  path:string
    -> exclude_invocation_id:string
    -> history Deferred.Or_error.t

  val recent_commands : history -> summary list
  val unmatched_commands : history -> string list
  val summary_command : summary -> string
  val summary_outcome : summary -> string
  val summary_error_code : summary -> string option
end

module Atomic_file : sig
  val write
    :  path:string
    -> temporary_suffix:string
    -> string
    -> unit Deferred.Or_error.t

  val write_versioned
    :  path:string
    -> lock_path:string
    -> temporary_suffix:string
    -> version:int
    -> string
    -> unit Deferred.Or_error.t
end

module File_input : sig
  type t

  val read : path:string -> maximum_bytes:int -> t Deferred.Or_error.t
  val path : t -> string
  val content : t -> string
  val size : t -> int
  val md5 : t -> string
end

val default_directory_prefix : unit -> string
val resolve_directory_prefix : command_line:string option -> string
val timestamp_utc : Time_float.t -> string
val invocation_id : now:Time_float.t -> string
val claim_id : unit -> Sandwalk_core.Claim_id.t
