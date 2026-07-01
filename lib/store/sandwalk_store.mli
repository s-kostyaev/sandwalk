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
    | Duplicate_plan_step of string
    | Plan_mutation_wrong_phase of Sandwalk_core.Phase.t
    | Empty_plan
    | Plan_validation_wrong_phase of Sandwalk_core.Phase.t
    | Plan_not_validated
    | Plan_validation_stale of
        { validated_revision : int
        ; current_revision : int
        }
    | Plan_seal_wrong_phase of Sandwalk_core.Phase.t
    | Database_error of string
  [@@deriving sexp_of]
end

module Stored_plan_step : sig
  type t

  val key : t -> Sandwalk_core.Plan_step.Key.t
  val title : t -> string
  val required : t -> bool
  val position : t -> int
end

module Seal_plan_result : sig
  type t

  val previous_schema_version : t -> int
  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val already_sealed : t -> bool
  val steps : t -> Stored_plan_step.t list
end

module Validate_plan_result : sig
  type t

  val previous_schema_version : t -> int
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val already_validated : t -> bool
  val steps : t -> Stored_plan_step.t list
end

module Add_plan_step_result : sig
  type t

  val previous_schema_version : t -> int
  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase_path : t -> Sandwalk_core.Phase.t list
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val steps : t -> Stored_plan_step.t list
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

val add_plan_step
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> step:Sandwalk_core.Plan_step.t
  -> now:string
  -> unit
  -> (Add_plan_step_result.t, Error.t) Result.t

val read_plan_steps
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Stored_plan_step.t list, Error.t) Result.t

val validate_plan
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (Validate_plan_result.t, Error.t) Result.t

val seal_plan
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (Seal_plan_result.t, Error.t) Result.t
