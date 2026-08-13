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
    | Step_already_claimed
    | Step_completed of string
    | Step_dependencies_incomplete of string
    | Claim_id_collision
    | Invalid_step_state of string
    | Claim_not_found
    | Claim_not_active
    | Candidate_not_found of string
    | Candidate_not_owned_by_claim of string
    | Search_wrong_phase of Sandwalk_core.Phase.t
    | Search_requires_claim
    | Hit_id_collision
    | Hit_not_found of string
    | Hit_not_owned_by_claim of string
    | Fetch_wrong_phase of Sandwalk_core.Phase.t
    | Fetch_requires_claim
    | Snapshot_id_collision
    | Snapshot_not_found of string
    | Snapshot_not_owned_by_claim of string
    | Snapshot_promotion_wrong_phase of Sandwalk_core.Phase.t
    | Snapshot_promotion_conflict of string
    | Excerpt_wrong_phase of Sandwalk_core.Phase.t
    | Excerpt_requires_claim
    | Excerpt_id_collision
    | Visual_wrong_phase of Sandwalk_core.Phase.t
    | Visual_id_collision
    | Visual_not_found of string
    | Finding_wrong_phase of Sandwalk_core.Phase.t
    | Finding_step_mismatch
    | Finding_exists of string
    | Finding_not_found of string
    | Excerpt_not_found of string
    | Finding_excerpt_step_mismatch
    | Finding_visual_step_mismatch
    | Finding_visual_limit_exceeded of string
    | Finding_visual_review_incomplete of string
    | Excerpt_stale of string
    | Finding_has_no_evidence of string
    | Finding_not_sealed of string
    | Finding_review_conflict of string
    | Step_has_no_findings of string
    | Step_has_unreviewed_findings of string
    | Step_has_rejected_findings of string
    | Finding_repair_wrong_phase of Sandwalk_core.Phase.t
    | Finding_repair_requires_completed_step of string
    | Finding_repair_has_completed_dependents of string
    | Draft_wrong_phase of Sandwalk_core.Phase.t
    | Draft_gate_failed
    | Report_wrong_phase of Sandwalk_core.Phase.t
    | Report_citation_invalid of string
    | Report_conflict
    | Report_review_wrong_phase of Sandwalk_core.Phase.t
    | Report_revision_stale
    | Report_review_incomplete
    | Report_block_stale of int
    | Finalize_wrong_phase of Sandwalk_core.Phase.t
    | Finalize_gate_failed
    | Export_wrong_phase of Sandwalk_core.Phase.t
    | Export_not_finalized
    | Plan_objective_wrong_phase of Sandwalk_core.Phase.t
    | Plan_dependency_wrong_phase of Sandwalk_core.Phase.t
    | Plan_dependency_self
    | Plan_dependency_exists
    | Plan_dependency_cycle
    | Plan_extension_wrong_phase of Sandwalk_core.Phase.t
    | Recon_start_wrong_phase of Sandwalk_core.Phase.t
    | Recon_not_active of Sandwalk_core.Phase.t
    | Gc_active_claims
    | Gc_no_plan
    | Gc_plan_stale
    | Database_error of string
  [@@deriving sexp_of]
end

module Hit_for_fetch : sig
  type t

  val hit_id : t -> Sandwalk_core.Hit_id.t
  val url : t -> string
  val source_root : t -> string option
end

module Record_snapshot_result : sig
  type t

  val previous_schema_version : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
end

module Snapshot_for_excerpt : sig
  type t

  val snapshot_id : t -> Sandwalk_core.Snapshot_id.t
  val artifact_path : t -> string
  val document_artifact : t -> string
  val document_media_type : t -> string
  val document_sha256 : t -> string
  val markdown_sha256 : t -> string
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
end

module Snapshot_for_visual : sig
  type t

  val snapshot_id : t -> Sandwalk_core.Snapshot_id.t
  val artifact_path : t -> string
  val manifest_json : t -> string
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
end

module Promote_snapshot_result : sig
  type t

  val previous_schema_version : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val promoted : t -> bool
end

