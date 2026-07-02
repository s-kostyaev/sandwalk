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
    | Plan_step_not_found of string
    | Step_claim_wrong_phase of Sandwalk_core.Phase.t
    | Step_already_claimed of int64
    | Step_completed of string
    | Claim_id_collision
    | Invalid_step_state of string
    | Claim_not_found
    | Claim_not_active
    | Claim_expired of string
    | Search_wrong_phase of Sandwalk_core.Phase.t
    | Search_requires_claim
    | Hit_id_collision
    | Hit_not_found of string
    | Hit_not_owned_by_claim of string
    | Fetch_wrong_phase of Sandwalk_core.Phase.t
    | Fetch_requires_claim
    | Snapshot_id_collision
    | Database_error of string
  [@@deriving sexp_of]
end

module Hit_for_fetch : sig
  type t

  val hit_id : t -> Sandwalk_core.Hit_id.t
  val url : t -> string
end

module Record_snapshot_result : sig
  type t

  val previous_schema_version : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
  val lease_expires_unix_seconds : t -> int64 option
end

module Stored_hit : sig
  type t

  val hit_id : t -> Sandwalk_core.Hit_id.t
  val position : t -> int
  val url : t -> string
  val title : t -> string
  val snippet : t -> string
end

module Record_search_result : sig
  type t

  val previous_schema_version : t -> int
  val hits : t -> Stored_hit.t list
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
  val lease_expires_unix_seconds : t -> int64 option
end

module Save_checkpoint_result : sig
  type t

  val previous_schema_version : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val checkpoint_number : t -> int
  val lease_expires_unix_seconds : t -> int64
end

module Latest_checkpoint : sig
  type t

  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val summary : t -> string
  val next : t -> string
  val created_at : t -> string
end

module Claim_step_result : sig
  type t

  val previous_schema_version : t -> int
  val claim_id : t -> Sandwalk_core.Claim_id.t
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val attempt : t -> int
  val previous_state : t -> Sandwalk_core.Step_state.t
  val expired_active_claim : t -> bool
end

module Active_claim : sig
  type t

  val claim_id : t -> Sandwalk_core.Claim_id.t
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val attempt : t -> int
  val lease_expires_at : t -> string
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

val claim_step
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> now:string
  -> now_unix_seconds:int64
  -> lease_expires_at:string
  -> lease_expires_unix_seconds:int64
  -> lease_duration_seconds:int
  -> unit
  -> (Claim_step_result.t, Error.t) Result.t

val read_active_claims
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Active_claim.t list, Error.t) Result.t

val save_checkpoint
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> checkpoint:Sandwalk_core.Checkpoint.t
  -> summary_path:string
  -> summary_md5:string
  -> summary_size:int
  -> next_path:string
  -> next_md5:string
  -> next_size:int
  -> now:string
  -> now_unix_seconds:int64
  -> unit
  -> (Save_checkpoint_result.t, Error.t) Result.t

val read_latest_checkpoint
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Latest_checkpoint.t option, Error.t) Result.t

val record_search
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t option
  -> query:string
  -> adapter:string
  -> hits:(Sandwalk_core.Hit_id.t * string * string * string) list
  -> now:string
  -> now_unix_seconds:int64
  -> unit
  -> (Record_search_result.t, Error.t) Result.t

val hit_for_fetch
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> hit_id:Sandwalk_core.Hit_id.t
  -> unit
  -> (Hit_for_fetch.t, Error.t) Result.t

val record_snapshot
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t option
  -> hit_id:Sandwalk_core.Hit_id.t
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> artifact_path:string
  -> final_url:string
  -> input_sha256:string
  -> markdown_sha256:string
  -> manifest_json:string
  -> now:string
  -> now_unix_seconds:int64
  -> unit
  -> (Record_snapshot_result.t, Error.t) Result.t