module Record_excerpt_result : sig
  type t

  val excerpt_id : t -> Sandwalk_core.Excerpt_id.t
  val created : t -> bool
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
end

module Record_visual_result : sig
  type t

  val visual_id : t -> Sandwalk_core.Visual_id.t
  val created : t -> bool
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
end

module Visual_evidence : sig
  type t

  val visual_id : t -> Sandwalk_core.Visual_id.t
  val snapshot_id : t -> Sandwalk_core.Snapshot_id.t
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val image_path : t -> string
  val manifest_path : t -> string
  val source_pdf_artifact : t -> string
  val source_pdf_sha256 : t -> string
  val page : t -> int
  val page_count : t -> int
  val image_sha256 : t -> string
  val image_md5 : t -> string
  val manifest_md5 : t -> string
  val image_size : t -> int
  val width : t -> int
  val height : t -> int
  val render_profile : t -> string
  val renderer_version : t -> string
  val description : t -> string
  val description_md5 : t -> string
end

module Create_finding_result : sig
  type t

  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val finding_key : t -> Sandwalk_core.Finding_key.t
  val revision : t -> int
end

module Attach_evidence_result : sig
  type t

  val revision : t -> int
  val attached : t -> bool
  val revised : t -> bool
end

module Seal_finding_result : sig
  type t

  val revision : t -> int
  val already_sealed : t -> bool
  val state : t -> string
end

module Review_finding_result : sig
  type t

  val revision : t -> int
  val reviewed : t -> bool
end

module Complete_step_result : sig
  type t

  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val phase : t -> Sandwalk_core.Phase.t
end

module Candidate_rejection_result : sig
  type t

  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val kind : t -> Sandwalk_core.Candidate_kind.t
  val reference : t -> string
  val rejected : t -> bool
end

module Repair_finding_result : sig
  type t

  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val finding_key : t -> Sandwalk_core.Finding_key.t
  val revision : t -> int
  val suspended_claims : t -> int
  val rejected_excerpts : t -> int
end

module Writer_evidence : sig
  type t

  val step : t -> string
  val finding : t -> string
  val verdict : t -> string
  val claim : t -> string
  val relation : t -> string
  val excerpt : t -> string
  val excerpt_path : t -> string
  val excerpt_md5 : t -> string
  val snapshot : t -> string
  val source_url : t -> string
  val line_start : t -> int
  val line_end : t -> int
end

module Writer_visual : sig
  type t

  val step : t -> string
  val finding : t -> string
  val verdict : t -> string
  val claim : t -> string
  val relation : t -> string
  val visual : t -> string
  val image_path : t -> string
  val image_md5 : t -> string
  val image_sha256 : t -> string
  val manifest_path : t -> string
  val manifest_md5 : t -> string
  val source_pdf_root : t -> string
  val source_pdf_artifact : t -> string
  val source_pdf_path : t -> string
  val source_pdf_sha256 : t -> string
  val description : t -> string
  val description_md5 : t -> string
  val snapshot : t -> string
  val source_url : t -> string
  val page : t -> int
end

module Submit_report_result : sig
  type t

  val revision : t -> int
  val block_count : t -> int
  val phase : t -> Sandwalk_core.Phase.t
end

module Review_report_result : sig
  type t

  val revision : t -> int
  val accepted : t -> bool
  val phase : t -> Sandwalk_core.Phase.t
end

module Current_report_block : sig
  type t

  val report_revision : t -> int
  val ordinal : t -> int
  val block_md5 : t -> string
  val block_text : t -> string
end

module Finding_review_context : sig
  type t

  val statement : t -> string
  val evidence : t -> (string * string * string) list
  val visuals : t -> (Visual_evidence.t * string) list
end

module Step_context : sig
  type t

  val objective : t -> string
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val step_title : t -> string
end

module Finalization_state : sig
  type t

  val report_revision : t -> int
  val report_path : t -> string
  val report_text : t -> string
  val report_md5 : t -> string
  val sources_by_finding : t -> (string * string list) list
end

module Completed_export_state : sig
  type t

  val final_report_md5 : t -> string
  val sources_md5 : t -> string
end

module Stored_hit : sig
  type t

  val hit_id : t -> Sandwalk_core.Hit_id.t
  val position : t -> int
  val url : t -> string
  val title : t -> string
  val snippet : t -> string
end

module Resume_entity : sig
  type t

  val kind : t -> string
  val reference : t -> string
  val step : t -> string option
  val detail : t -> string
end

module Research_guidance : sig
  type t =
    | Search of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; query : string
        }
    | Fetch of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; hit_id : Sandwalk_core.Hit_id.t
        ; title : string
        ; url : string
        ; snippet : string
        }
    | Create_excerpt of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; snapshot_id : Sandwalk_core.Snapshot_id.t
        ; document_path : string
        ; document_media_type : string
        }
    | Create_finding of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; excerpt_id : Sandwalk_core.Excerpt_id.t
        ; excerpt_path : string
        }
    | Attach_evidence of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; finding_key : Sandwalk_core.Finding_key.t
        ; excerpt_id : Sandwalk_core.Excerpt_id.t
        ; excerpt_path : string
        }
    | Seal_finding of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; finding_key : Sandwalk_core.Finding_key.t
        }
    | Review_finding of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        ; finding_key : Sandwalk_core.Finding_key.t
        }
    | Complete_step of
        { claim_id : Sandwalk_core.Claim_id.t
        ; step_key : Sandwalk_core.Plan_step.Key.t
        }
end

module Record_search_result : sig
  type t

  val previous_schema_version : t -> int
  val hits : t -> Stored_hit.t list
  val step_key : t -> Sandwalk_core.Plan_step.Key.t option
end

module Save_checkpoint_result : sig
  type t

  val previous_schema_version : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val checkpoint_number : t -> int
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
end

module Active_claim : sig
  type t

  val claim_id : t -> Sandwalk_core.Claim_id.t
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val attempt : t -> int
end

module Stored_plan_step : sig
  type t

  val key : t -> Sandwalk_core.Plan_step.Key.t
  val title : t -> string
  val required : t -> bool
  val position : t -> int
end

module Stored_plan_extension : sig
  type t

  val revision : t -> int
  val step_key : t -> Sandwalk_core.Plan_step.Key.t
  val reason : t -> string
end

module Plan_state : sig
  type t

  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val validated_revision : t -> int option
  val sealed_revision : t -> int option
  val objective : t -> string option
  val steps : t -> Stored_plan_step.t list
  val dependencies : t -> (string * string) list
  val extensions : t -> Stored_plan_extension.t list
end

module Mutate_plan_result : sig
  type t

  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase_path : t -> Sandwalk_core.Phase.t list
  val state : t -> Plan_state.t
end

module Recon_result : sig
  type t

  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase : t -> Sandwalk_core.Phase.t
  val observation_count : t -> int
end

module Raw_gc_plan : sig
  type t

  val plan_path : t -> string
  val plan_json : t -> string
  val plan_md5 : t -> string
  val artifact_paths : t -> string list
end

module Seal_plan_result : sig
  type t

  val previous_schema_version : t -> int
  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val already_sealed : t -> bool
  val steps : t -> Stored_plan_step.t list
  val objective : t -> string option
  val dependencies : t -> (string * string) list
end

module Validate_plan_result : sig
  type t

  val previous_schema_version : t -> int
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val already_validated : t -> bool
  val steps : t -> Stored_plan_step.t list
  val objective : t -> string option
  val dependencies : t -> (string * string) list
end

module Add_plan_step_result : sig
  type t

  val previous_schema_version : t -> int
  val previous_phase : t -> Sandwalk_core.Phase.t
  val phase_path : t -> Sandwalk_core.Phase.t list
  val phase : t -> Sandwalk_core.Phase.t
  val revision : t -> int
  val steps : t -> Stored_plan_step.t list
  val objective : t -> string option
  val dependencies : t -> (string * string) list
end

module Extend_plan_result : sig
  type t

  val previous_schema_version : t -> int
  val state : t -> Plan_state.t
  val position : t -> int
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

val extend_plan
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> step:Sandwalk_core.Plan_step.t
  -> dependencies:Sandwalk_core.Plan_step.Key.t list
  -> reason:Sandwalk_core.Plan_extension_reason.t
  -> reason_path:string
  -> reason_md5:string
  -> reason_size:int
  -> now:string
  -> unit
  -> (Extend_plan_result.t, Error.t) Result.t

val read_plan_steps
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Stored_plan_step.t list, Error.t) Result.t

val read_next_step
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Sandwalk_core.Plan_step.Key.t option, Error.t) Result.t

val read_plan_state
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Plan_state.t, Error.t) Result.t

val set_plan_objective
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> objective:string
  -> objective_path:string
  -> objective_md5:string
  -> objective_size:int
  -> now:string
  -> unit
  -> (Mutate_plan_result.t, Error.t) Result.t

val add_plan_dependency
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> dependency_key:Sandwalk_core.Plan_step.Key.t
  -> now:string
  -> unit
  -> (Mutate_plan_result.t, Error.t) Result.t

val start_reconnaissance
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> goal_text:string
  -> goal_path:string
  -> goal_md5:string
  -> goal_size:int
  -> now:string
  -> unit
  -> (Recon_result.t, Error.t) Result.t

val add_reconnaissance_observation
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> observation_text:string
  -> observation_path:string
  -> observation_md5:string
  -> observation_size:int
  -> now:string
  -> unit
  -> (Recon_result.t, Error.t) Result.t

val finish_reconnaissance
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> summary_text:string
  -> summary_path:string
  -> summary_md5:string
  -> summary_size:int
  -> now:string
  -> unit
  -> (Recon_result.t, Error.t) Result.t

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
  -> unit
  -> (Claim_step_result.t, Error.t) Result.t

val read_active_claims
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Active_claim.t list, Error.t) Result.t

val migrate_workspace
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (int, Error.t) Result.t

val read_research_guidance
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Research_guidance.t option, Error.t) Result.t

val read_current_report_blocks
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Current_report_block.t list, Error.t) Result.t

val read_step_context
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> step_key:string
  -> unit
  -> (Step_context.t, Error.t) Result.t

val read_finding_review_context
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> finding_reference:string
  -> unit
  -> (Finding_review_context.t, Error.t) Result.t

val reject_candidate
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> kind:Sandwalk_core.Candidate_kind.t
  -> reference:string
  -> reason_text:string
  -> reason_path:string
  -> reason_md5:string
  -> reason_size:int
  -> now:string
  -> unit
  -> (Candidate_rejection_result.t, Error.t) Result.t

val repair_finding
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> reason_text:string
  -> reason_path:string
  -> reason_md5:string
  -> reason_size:int
  -> now:string
  -> unit
  -> (Repair_finding_result.t, Error.t) Result.t

val read_resume_entities
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> unit
  -> (Resume_entity.t list, Error.t) Result.t

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
  -> adapter_metadata:Yojson.Safe.t
  -> source_root:string option
  -> hits:(Sandwalk_core.Hit_id.t * string * string * string) list
  -> now:string
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
  -> document_artifact:string
  -> document_media_type:string
  -> final_url:string
  -> input_sha256:string
  -> document_sha256:string
  -> manifest_json:string
  -> now:string
  -> unit
  -> (Record_snapshot_result.t, Error.t) Result.t

val promote_snapshot
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> now:string
  -> unit
  -> (Promote_snapshot_result.t, Error.t) Result.t

val snapshot_for_excerpt
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> unit
  -> (Snapshot_for_excerpt.t, Error.t) Result.t

val snapshot_for_visual
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> unit
  -> (Snapshot_for_visual.t, Error.t) Result.t

val record_excerpt
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t option
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> excerpt_id:Sandwalk_core.Excerpt_id.t
  -> artifact_path:string
  -> markdown_sha256:string
  -> line_start:int
  -> line_end:int
  -> byte_start:int
  -> byte_end:int
  -> excerpt_md5:string
  -> excerpt_size:int
  -> now:string
  -> unit
  -> (Record_excerpt_result.t, Error.t) Result.t

val record_visual
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> snapshot_id:Sandwalk_core.Snapshot_id.t
  -> visual_id:Sandwalk_core.Visual_id.t
  -> image_path:string
  -> manifest_path:string
  -> source_pdf_artifact:string
  -> source_pdf_sha256:string
  -> page:int
  -> page_count:int
  -> image_sha256:string
  -> image_md5:string
  -> image_size:int
  -> width:int
  -> height:int
  -> render_profile:string
  -> renderer_version:string
  -> description:string
  -> description_md5:string
  -> description_size:int
  -> manifest_json:string
  -> manifest_md5:string
  -> now:string
  -> unit
  -> (Record_visual_result.t, Error.t) Result.t

val read_visual
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> visual_id:Sandwalk_core.Visual_id.t
  -> unit
  -> (Visual_evidence.t, Error.t) Result.t

val create_finding
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> claim_text:string
  -> claim_md5:string
  -> claim_size:int
  -> now:string
  -> unit
  -> (Create_finding_result.t, Error.t) Result.t

val attach_evidence
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> excerpt_id:Sandwalk_core.Excerpt_id.t
  -> relation:Sandwalk_core.Finding_relation.t
  -> now:string
  -> unit
  -> (Attach_evidence_result.t, Error.t) Result.t

val attach_visual_evidence
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> visual_id:Sandwalk_core.Visual_id.t
  -> relation:Sandwalk_core.Finding_relation.t
  -> now:string
  -> unit
  -> (Attach_evidence_result.t, Error.t) Result.t

val seal_finding
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> now:string
  -> unit
  -> (Seal_finding_result.t, Error.t) Result.t

val review_finding
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> step_key:Sandwalk_core.Plan_step.Key.t
  -> finding_key:Sandwalk_core.Finding_key.t
  -> verdict:string
  -> summary:string
  -> source_quality:string
  -> conflicts:string
  -> qualifications:string
  -> reviewed_visuals:string list
  -> review_json:string
  -> review_md5:string
  -> now:string
  -> unit
  -> (Review_finding_result.t, Error.t) Result.t

val complete_step
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> claim_id:Sandwalk_core.Claim_id.t
  -> now:string
  -> unit
  -> (Complete_step_result.t, Error.t) Result.t

val read_writer_evidence
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Writer_evidence.t list, Error.t) Result.t

val read_writer_visuals
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Writer_visual.t list, Error.t) Result.t

val begin_drafting
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> now:string
  -> unit
  -> (Sandwalk_core.Phase.t, Error.t) Result.t

val submit_report
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> report_path:string
  -> report_text:string
  -> report_md5:string
  -> report_size:int
  -> blocks:(string * string * string list) list
  -> now:string
  -> unit
  -> (Submit_report_result.t, Error.t) Result.t

val validate_report_citations
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> citations:string list
  -> unit
  -> (unit, Error.t) Result.t

val review_report
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> report_revision:int
  -> reviews:(int * string * string * string) list
  -> now:string
  -> unit
  -> (Review_report_result.t, Error.t) Result.t

val read_finalization_state
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Finalization_state.t, Error.t) Result.t

val read_completed_export_state
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Completed_export_state.t, Error.t) Result.t

val finalize_workspace
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> report_revision:int
  -> final_report_md5:string
  -> sources_md5:string
  -> source_count:int
  -> now:string
  -> unit
  -> (Sandwalk_core.Phase.t, Error.t) Result.t

val read_raw_gc_candidates
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (string list, Error.t) Result.t

val record_raw_gc_plan
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> plan_path:string
  -> plan_json:string
  -> plan_md5:string
  -> now:string
  -> unit
  -> (unit, Error.t) Result.t

val read_raw_gc_plan
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> unit
  -> (Raw_gc_plan.t, Error.t) Result.t

val mark_raw_gc_applied
  :  ?busy_timeout_ms:int
  -> database_path:string
  -> expected_slug:Sandwalk_core.Slug.t
  -> plan_md5:string
  -> now:string
  -> unit
  -> (unit, Error.t) Result.t
