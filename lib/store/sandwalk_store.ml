open! Core

module Error = struct
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
    | Finding_wrong_phase of Sandwalk_core.Phase.t
    | Finding_step_mismatch
    | Finding_exists of string
    | Finding_not_found of string
    | Excerpt_not_found of string
    | Finding_excerpt_step_mismatch
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

module Hit_for_fetch = struct
  type t =
    { hit_id : Sandwalk_core.Hit_id.t
    ; url : string
    }

  let hit_id t = t.hit_id
  let url t = t.url
end

module Record_snapshot_result = struct
  type t =
    { previous_schema_version : int
    ; step_key : Sandwalk_core.Plan_step.Key.t option
    }

  let previous_schema_version t = t.previous_schema_version
  let step_key t = t.step_key
end

module Snapshot_for_excerpt = struct
  type t =
    { snapshot_id : Sandwalk_core.Snapshot_id.t
    ; artifact_path : string
    ; markdown_sha256 : string
    ; step_key : Sandwalk_core.Plan_step.Key.t option
    }

  let snapshot_id t = t.snapshot_id
  let artifact_path t = t.artifact_path
  let markdown_sha256 t = t.markdown_sha256
  let step_key t = t.step_key
end

module Promote_snapshot_result = struct
  type t =
    { previous_schema_version : int
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; promoted : bool
    }

  let previous_schema_version t = t.previous_schema_version
  let step_key t = t.step_key
  let promoted t = t.promoted
end

module Record_excerpt_result = struct
  type t =
    { excerpt_id : Sandwalk_core.Excerpt_id.t
    ; created : bool
    ; step_key : Sandwalk_core.Plan_step.Key.t option
    }

  let excerpt_id t = t.excerpt_id
  let created t = t.created
  let step_key t = t.step_key
end

module Create_finding_result = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; finding_key : Sandwalk_core.Finding_key.t
    ; revision : int
    }

  let step_key t = t.step_key
  let finding_key t = t.finding_key
  let revision t = t.revision
end

module Attach_evidence_result = struct
  type t =
    { revision : int
    ; attached : bool
    ; revised : bool
    }

  let revision t = t.revision
  let attached t = t.attached
  let revised t = t.revised
end

module Seal_finding_result = struct
  type t =
    { revision : int
    ; already_sealed : bool
    ; state : string
    }

  let revision t = t.revision
  let already_sealed t = t.already_sealed
  let state t = t.state
end

module Review_finding_result = struct
  type t =
    { revision : int
    ; reviewed : bool
    }

  let revision t = t.revision
  let reviewed t = t.reviewed
end

module Complete_step_result = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; phase : Sandwalk_core.Phase.t
    }

  let step_key t = t.step_key
  let phase t = t.phase
end

module Candidate_rejection_result = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; kind : Sandwalk_core.Candidate_kind.t
    ; reference : string
    ; rejected : bool
    }

  let step_key t = t.step_key
  let kind t = t.kind
  let reference t = t.reference
  let rejected t = t.rejected
end

module Repair_finding_result = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; finding_key : Sandwalk_core.Finding_key.t
    ; revision : int
    ; suspended_claims : int
    ; rejected_excerpts : int
    }

  let step_key t = t.step_key
  let finding_key t = t.finding_key
  let revision t = t.revision
  let suspended_claims t = t.suspended_claims
  let rejected_excerpts t = t.rejected_excerpts
end

module Writer_evidence = struct
  type t =
    { step : string
    ; finding : string
    ; verdict : string
    ; claim : string
    ; relation : string
    ; excerpt : string
    ; excerpt_path : string
    ; excerpt_md5 : string
    ; snapshot : string
    ; source_url : string
    ; line_start : int
    ; line_end : int
    }

  let step t = t.step
  let finding t = t.finding
  let verdict t = t.verdict
  let claim t = t.claim
  let relation t = t.relation
  let excerpt t = t.excerpt
  let excerpt_path t = t.excerpt_path
  let excerpt_md5 t = t.excerpt_md5
  let snapshot t = t.snapshot
  let source_url t = t.source_url
  let line_start t = t.line_start
  let line_end t = t.line_end
end

module Submit_report_result = struct
  type t =
    { revision : int
    ; block_count : int
    ; phase : Sandwalk_core.Phase.t
    }

  let revision t = t.revision
  let block_count t = t.block_count
  let phase t = t.phase
end

module Review_report_result = struct
  type t =
    { revision : int
    ; accepted : bool
    ; phase : Sandwalk_core.Phase.t
    }

  let revision t = t.revision
  let accepted t = t.accepted
  let phase t = t.phase
end

module Current_report_block = struct
  type t =
    { report_revision : int
    ; ordinal : int
    ; block_md5 : string
    ; block_text : string
    }

  let report_revision t = t.report_revision
  let ordinal t = t.ordinal
  let block_md5 t = t.block_md5
  let block_text t = t.block_text
end

module Finding_review_context = struct
  type t =
    { statement : string
    ; evidence : (string * string * string) list
    }

  let statement t = t.statement
  let evidence t = t.evidence
end

module Step_context = struct
  type t =
    { objective : string
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; step_title : string
    }

  let objective t = t.objective
  let step_key t = t.step_key
  let step_title t = t.step_title
end

module Finalization_state = struct
  type t =
    { report_revision : int
    ; report_path : string
    ; report_text : string
    ; report_md5 : string
    ; sources_by_finding : (string * string list) list
    }

  let report_revision t = t.report_revision
  let report_path t = t.report_path
  let report_text t = t.report_text
  let report_md5 t = t.report_md5
  let sources_by_finding t = t.sources_by_finding
end

module Stored_hit = struct
  type t =
    { hit_id : Sandwalk_core.Hit_id.t
    ; position : int
    ; url : string
    ; title : string
    ; snippet : string
    }

  let hit_id t = t.hit_id
  let position t = t.position
  let url t = t.url
  let title t = t.title
  let snippet t = t.snippet
end

module Resume_entity = struct
  type t =
    { kind : string
    ; reference : string
    ; step : string option
    ; detail : string
    }

  let kind t = t.kind
  let reference t = t.reference
  let step t = t.step
  let detail t = t.detail
end

module Research_guidance = struct
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

module Record_search_result = struct
  type t =
    { previous_schema_version : int
    ; hits : Stored_hit.t list
    ; step_key : Sandwalk_core.Plan_step.Key.t option
    }

  let previous_schema_version t = t.previous_schema_version
  let hits t = t.hits
  let step_key t = t.step_key
end

module Save_checkpoint_result = struct
  type t =
    { previous_schema_version : int
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; checkpoint_number : int
    }

  let previous_schema_version t = t.previous_schema_version
  let step_key t = t.step_key
  let checkpoint_number t = t.checkpoint_number
end

module Latest_checkpoint = struct
  type t =
    { step_key : Sandwalk_core.Plan_step.Key.t
    ; summary : string
    ; next : string
    ; created_at : string
    }

  let step_key t = t.step_key
  let summary t = t.summary
  let next t = t.next
  let created_at t = t.created_at
end

module Claim_step_result = struct
  type t =
    { previous_schema_version : int
    ; claim_id : Sandwalk_core.Claim_id.t
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; attempt : int
    ; previous_state : Sandwalk_core.Step_state.t
    }

  let previous_schema_version t = t.previous_schema_version
  let claim_id t = t.claim_id
  let step_key t = t.step_key
  let attempt t = t.attempt
  let previous_state t = t.previous_state
end

module Active_claim = struct
  type t =
    { claim_id : Sandwalk_core.Claim_id.t
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; attempt : int
    }

  let claim_id t = t.claim_id
  let step_key t = t.step_key
  let attempt t = t.attempt
end

module Stored_plan_step = struct
  type t =
    { key : Sandwalk_core.Plan_step.Key.t
    ; title : string
    ; required : bool
    ; position : int
    }

  let key t = t.key
  let title t = t.title
  let required t = t.required
  let position t = t.position
end

module Stored_plan_extension = struct
  type t =
    { revision : int
    ; step_key : Sandwalk_core.Plan_step.Key.t
    ; reason : string
    }

  let revision t = t.revision
  let step_key t = t.step_key
  let reason t = t.reason
end

module Plan_state = struct
  type t =
    { phase : Sandwalk_core.Phase.t
    ; revision : int
    ; validated_revision : int option
    ; sealed_revision : int option
    ; objective : string option
    ; steps : Stored_plan_step.t list
    ; dependencies : (string * string) list
    ; extensions : Stored_plan_extension.t list
    }

  let phase t = t.phase
  let revision t = t.revision
  let validated_revision t = t.validated_revision
  let sealed_revision t = t.sealed_revision
  let objective t = t.objective
  let steps t = t.steps
  let dependencies t = t.dependencies
  let extensions t = t.extensions
end

module Mutate_plan_result = struct
  type t =
    { previous_phase : Sandwalk_core.Phase.t
    ; phase_path : Sandwalk_core.Phase.t list
    ; state : Plan_state.t
    }

  let previous_phase t = t.previous_phase
  let phase_path t = t.phase_path
  let state t = t.state
end

module Recon_result = struct
  type t =
    { previous_phase : Sandwalk_core.Phase.t
    ; phase : Sandwalk_core.Phase.t
    ; observation_count : int
    }

  let previous_phase t = t.previous_phase
  let phase t = t.phase
  let observation_count t = t.observation_count
end

module Raw_gc_plan = struct
  type t =
    { plan_path : string
    ; plan_json : string
    ; plan_md5 : string
    ; artifact_paths : string list
    }

  let plan_path t = t.plan_path
  let plan_json t = t.plan_json
  let plan_md5 t = t.plan_md5
  let artifact_paths t = t.artifact_paths
end

module Validate_plan_result = struct
  type t =
    { previous_schema_version : int
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; already_validated : bool
    ; steps : Stored_plan_step.t list
    ; objective : string option
    ; dependencies : (string * string) list
    }

  let previous_schema_version t = t.previous_schema_version
  let phase t = t.phase
  let revision t = t.revision
  let already_validated t = t.already_validated
  let steps t = t.steps
  let objective t = t.objective
  let dependencies t = t.dependencies
end

module Seal_plan_result = struct
  type t =
    { previous_schema_version : int
    ; previous_phase : Sandwalk_core.Phase.t
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; already_sealed : bool
    ; steps : Stored_plan_step.t list
    ; objective : string option
    ; dependencies : (string * string) list
    }

  let previous_schema_version t = t.previous_schema_version
  let previous_phase t = t.previous_phase
  let phase t = t.phase
  let revision t = t.revision
  let already_sealed t = t.already_sealed
  let steps t = t.steps
  let objective t = t.objective
  let dependencies t = t.dependencies
end

module Add_plan_step_result = struct
  type t =
    { previous_schema_version : int
    ; previous_phase : Sandwalk_core.Phase.t
    ; phase_path : Sandwalk_core.Phase.t list
    ; phase : Sandwalk_core.Phase.t
    ; revision : int
    ; steps : Stored_plan_step.t list
    ; objective : string option
    ; dependencies : (string * string) list
    }

  let previous_schema_version t = t.previous_schema_version
  let previous_phase t = t.previous_phase
  let phase_path t = t.phase_path
  let phase t = t.phase
  let revision t = t.revision
  let steps t = t.steps
  let objective t = t.objective
  let dependencies t = t.dependencies
end

module Extend_plan_result = struct
  type t =
    { previous_schema_version : int
    ; state : Plan_state.t
    ; position : int
    }

  let previous_schema_version t = t.previous_schema_version
  let state t = t.state
  let position t = t.position
end

module Workspace_status = struct
  type t =
    { slug : Sandwalk_core.Slug.t
    ; phase : Sandwalk_core.Phase.t
    ; schema_version : int
    }

  let slug t = t.slug
  let phase t = t.phase
  let schema_version t = t.schema_version
end

let current_schema_version = 22

let check database return_code =
  if Sqlite3.Rc.is_success return_code
  then Ok ()
  else
    Error
      (Error.Database_error
         (sprintf
            "%s: %s"
            (Sqlite3.Rc.to_string return_code)
            (Sqlite3.errmsg database)))
;;

let execute database sql = check database (Sqlite3.exec database sql)

let with_statement database sql ~f =
  let statement = Sqlite3.prepare database sql in
  Exn.protect
    ~f:(fun () -> f statement)
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
;;

let bind_text database statement index value =
  check database (Sqlite3.bind_text statement index value)
;;

let step_done database statement =
  match Sqlite3.step statement with
  | Sqlite3.Rc.DONE -> Ok ()
  | return_code -> check database return_code
;;

let workspace_exists database =
  with_statement database "SELECT 1 FROM workspaces WHERE singleton = 1" ~f:(fun statement ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok true
    | Sqlite3.Rc.DONE -> Ok false
    | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let migration_v1 =
  {|
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS workspaces (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  slug TEXT NOT NULL CHECK (
    length(slug) BETWEEN 1 AND 63
    AND slug NOT GLOB '*[^a-z0-9-]*'
    AND slug NOT GLOB '-*'
    AND slug NOT GLOB '*-'
    AND slug NOT GLOB '*--*'
  ),
  phase TEXT NOT NULL CHECK (
    phase IN (
      'initialized', 'scoping', 'reconnaissance', 'planning', 'researching',
      'evidence-review', 'drafting', 'draft-review', 'finalizing', 'completed'
    )
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
PRAGMA user_version = 1;
|}
;;

let migration_v2 =
  {|
CREATE TABLE plan_steps (
  step_key TEXT PRIMARY KEY CHECK (
    length(step_key) BETWEEN 1 AND 63
    AND step_key NOT GLOB '*[^a-z0-9-]*'
    AND step_key NOT GLOB '-*'
    AND step_key NOT GLOB '*-'
    AND step_key NOT GLOB '*--*'
  ),
  title TEXT NOT NULL CHECK (
    length(CAST(title AS BLOB)) BETWEEN 1 AND 200
    AND title = trim(title)
  ),
  position INTEGER NOT NULL UNIQUE CHECK (position >= 1),
  required INTEGER NOT NULL CHECK (required IN (0, 1)),
  created_at TEXT NOT NULL
);
CREATE TABLE plan_metadata (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  revision INTEGER NOT NULL CHECK (revision >= 0)
);
INSERT INTO plan_metadata (singleton, revision) VALUES (1, 0);
PRAGMA user_version = 2;
|}
;;

let migration_v3 =
  {|
ALTER TABLE plan_metadata ADD COLUMN validated_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN validated_at TEXT;
PRAGMA user_version = 3;
|}
;;

let migration_v4 =
  {|
ALTER TABLE plan_metadata ADD COLUMN sealed_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN sealed_at TEXT;
PRAGMA user_version = 4;
|}
;;

let migration_v5 =
  {|
CREATE TABLE step_executions (
  step_key TEXT PRIMARY KEY REFERENCES plan_steps(step_key),
  state TEXT NOT NULL CHECK (
    state IN ('pending', 'claimed', 'suspended', 'expired', 'blocked', 'completed')
  ),
  active_claim_id TEXT UNIQUE,
  lease_expires_unix_seconds INTEGER,
  attempt INTEGER NOT NULL CHECK (attempt >= 0),
  CHECK (
    (state = 'claimed' AND active_claim_id IS NOT NULL
      AND lease_expires_unix_seconds IS NOT NULL)
    OR
    (state <> 'claimed' AND active_claim_id IS NULL
      AND lease_expires_unix_seconds IS NULL)
  )
);
CREATE TABLE claims (
  claim_id TEXT PRIMARY KEY CHECK (
    length(claim_id) = 38
    AND substr(claim_id, 1, 6) = 'claim_'
    AND substr(claim_id, 7) NOT GLOB '*[^a-f0-9]*'
  ),
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  attempt INTEGER NOT NULL CHECK (attempt >= 1),
  issued_at TEXT NOT NULL,
  lease_expires_at TEXT NOT NULL,
  lease_expires_unix_seconds INTEGER NOT NULL,
  ended_at TEXT,
  end_reason TEXT CHECK (
    end_reason IS NULL OR end_reason IN ('expired', 'suspended', 'blocked', 'completed')
  )
);
INSERT INTO step_executions (step_key, state, attempt)
SELECT step_key, 'pending', 0 FROM plan_steps;
PRAGMA user_version = 5;
|}
;;

let migration_v6 =
  {|
ALTER TABLE claims ADD COLUMN lease_duration_seconds INTEGER
  CHECK (lease_duration_seconds BETWEEN 30 AND 86400);
UPDATE claims
SET lease_duration_seconds = 900
WHERE lease_duration_seconds IS NULL;
CREATE TABLE checkpoints (
  checkpoint_id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  claim_id TEXT NOT NULL REFERENCES claims(claim_id),
  checkpoint_number INTEGER NOT NULL CHECK (checkpoint_number >= 1),
  created_at TEXT NOT NULL,
  summary TEXT NOT NULL,
  next TEXT NOT NULL,
  summary_path TEXT NOT NULL,
  summary_md5 TEXT NOT NULL,
  summary_size INTEGER NOT NULL CHECK (summary_size >= 0),
  next_path TEXT NOT NULL,
  next_md5 TEXT NOT NULL,
  next_size INTEGER NOT NULL CHECK (next_size >= 0),
  UNIQUE (step_key, checkpoint_number)
);
PRAGMA user_version = 6;
|}
;;

let migration_v7 =
  {|
CREATE TABLE search_queries (
  query_id INTEGER PRIMARY KEY AUTOINCREMENT,
  query TEXT NOT NULL,
  phase TEXT NOT NULL,
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  adapter TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE search_hits (
  hit_ref TEXT PRIMARY KEY CHECK (
    length(hit_ref) = 36
    AND substr(hit_ref, 1, 4) = 'hit_'
    AND substr(hit_ref, 5) NOT GLOB '*[^a-f0-9]*'
  ),
  query_id INTEGER NOT NULL REFERENCES search_queries(query_id),
  position INTEGER NOT NULL CHECK (position >= 1),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  snippet TEXT NOT NULL,
  UNIQUE (query_id, position)
);
PRAGMA user_version = 7;
|}
;;

let migration_v8 =
  {|
CREATE TABLE snapshots (
  snapshot_ref TEXT PRIMARY KEY CHECK (
    length(snapshot_ref) = 37
    AND substr(snapshot_ref, 1, 5) = 'snap_'
    AND substr(snapshot_ref, 6) NOT GLOB '*[^a-f0-9]*'
  ),
  hit_ref TEXT NOT NULL REFERENCES search_hits(hit_ref),
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  artifact_path TEXT NOT NULL UNIQUE,
  final_url TEXT NOT NULL,
  input_sha256 TEXT NOT NULL,
  markdown_sha256 TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  retrieved_at TEXT NOT NULL
);
PRAGMA user_version = 8;
|}
;;

let migration_v9 =
  {|
CREATE TABLE excerpts (
  excerpt_ref TEXT PRIMARY KEY CHECK (
    length(excerpt_ref) = 40
    AND substr(excerpt_ref, 1, 8) = 'excerpt_'
    AND substr(excerpt_ref, 9) NOT GLOB '*[^a-f0-9]*'
  ),
  snapshot_ref TEXT NOT NULL REFERENCES snapshots(snapshot_ref),
  claim_id TEXT REFERENCES claims(claim_id),
  step_key TEXT REFERENCES plan_steps(step_key),
  artifact_path TEXT NOT NULL UNIQUE,
  markdown_sha256 TEXT NOT NULL CHECK (
    length(markdown_sha256) = 64
    AND markdown_sha256 NOT GLOB '*[^a-f0-9]*'
  ),
  line_start INTEGER NOT NULL CHECK (line_start >= 1),
  line_end INTEGER NOT NULL CHECK (line_end >= line_start),
  byte_start INTEGER NOT NULL CHECK (byte_start >= 0),
  byte_end INTEGER NOT NULL CHECK (byte_end > byte_start),
  excerpt_md5 TEXT NOT NULL CHECK (
    length(excerpt_md5) = 32
    AND excerpt_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  excerpt_size INTEGER NOT NULL CHECK (excerpt_size = byte_end - byte_start),
  created_at TEXT NOT NULL,
  UNIQUE (snapshot_ref, byte_start, byte_end)
);
PRAGMA user_version = 9;
|}
;;

let migration_v10 =
  {|
CREATE TABLE findings (
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  finding_key TEXT NOT NULL CHECK (
    length(finding_key) BETWEEN 1 AND 63
    AND finding_key NOT GLOB '*[^a-z0-9-]*'
    AND finding_key NOT GLOB '-*'
    AND finding_key NOT GLOB '*-'
    AND finding_key NOT GLOB '*--*'
  ),
  current_revision INTEGER NOT NULL CHECK (current_revision >= 1),
  state TEXT NOT NULL CHECK (state IN ('draft', 'sealed', 'reviewed')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (step_key, finding_key)
);
CREATE TABLE finding_revisions (
  step_key TEXT NOT NULL,
  finding_key TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  claim_text TEXT NOT NULL,
  claim_md5 TEXT NOT NULL CHECK (
    length(claim_md5) = 32
    AND claim_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  claim_size INTEGER NOT NULL CHECK (claim_size > 0 AND claim_size <= 65536),
  created_at TEXT NOT NULL,
  sealed_at TEXT,
  PRIMARY KEY (step_key, finding_key, revision),
  FOREIGN KEY (step_key, finding_key)
    REFERENCES findings(step_key, finding_key)
);
PRAGMA user_version = 10;
|}
;;

let migration_v11 =
  {|
CREATE TABLE finding_evidence (
  step_key TEXT NOT NULL,
  finding_key TEXT NOT NULL,
  revision INTEGER NOT NULL,
  excerpt_ref TEXT NOT NULL REFERENCES excerpts(excerpt_ref),
  relation TEXT NOT NULL CHECK (
    relation IN ('supports', 'contradicts', 'qualifies', 'context')
  ),
  attached_at TEXT NOT NULL,
  PRIMARY KEY (step_key, finding_key, revision, excerpt_ref, relation),
  FOREIGN KEY (step_key, finding_key, revision)
    REFERENCES finding_revisions(step_key, finding_key, revision)
);
PRAGMA user_version = 11;
|}
;;

let migration_v12 =
  {|
CREATE TABLE finding_reviews (
  step_key TEXT NOT NULL,
  finding_key TEXT NOT NULL,
  revision INTEGER NOT NULL,
  verdict TEXT NOT NULL CHECK (
    verdict IN (
      'supported', 'partially-supported', 'unsupported', 'contradicted'
    )
  ),
  summary TEXT NOT NULL,
  source_quality TEXT NOT NULL,
  conflicts TEXT NOT NULL,
  qualifications TEXT NOT NULL,
  review_json TEXT NOT NULL,
  review_md5 TEXT NOT NULL CHECK (
    length(review_md5) = 32
    AND review_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  reviewed_at TEXT NOT NULL,
  PRIMARY KEY (step_key, finding_key, revision),
  FOREIGN KEY (step_key, finding_key, revision)
    REFERENCES finding_revisions(step_key, finding_key, revision)
);
PRAGMA user_version = 12;
|}
;;

let migration_v13 =
  {|
CREATE TABLE reports (
  revision INTEGER PRIMARY KEY CHECK (revision >= 1),
  report_path TEXT NOT NULL,
  report_text TEXT NOT NULL,
  report_md5 TEXT NOT NULL CHECK (
    length(report_md5) = 32
    AND report_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  report_size INTEGER NOT NULL CHECK (report_size > 0 AND report_size <= 1048576),
  submitted_at TEXT NOT NULL,
  current INTEGER NOT NULL CHECK (current IN (0, 1))
);
CREATE UNIQUE INDEX one_current_report ON reports(current) WHERE current = 1;
CREATE TABLE report_blocks (
  report_revision INTEGER NOT NULL REFERENCES reports(revision),
  ordinal INTEGER NOT NULL CHECK (ordinal >= 1),
  block_text TEXT NOT NULL,
  block_md5 TEXT NOT NULL CHECK (
    length(block_md5) = 32
    AND block_md5 NOT GLOB '*[^a-f0-9]*'
  ),
  citations_json TEXT NOT NULL,
  PRIMARY KEY (report_revision, ordinal)
);
PRAGMA user_version = 13;
|}
;;

let migration_v14 =
  {|
CREATE TABLE report_block_reviews (
  report_revision INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  verdict TEXT NOT NULL CHECK (
    verdict IN (
      'supported', 'partially-supported', 'unsupported', 'contradicted'
    )
  ),
  summary TEXT NOT NULL,
  block_md5 TEXT NOT NULL,
  reviewed_at TEXT NOT NULL,
  PRIMARY KEY (report_revision, ordinal),
  FOREIGN KEY (report_revision, ordinal)
    REFERENCES report_blocks(report_revision, ordinal)
);
PRAGMA user_version = 14;
|}
;;

let migration_v15 =
  {|
CREATE TABLE finalizations (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  report_revision INTEGER NOT NULL REFERENCES reports(revision),
  final_report_md5 TEXT NOT NULL CHECK (length(final_report_md5) = 32),
  sources_md5 TEXT NOT NULL CHECK (length(sources_md5) = 32),
  source_count INTEGER NOT NULL CHECK (source_count >= 1),
  completed_at TEXT NOT NULL
);
PRAGMA user_version = 15;
|}
;;

let migration_v16 =
  {|
CREATE TABLE plan_objective (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  objective_text TEXT NOT NULL,
  objective_path TEXT NOT NULL,
  objective_md5 TEXT NOT NULL CHECK (length(objective_md5) = 32),
  objective_size INTEGER NOT NULL CHECK (
    objective_size > 0 AND objective_size <= 65536
  ),
  updated_at TEXT NOT NULL
);
CREATE TABLE plan_dependencies (
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  dependency_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  created_at TEXT NOT NULL,
  PRIMARY KEY (step_key, dependency_key),
  CHECK (step_key <> dependency_key)
);
PRAGMA user_version = 16;
|}
;;

let migration_v17 =
  {|
CREATE TABLE reconnaissance (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  goal_text TEXT NOT NULL,
  goal_path TEXT NOT NULL,
  goal_md5 TEXT NOT NULL CHECK (length(goal_md5) = 32),
  goal_size INTEGER NOT NULL CHECK (goal_size > 0 AND goal_size <= 65536),
  started_at TEXT NOT NULL,
  summary_text TEXT,
  summary_path TEXT,
  summary_md5 TEXT,
  summary_size INTEGER,
  finished_at TEXT
);
CREATE TABLE reconnaissance_observations (
  observation_id INTEGER PRIMARY KEY AUTOINCREMENT,
  observation_text TEXT NOT NULL,
  observation_path TEXT NOT NULL,
  observation_md5 TEXT NOT NULL CHECK (length(observation_md5) = 32),
  observation_size INTEGER NOT NULL CHECK (
    observation_size > 0 AND observation_size <= 65536
  ),
  created_at TEXT NOT NULL
);
PRAGMA user_version = 17;
|}
;;

let migration_v18 =
  {|
CREATE TABLE raw_gc_plan (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  plan_path TEXT NOT NULL,
  plan_json TEXT NOT NULL,
  plan_md5 TEXT NOT NULL CHECK (length(plan_md5) = 32),
  created_at TEXT NOT NULL,
  applied_at TEXT
);
PRAGMA user_version = 18;
|}
;;

let migration_v19 =
  {|
CREATE TABLE plan_extensions (
  revision INTEGER PRIMARY KEY CHECK (revision >= 1),
  step_key TEXT NOT NULL UNIQUE REFERENCES plan_steps(step_key),
  reason_text TEXT NOT NULL CHECK (
    length(CAST(reason_text AS BLOB)) BETWEEN 1 AND 65536
  ),
  reason_path TEXT NOT NULL,
  reason_md5 TEXT NOT NULL CHECK (length(reason_md5) = 32),
  reason_size INTEGER NOT NULL CHECK (
    reason_size > 0 AND reason_size <= 65536
  ),
  created_at TEXT NOT NULL
);
PRAGMA user_version = 19;
|}
;;

let migration_v20 =
  {|
CREATE TABLE snapshot_promotions (
  snapshot_ref TEXT PRIMARY KEY REFERENCES snapshots(snapshot_ref),
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  claim_id TEXT NOT NULL REFERENCES claims(claim_id),
  promoted_at TEXT NOT NULL
);
PRAGMA user_version = 20;
|}
;;

let migration_v21 =
  {|
UPDATE step_executions
SET state = 'suspended'
WHERE state = 'expired';
UPDATE claims
SET end_reason = 'suspended'
WHERE end_reason = 'expired';
PRAGMA user_version = 21;
|}
;;

let migration_v22 =
  {|
CREATE TABLE candidate_rejections (
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  candidate_kind TEXT NOT NULL CHECK (
    candidate_kind IN ('hit', 'snapshot', 'excerpt')
  ),
  candidate_ref TEXT NOT NULL,
  claim_id TEXT REFERENCES claims(claim_id),
  reason_text TEXT NOT NULL CHECK (
    length(CAST(reason_text AS BLOB)) BETWEEN 1 AND 65536
  ),
  reason_path TEXT NOT NULL,
  reason_md5 TEXT NOT NULL CHECK (length(reason_md5) = 32),
  reason_size INTEGER NOT NULL CHECK (
    reason_size > 0 AND reason_size <= 65536
  ),
  rejected_at TEXT NOT NULL,
  PRIMARY KEY (step_key, candidate_kind, candidate_ref)
);
CREATE TABLE finding_repairs (
  repair_id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_key TEXT NOT NULL,
  finding_key TEXT NOT NULL,
  previous_revision INTEGER NOT NULL CHECK (previous_revision >= 1),
  repair_revision INTEGER NOT NULL CHECK (repair_revision > previous_revision),
  reason_text TEXT NOT NULL CHECK (
    length(CAST(reason_text AS BLOB)) BETWEEN 1 AND 65536
  ),
  reason_path TEXT NOT NULL,
  reason_md5 TEXT NOT NULL CHECK (length(reason_md5) = 32),
  reason_size INTEGER NOT NULL CHECK (
    reason_size > 0 AND reason_size <= 65536
  ),
  created_at TEXT NOT NULL,
  FOREIGN KEY (step_key, finding_key)
    REFERENCES findings(step_key, finding_key),
  UNIQUE (step_key, finding_key, repair_revision)
);
PRAGMA user_version = 22;
|}
;;

let insert_migration database ~version ~now =
  with_statement
    database
    "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?1, ?2)"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = check database (Sqlite3.bind_int statement 1 version) in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let query_schema_version database =
  with_statement database "PRAGMA user_version" ~f:(fun statement ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
    | Sqlite3.Rc.DONE -> Error Error.Not_initialized
    | return_code ->
      check database return_code
      |> Result.map ~f:(fun () -> current_schema_version))
;;

let migrate database ~from_version ~now =
  let open Result.Let_syntax in
  if from_version < 0 || from_version > current_schema_version
  then Error (Error.Unsupported_schema_version from_version)
  else (
    let%bind () =
      if from_version < 1
      then (
        let%bind () = execute database migration_v1 in
        insert_migration database ~version:1 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 2
      then (
        let%bind () = execute database migration_v2 in
        insert_migration database ~version:2 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 3
      then (
        let%bind () = execute database migration_v3 in
        insert_migration database ~version:3 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 4
      then (
        let%bind () = execute database migration_v4 in
        insert_migration database ~version:4 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 5
      then (
        let%bind () = execute database migration_v5 in
        insert_migration database ~version:5 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 6
      then (
        let%bind () = execute database migration_v6 in
        insert_migration database ~version:6 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 7
      then (
        let%bind () = execute database migration_v7 in
        insert_migration database ~version:7 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 8
      then (
        let%bind () = execute database migration_v8 in
        insert_migration database ~version:8 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 9
      then (
        let%bind () = execute database migration_v9 in
        insert_migration database ~version:9 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 10
      then (
        let%bind () = execute database migration_v10 in
        insert_migration database ~version:10 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 11
      then (
        let%bind () = execute database migration_v11 in
        insert_migration database ~version:11 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 12
      then (
        let%bind () = execute database migration_v12 in
        insert_migration database ~version:12 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 13
      then (
        let%bind () = execute database migration_v13 in
        insert_migration database ~version:13 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 14
      then (
        let%bind () = execute database migration_v14 in
        insert_migration database ~version:14 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 15
      then (
        let%bind () = execute database migration_v15 in
        insert_migration database ~version:15 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 16
      then (
        let%bind () = execute database migration_v16 in
        insert_migration database ~version:16 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 17
      then (
        let%bind () = execute database migration_v17 in
        insert_migration database ~version:17 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 18
      then (
        let%bind () = execute database migration_v18 in
        insert_migration database ~version:18 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 19
      then (
        let%bind () = execute database migration_v19 in
        insert_migration database ~version:19 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 20
      then (
        let%bind () = execute database migration_v20 in
        insert_migration database ~version:20 ~now)
      else Ok ()
    in
    let%bind () =
      if from_version < 21
      then (
        let%bind () = execute database migration_v21 in
        insert_migration database ~version:21 ~now)
      else Ok ()
    in
    if from_version < 22
    then (
      let%bind () = execute database migration_v22 in
      insert_migration database ~version:22 ~now)
    else Ok ())
;;

let insert_workspace database ~slug ~now =
  with_statement
    database
    {|
INSERT INTO workspaces (singleton, slug, phase, created_at, updated_at)
VALUES (1, ?1, 'initialized', ?2, ?2)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Slug.to_string slug)
      in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let initialize ?(busy_timeout_ms = 5_000) ~database_path ~slug ~now () =
  let database = Sqlite3.db_open database_path in
  Exn.protect
    ~f:(fun () ->
      try
        Sqlite3.busy_timeout database busy_timeout_ms;
        let open Result.Let_syntax in
        let%bind () = execute database "PRAGMA journal_mode = WAL" in
        let%bind () = execute database "PRAGMA foreign_keys = ON" in
        let%bind () = execute database "BEGIN IMMEDIATE" in
        let outcome =
          let%bind schema_version = query_schema_version database in
          let%bind () = migrate database ~from_version:schema_version ~now in
          let%bind exists = workspace_exists database in
          if exists
          then Error Error.Already_initialized
          else insert_workspace database ~slug ~now
        in
        (match outcome with
         | Ok () ->
           let%map () = execute database "COMMIT" in
           ()
         | Error _ as error ->
           ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
           error)
      with
      | exn -> Error (Error.Database_error (Exn.to_string exn)))
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
;;

let query_workspace database =
  with_statement
    database
    "SELECT slug, phase FROM workspaces WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        Ok (Sqlite3.column_text statement 0, Sqlite3.column_text statement 1)
      | Sqlite3.Rc.DONE -> Error Error.Not_initialized
      | return_code ->
        check database return_code
        |> Result.map ~f:(fun () -> assert false))
;;

let read_status
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          let%bind () =
            if schema_version >= 1 && schema_version <= current_schema_version
            then Ok ()
            else Error (Error.Unsupported_schema_version schema_version)
          in
          let%bind slug_text, phase_text = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind phase =
            Sandwalk_core.Phase.of_string phase_text
            |> Result.of_option
                 ~error:(Error.Invalid_persisted_phase phase_text)
          in
          Ok
            { Workspace_status.slug = expected_slug
            ; phase
            ; schema_version
            }
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let plan_step_exists database key =
  with_statement
    database
    "SELECT 1 FROM plan_steps WHERE step_key = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = bind_text database statement 1 key in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok true
      | Sqlite3.Rc.DONE -> Ok false
      | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let next_plan_position database =
  with_statement
    database
    "SELECT COALESCE(MAX(position), 0) + 1 FROM plan_steps"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE -> Ok 1
      | return_code -> check database return_code |> Result.map ~f:(Fn.const 1))
;;

let insert_plan_step database ~step ~position ~now =
  with_statement
    database
    {|
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES (?1, ?2, ?3, ?4, ?5)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.key step
           |> Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () =
        bind_text database statement 2 (Sandwalk_core.Plan_step.title step)
      in
      let%bind () = check database (Sqlite3.bind_int statement 3 position) in
      let%bind () =
        check
          database
          (Sqlite3.bind_int
             statement
             4
             (if Sandwalk_core.Plan_step.required step then 1 else 0))
      in
      let%bind () = bind_text database statement 5 now in
      step_done database statement)
;;

let insert_step_execution database ~step =
  with_statement
    database
    {|
INSERT INTO step_executions (step_key, state, attempt)
VALUES (?1, 'pending', 0)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.key step
           |> Sandwalk_core.Plan_step.Key.to_string)
      in
      step_done database statement)
;;

let update_phase database ~phase ~now =
  with_statement
    database
    "UPDATE workspaces SET phase = ?1, updated_at = ?2 WHERE singleton = 1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Phase.to_string phase)
      in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let increment_plan_revision database =
  let open Result.Let_syntax in
  let%bind () =
    execute
      database
      "UPDATE plan_metadata SET revision = revision + 1 WHERE singleton = 1"
  in
  with_statement
    database
    "SELECT revision FROM plan_metadata WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const 0))
;;

let query_plan_validation database =
  with_statement
    database
    "SELECT revision, validated_revision FROM plan_metadata WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        Ok
          ( Sqlite3.column_int statement 0
          , if Sqlite3.column_is_null statement 1
            then None
            else Some (Sqlite3.column_int statement 1) )
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const (0, None)))
;;

let mark_plan_validated database ~revision ~now =
  with_statement
    database
    {|
UPDATE plan_metadata
SET validated_revision = ?1, validated_at = ?2
WHERE singleton = 1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = check database (Sqlite3.bind_int statement 1 revision) in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let query_plan_seal database =
  with_statement
    database
    {|
SELECT revision, validated_revision, sealed_revision
FROM plan_metadata
WHERE singleton = 1
|}
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let optional_int column =
          if Sqlite3.column_is_null statement column
          then None
          else Some (Sqlite3.column_int statement column)
        in
        Ok
          ( Sqlite3.column_int statement 0
          , optional_int 1
          , optional_int 2 )
      | Sqlite3.Rc.DONE ->
        Error (Error.Database_error "Missing plan metadata")
      | return_code ->
        check database return_code
        |> Result.map ~f:(Fn.const (0, None, None)))
;;

let mark_plan_sealed database ~revision ~now =
  with_statement
    database
    {|
UPDATE plan_metadata
SET sealed_revision = ?1, sealed_at = ?2
WHERE singleton = 1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () = check database (Sqlite3.bind_int statement 1 revision) in
      let%bind () = bind_text database statement 2 now in
      step_done database statement)
;;

let query_plan_steps database =
  let steps = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT step_key, title, required, position
FROM plan_steps
ORDER BY position
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some key; Some title; Some required; Some position |] ->
             let key =
               match Sandwalk_core.Plan_step.Key.of_string key with
               | Ok key -> key
               | Error _ -> failwith "Invalid persisted plan step key"
             in
             steps :=
               { Stored_plan_step.key = key
               ; title
               ; required = String.equal required "1"
               ; position = Int.of_string position
               }
               :: !steps
           | _ -> failwith "Invalid persisted plan step row"))
  in
  List.rev !steps
;;

let read_plan_steps ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 2
          then Ok []
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_plan_steps database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let read_next_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 5
          then Ok None
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else
            let query =
              if schema_version < 16
              then
                {|
SELECT p.step_key
FROM plan_steps p
JOIN step_executions e ON e.step_key = p.step_key
WHERE e.state IN ('pending', 'suspended', 'expired', 'blocked')
ORDER BY p.position
LIMIT 1
|}
              else if schema_version < 21
              then
                {|
SELECT p.step_key
FROM plan_steps p
JOIN step_executions e ON e.step_key = p.step_key
WHERE e.state IN ('pending', 'suspended', 'expired', 'blocked')
  AND NOT EXISTS (
    SELECT 1
    FROM plan_dependencies d
    JOIN step_executions de ON de.step_key = d.dependency_key
    WHERE d.step_key = p.step_key AND de.state <> 'completed'
  )
ORDER BY p.position
LIMIT 1
|}
              else
                {|
SELECT p.step_key
FROM plan_steps p
JOIN step_executions e ON e.step_key = p.step_key
WHERE e.state IN ('pending', 'suspended', 'blocked')
  AND NOT EXISTS (
    SELECT 1
    FROM plan_dependencies d
    JOIN step_executions de ON de.step_key = d.dependency_key
    WHERE d.step_key = p.step_key AND de.state <> 'completed'
  )
ORDER BY p.position
LIMIT 1
|}
            in
            with_statement
              database
              query
            ~f:(fun statement ->
              match Sqlite3.step statement with
              | Sqlite3.Rc.ROW ->
                Sqlite3.column_text statement 0
                |> Sandwalk_core.Plan_step.Key.of_string
                |> Result.map ~f:Option.some
                |> Result.map_error ~f:(fun _ ->
                  Error.Database_error "Invalid persisted plan step.")
              | Sqlite3.Rc.DONE -> Ok None
              | return_code ->
                check database return_code |> Result.map ~f:(Fn.const None))
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_plan_objective database =
  with_statement
    database
    "SELECT objective_text FROM plan_objective WHERE singleton = 1"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Some (Sqlite3.column_text statement 0))
      | Sqlite3.Rc.DONE -> Ok None
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const None))
;;

let query_plan_dependencies database =
  let dependencies = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT step_key, dependency_key
FROM plan_dependencies
ORDER BY step_key, dependency_key
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some step; Some dependency |] ->
             dependencies := (step, dependency) :: !dependencies
           | _ -> failwith "Invalid persisted plan dependency."))
  in
  List.rev !dependencies
;;

let query_plan_extensions database =
  let extensions = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT revision, step_key, reason_text
FROM plan_extensions
ORDER BY revision
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some revision; Some step_key; Some reason |] ->
             let step_key =
               match Sandwalk_core.Plan_step.Key.of_string step_key with
               | Ok step_key -> step_key
               | Error _ -> failwith "Invalid persisted extension step key."
             in
             extensions :=
               { Stored_plan_extension.revision = Int.of_string revision
               ; step_key
               ; reason
               }
               :: !extensions
           | _ -> failwith "Invalid persisted plan extension."))
  in
  List.rev !extensions
;;

let query_plan_state database ~schema_version =
  let open Result.Let_syntax in
  let%bind _, phase_text = query_workspace database in
  let%bind phase =
    Sandwalk_core.Phase.of_string phase_text
    |> Result.of_option ~error:(Error.Invalid_persisted_phase phase_text)
  in
  let%bind revision, validated_revision, sealed_revision =
    if schema_version >= 4
    then query_plan_seal database
    else if schema_version >= 3
    then (
      let%map revision, validated = query_plan_validation database in
      revision, validated, None)
    else
      with_statement
        database
        "SELECT revision FROM plan_metadata WHERE singleton = 1"
        ~f:(fun statement ->
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW ->
            Ok (Sqlite3.column_int statement 0, None, None)
          | _ -> Error (Error.Database_error "Missing plan metadata"))
  in
  let%bind steps = query_plan_steps database in
  let%bind objective =
    if schema_version >= 16 then query_plan_objective database else Ok None
  in
  let%bind dependencies =
    if schema_version >= 16 then query_plan_dependencies database else Ok []
  in
  let%map extensions =
    if schema_version >= 19 then query_plan_extensions database else Ok []
  in
  { Plan_state.phase
  ; revision
  ; validated_revision
  ; sealed_revision
  ; objective
  ; steps
  ; dependencies
  ; extensions
  }
;;

let read_plan_state
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          let%bind slug_text, _ = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          if schema_version < 2
          then Error (Error.Database_error "Plan is not initialized.")
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_plan_state database ~schema_version
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let set_plan_objective
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~objective
      ~objective_path
      ~objective_md5
      ~objective_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind current_phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind phase_path =
              Sandwalk_core.Planning.transition_path current_phase
              |> Result.map_error ~f:(fun _ ->
                Error.Plan_objective_wrong_phase current_phase)
            in
            let phase =
              List.last phase_path |> Option.value ~default:current_phase
            in
            let%bind () =
              List.fold_result
                phase_path
                ~init:current_phase
                ~f:(fun from into ->
                  Sandwalk_core.transition ~from ~into
                  |> Result.map_error ~f:(fun _ ->
                    Error.Plan_objective_wrong_phase from))
              |> Result.map ~f:ignore
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO plan_objective (
  singleton, objective_text, objective_path, objective_md5,
  objective_size, updated_at
) VALUES (1, ?1, ?2, ?3, ?4, ?5)
ON CONFLICT(singleton) DO UPDATE SET
  objective_text = excluded.objective_text,
  objective_path = excluded.objective_path,
  objective_md5 = excluded.objective_md5,
  objective_size = excluded.objective_size,
  updated_at = excluded.updated_at
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 objective in
                  let%bind () = bind_text database statement 2 objective_path in
                  let%bind () = bind_text database statement 3 objective_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 4 objective_size)
                  in
                  let%bind () = bind_text database statement 5 now in
                  step_done database statement)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase current_phase
              then Ok ()
              else update_phase database ~phase ~now
            in
            let%bind _ = increment_plan_revision database in
            let%map state = query_plan_state database ~schema_version:16 in
            { Mutate_plan_result.previous_phase = current_phase
            ; phase_path
            ; state
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let add_plan_dependency
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step_key
      ~dependency_key
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Planning
              then Ok ()
              else Error (Error.Plan_dependency_wrong_phase phase)
            in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let dependency =
              Sandwalk_core.Plan_step.Key.to_string dependency_key
            in
            let%bind () =
              if String.equal step dependency
              then Error Error.Plan_dependency_self
              else Ok ()
            in
            let%bind step_exists = plan_step_exists database step in
            let%bind dependency_exists =
              plan_step_exists database dependency
            in
            let%bind () =
              if not step_exists
              then Error (Error.Plan_step_not_found step)
              else if not dependency_exists
              then Error (Error.Plan_step_not_found dependency)
              else Ok ()
            in
            let%bind exists =
              with_statement
                database
                {|
SELECT 1 FROM plan_dependencies
WHERE step_key = ?1 AND dependency_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 dependency in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const false))
            in
            let%bind () =
              if exists then Error Error.Plan_dependency_exists else Ok ()
            in
            let%bind cycle =
              with_statement
                database
                {|
WITH RECURSIVE reachable(key) AS (
  SELECT ?1
  UNION
  SELECT d.dependency_key
  FROM plan_dependencies d
  JOIN reachable r ON d.step_key = r.key
)
SELECT 1 FROM reachable WHERE key = ?2 LIMIT 1
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 dependency in
                  let%bind () = bind_text database statement 2 step in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const true))
            in
            let%bind () =
              if cycle then Error Error.Plan_dependency_cycle else Ok ()
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO plan_dependencies (step_key, dependency_key, created_at)
VALUES (?1, ?2, ?3)
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 dependency in
                  let%bind () = bind_text database statement 3 now in
                  step_done database statement)
            in
            let%bind _ = increment_plan_revision database in
            let%map state = query_plan_state database ~schema_version:16 in
            { Mutate_plan_result.previous_phase = phase
            ; phase_path = []
            ; state
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_observation_count database =
  with_statement
    database
    "SELECT COUNT(*) FROM reconnaissance_observations"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const 0))
;;

let start_reconnaissance
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~goal_text
      ~goal_path
      ~goal_md5
      ~goal_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let path =
              match phase with
              | Sandwalk_core.Phase.Initialized ->
                Ok
                  [ Sandwalk_core.Phase.Scoping
                  ; Sandwalk_core.Phase.Reconnaissance
                  ]
              | Sandwalk_core.Phase.Scoping ->
                Ok [ Sandwalk_core.Phase.Reconnaissance ]
              | Sandwalk_core.Phase.Planning ->
                Ok [ Sandwalk_core.Phase.Reconnaissance ]
              | _ -> Error (Error.Recon_start_wrong_phase phase)
            in
            let%bind path = path in
            let%bind () =
              List.fold_result path ~init:phase ~f:(fun from into ->
                Sandwalk_core.transition ~from ~into
                |> Result.map_error ~f:(fun _ ->
                  Error.Recon_start_wrong_phase phase))
              |> Result.map ~f:ignore
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO reconnaissance (
  singleton, goal_text, goal_path, goal_md5, goal_size, started_at
) VALUES (1, ?1, ?2, ?3, ?4, ?5)
ON CONFLICT(singleton) DO UPDATE SET
  goal_text = excluded.goal_text,
  goal_path = excluded.goal_path,
  goal_md5 = excluded.goal_md5,
  goal_size = excluded.goal_size,
  started_at = excluded.started_at,
  summary_text = NULL,
  summary_path = NULL,
  summary_md5 = NULL,
  summary_size = NULL,
  finished_at = NULL
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 goal_text in
                  let%bind () = bind_text database statement 2 goal_path in
                  let%bind () = bind_text database statement 3 goal_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 4 goal_size)
                  in
                  let%bind () = bind_text database statement 5 now in
                  step_done database statement)
            in
            let%bind () =
              update_phase
                database
                ~phase:Sandwalk_core.Phase.Reconnaissance
                ~now
            in
            let%map observation_count = query_observation_count database in
            { Recon_result.previous_phase = phase
            ; phase = Sandwalk_core.Phase.Reconnaissance
            ; observation_count
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let add_reconnaissance_observation
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~observation_text
      ~observation_path
      ~observation_md5
      ~observation_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if
                Sandwalk_core.Phase.equal
                  phase
                  Sandwalk_core.Phase.Reconnaissance
              then Ok ()
              else Error (Error.Recon_not_active phase)
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO reconnaissance_observations (
  observation_text, observation_path, observation_md5,
  observation_size, created_at
) VALUES (?1, ?2, ?3, ?4, ?5)
|}
                ~f:(fun statement ->
                  let%bind () =
                    bind_text database statement 1 observation_text
                  in
                  let%bind () =
                    bind_text database statement 2 observation_path
                  in
                  let%bind () =
                    bind_text database statement 3 observation_md5
                  in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 4 observation_size)
                  in
                  let%bind () = bind_text database statement 5 now in
                  step_done database statement)
            in
            let%map observation_count = query_observation_count database in
            { Recon_result.previous_phase = phase; phase; observation_count }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let finish_reconnaissance
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~summary_text
      ~summary_path
      ~summary_md5
      ~summary_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if
                Sandwalk_core.Phase.equal
                  phase
                  Sandwalk_core.Phase.Reconnaissance
              then Ok ()
              else Error (Error.Recon_not_active phase)
            in
            let%bind _ =
              Sandwalk_core.transition
                ~from:phase
                ~into:Sandwalk_core.Phase.Planning
              |> Result.map_error ~f:(fun _ -> Error.Recon_not_active phase)
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE reconnaissance
SET summary_text = ?1, summary_path = ?2, summary_md5 = ?3,
    summary_size = ?4, finished_at = ?5
WHERE singleton = 1
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 summary_text in
                  let%bind () = bind_text database statement 2 summary_path in
                  let%bind () = bind_text database statement 3 summary_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 4 summary_size)
                  in
                  let%bind () = bind_text database statement 5 now in
                  step_done database statement)
            in
            let%bind observation_count = query_observation_count database in
            let%map () =
              update_phase database ~phase:Sandwalk_core.Phase.Planning ~now
            in
            { Recon_result.previous_phase = phase
            ; phase = Sandwalk_core.Phase.Planning
            ; observation_count
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let add_plan_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind current_phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind phase_path =
              Sandwalk_core.Planning.transition_path current_phase
              |> Result.map_error ~f:(function
                | Sandwalk_core.Planning.Error.Wrong_phase phase ->
                  Error.Plan_mutation_wrong_phase phase)
            in
            let key =
              Sandwalk_core.Plan_step.key step
              |> Sandwalk_core.Plan_step.Key.to_string
            in
            let%bind exists = plan_step_exists database key in
            let%bind () =
              if exists
              then Error (Error.Duplicate_plan_step key)
              else Ok ()
            in
            let%bind position = next_plan_position database in
            let%bind () = insert_plan_step database ~step ~position ~now in
            let%bind () = insert_step_execution database ~step in
            let phase =
              List.last phase_path |> Option.value ~default:current_phase
            in
            let%bind () =
              List.fold_result
                phase_path
                ~init:current_phase
                ~f:(fun from into ->
                  Sandwalk_core.transition ~from ~into
                  |> Result.map_error ~f:(fun _ ->
                    Error.Plan_mutation_wrong_phase from))
              |> Result.map ~f:ignore
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase current_phase
              then Ok ()
              else update_phase database ~phase ~now
            in
            let%bind revision = increment_plan_revision database in
            let%bind steps = query_plan_steps database in
            let%bind objective = query_plan_objective database in
            let%map dependencies = query_plan_dependencies database in
            { Add_plan_step_result.previous_schema_version
            ; previous_phase = current_phase
            ; phase_path
            ; phase
            ; revision
            ; steps
            ; objective
            ; dependencies
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let extend_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step
      ~dependencies
      ~reason
      ~reason_path
      ~reason_md5
      ~reason_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Plan_extension_wrong_phase phase)
            in
            let key =
              Sandwalk_core.Plan_step.key step
              |> Sandwalk_core.Plan_step.Key.to_string
            in
            let dependency_keys =
              List.map dependencies ~f:Sandwalk_core.Plan_step.Key.to_string
            in
            let%bind exists = plan_step_exists database key in
            let%bind () =
              if exists
              then Error (Error.Duplicate_plan_step key)
              else if List.exists dependency_keys ~f:(String.equal key)
              then Error Error.Plan_dependency_self
              else if
                Set.length (String.Set.of_list dependency_keys)
                <> List.length dependency_keys
              then Error Error.Plan_dependency_exists
              else Ok ()
            in
            let%bind () =
              List.fold_result dependency_keys ~init:() ~f:(fun () dependency ->
                let%bind exists = plan_step_exists database dependency in
                if exists
                then Ok ()
                else Error (Error.Plan_step_not_found dependency))
            in
            let%bind position = next_plan_position database in
            let%bind () = insert_plan_step database ~step ~position ~now in
            let%bind () = insert_step_execution database ~step in
            let%bind () =
              List.fold_result dependency_keys ~init:() ~f:(fun () dependency ->
                with_statement
                  database
                  {|
INSERT INTO plan_dependencies (step_key, dependency_key, created_at)
VALUES (?1, ?2, ?3)
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 key in
                    let%bind () = bind_text database statement 2 dependency in
                    let%bind () = bind_text database statement 3 now in
                    step_done database statement))
            in
            let%bind revision = increment_plan_revision database in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO plan_extensions (
  revision, step_key, reason_text, reason_path, reason_md5,
  reason_size, created_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
|}
                ~f:(fun statement ->
                  let%bind () =
                    check database (Sqlite3.bind_int statement 1 revision)
                  in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () =
                    bind_text
                      database
                      statement
                      3
                      (Sandwalk_core.Plan_extension_reason.text reason)
                  in
                  let%bind () = bind_text database statement 4 reason_path in
                  let%bind () = bind_text database statement 5 reason_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 6 reason_size)
                  in
                  let%bind () = bind_text database statement 7 now in
                  step_done database statement)
            in
            let%bind () = mark_plan_validated database ~revision ~now in
            let%bind () = mark_plan_sealed database ~revision ~now in
            let%map state = query_plan_state database ~schema_version:19 in
            { Extend_plan_result.previous_schema_version
            ; state
            ; position
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let validate_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Planning
              then Ok ()
              else Error (Error.Plan_validation_wrong_phase phase)
            in
            let%bind steps = query_plan_steps database in
            let%bind () =
              if List.is_empty steps then Error Error.Empty_plan else Ok ()
            in
            let%bind revision, validated_revision =
              query_plan_validation database
            in
            let already_validated =
              Option.value_map
                validated_revision
                ~default:false
                ~f:(Int.equal revision)
            in
            let%bind () =
              if already_validated
              then Ok ()
              else mark_plan_validated database ~revision ~now
            in
            let%bind objective = query_plan_objective database in
            let%map dependencies = query_plan_dependencies database in
              { Validate_plan_result.previous_schema_version
              ; phase
              ; revision
              ; already_validated
              ; steps
              ; objective
              ; dependencies
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let seal_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind previous_phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind steps = query_plan_steps database in
            let%bind () =
              if List.is_empty steps then Error Error.Empty_plan else Ok ()
            in
            let%bind revision, validated_revision, sealed_revision =
              query_plan_seal database
            in
            let already_sealed =
              Sandwalk_core.Phase.equal previous_phase Researching
              && Option.value_map
                   sealed_revision
                   ~default:false
                   ~f:(Int.equal revision)
            in
            let%bind () =
              if already_sealed
              then Ok ()
              else if not (Sandwalk_core.Phase.equal previous_phase Planning)
              then Error (Error.Plan_seal_wrong_phase previous_phase)
              else (
                match validated_revision with
                | None -> Error Error.Plan_not_validated
                | Some validated_revision
                  when not (Int.equal validated_revision revision) ->
                  Error
                    (Error.Plan_validation_stale
                       { validated_revision; current_revision = revision })
                | Some _ -> Ok ())
            in
            let phase = Sandwalk_core.Phase.Researching in
            let%bind () =
              if already_sealed
              then Ok ()
              else (
                let%bind _ =
                  Sandwalk_core.transition
                    ~from:previous_phase
                    ~into:phase
                  |> Result.map_error ~f:(fun _ ->
                    Error.Plan_seal_wrong_phase previous_phase)
                in
                let%bind () = mark_plan_sealed database ~revision ~now in
                update_phase database ~phase ~now)
            in
            let%bind objective = query_plan_objective database in
            let%map dependencies = query_plan_dependencies database in
              { Seal_plan_result.previous_schema_version
              ; previous_phase
              ; phase
              ; revision
              ; already_sealed
              ; steps
              ; objective
              ; dependencies
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_step_execution database ~step_key =
  with_statement
    database
    {|
SELECT state, active_claim_id, attempt
FROM step_executions
WHERE step_key = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let key = Sandwalk_core.Plan_step.Key.to_string step_key in
      let%bind () = bind_text database statement 1 key in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let state_text = Sqlite3.column_text statement 0 in
        let%map state =
          Sandwalk_core.Step_state.of_string state_text
          |> Result.of_option ~error:(Error.Invalid_step_state state_text)
        in
        let active_claim_id =
          if Sqlite3.column_is_null statement 1
          then None
          else Some (Sqlite3.column_text statement 1)
        in
        state, active_claim_id, Sqlite3.column_int statement 2
      | Sqlite3.Rc.DONE -> Error (Error.Plan_step_not_found key)
      | return_code ->
        check database return_code
        |> Result.map
             ~f:
               (Fn.const
                  (Sandwalk_core.Step_state.Pending, None, 0)))
;;

let claim_id_exists database claim_id =
  with_statement
    database
    "SELECT 1 FROM claims WHERE claim_id = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok true
      | Sqlite3.Rc.DONE -> Ok false
      | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

(* Schema 5-20 lease columns remain inert for migration compatibility.  Schema
   21 never reads them or uses time to decide claim validity. *)
let insert_claim database ~claim_id ~step_key ~attempt ~now =
  with_statement
    database
    {|
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds, lease_duration_seconds
)
VALUES (?1, ?2, ?3, ?4, 'unbounded', 9223372036854775807, 86400)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      let%bind () = check database (Sqlite3.bind_int statement 3 attempt) in
      let%bind () = bind_text database statement 4 now in
      step_done database statement)
;;

let activate_claim database ~claim_id ~step_key ~attempt =
  with_statement
    database
    {|
UPDATE step_executions
SET state = 'claimed',
    active_claim_id = ?1,
    lease_expires_unix_seconds = 9223372036854775807,
    attempt = ?2
WHERE step_key = ?3
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () = check database (Sqlite3.bind_int statement 2 attempt) in
      let%bind () =
        bind_text
          database
          statement
          3
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      step_done database statement)
;;

let claim_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step_key
      ~claim_id
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if
                Sandwalk_core.Phase.equal
                  phase
                  Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Step_claim_wrong_phase phase)
            in
            let%bind state, _active_claim_id, previous_attempt =
              query_step_execution database ~step_key
            in
            let%bind decision =
              Sandwalk_core.Claim_decision.decide ~state
              |> Result.map_error ~f:(function
                | Sandwalk_core.Claim_decision.Error.Active_claim ->
                  Error.Step_already_claimed
                | Sandwalk_core.Claim_decision.Error.Step_completed ->
                  Error.Step_completed
                    (Sandwalk_core.Plan_step.Key.to_string step_key))
            in
            let step_text =
              Sandwalk_core.Plan_step.Key.to_string step_key
            in
            let%bind incomplete_dependencies =
              with_statement
                database
                {|
SELECT COUNT(*)
FROM plan_dependencies d
JOIN step_executions e ON e.step_key = d.dependency_key
WHERE d.step_key = ?1 AND e.state <> 'completed'
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step_text in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code |> Result.map ~f:(Fn.const 1))
            in
            let%bind () =
              if incomplete_dependencies = 0
              then Ok ()
              else Error (Error.Step_dependencies_incomplete step_text)
            in
            let%bind collision = claim_id_exists database claim_id in
            let%bind () =
              if collision then Error Error.Claim_id_collision else Ok ()
            in
            let attempt = previous_attempt + 1 in
            let%bind () =
              insert_claim database ~claim_id ~step_key ~attempt ~now
            in
            let%bind () =
              activate_claim database ~claim_id ~step_key ~attempt
            in
            Ok
              { Claim_step_result.previous_schema_version
              ; claim_id
              ; step_key
              ; attempt
              ; previous_state = decision.previous_state
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_active_claims database =
  let claims = ref [] in
  let open Result.Let_syntax in
  let%map () =
    check
      database
      (Sqlite3.exec
         database
         {|
SELECT c.claim_id, c.step_key, c.attempt
FROM step_executions e
JOIN claims c ON c.claim_id = e.active_claim_id
WHERE e.state = 'claimed'
ORDER BY c.step_key
|}
         ~cb:(fun row _headers ->
           match row with
           | [| Some claim_id; Some step_key; Some attempt |] ->
             let claim_id =
               Sandwalk_core.Claim_id.of_string claim_id |> Option.value_exn
             in
             let step_key =
               match Sandwalk_core.Plan_step.Key.of_string step_key with
               | Ok step_key -> step_key
               | Error _ -> failwith "Invalid persisted plan step key"
             in
             claims :=
               { Active_claim.claim_id = claim_id
               ; step_key
               ; attempt = Int.of_string attempt
               }
               :: !claims
           | _ -> failwith "Invalid persisted active claim row"))
  in
  List.rev !claims
;;

let read_active_claims ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 5
          then Ok []
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_active_claims database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let migrate_workspace
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, _ = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%map () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            previous_schema_version
          in
          (match outcome with
           | Ok previous_schema_version ->
             let%map () = execute database "COMMIT" in
             previous_schema_version
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_step_title database step_key =
  with_statement
    database
    "SELECT title FROM plan_steps WHERE step_key = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text statement 0)
      | Sqlite3.Rc.DONE ->
        Error
          (Error.Plan_step_not_found
             (Sandwalk_core.Plan_step.Key.to_string step_key))
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const ""))
;;

let query_first_unfetched_hit database step_key =
  with_statement
    database
    {|
SELECT h.hit_ref, h.title, h.url, h.snippet
FROM search_hits h
JOIN search_queries q ON q.query_id = h.query_id
LEFT JOIN snapshots s ON s.hit_ref = h.hit_ref
WHERE q.step_key = ?1 AND s.snapshot_ref IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM candidate_rejections r
    WHERE r.step_key = ?1
      AND r.candidate_kind = 'hit'
      AND r.candidate_ref = h.hit_ref
  )
ORDER BY q.query_id DESC, h.position
LIMIT 1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let%map hit_id =
          Sandwalk_core.Hit_id.of_string (Sqlite3.column_text statement 0)
          |> Result.of_option
               ~error:(Error.Database_error "Invalid persisted hit reference")
        in
        Some
          ( hit_id
          , Sqlite3.column_text statement 1
          , Sqlite3.column_text statement 2
          , Sqlite3.column_text statement 3 )
      | Sqlite3.Rc.DONE -> Ok None
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const None))
;;

let query_first_snapshot database step_key =
  with_statement
    database
    {|
SELECT s.snapshot_ref, s.artifact_path
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
WHERE COALESCE(s.step_key, p.step_key) = ?1
  AND NOT EXISTS (
    SELECT 1 FROM candidate_rejections r
    WHERE r.step_key = ?1
      AND r.candidate_kind = 'snapshot'
      AND r.candidate_ref = s.snapshot_ref
  )
ORDER BY s.rowid
LIMIT 1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let%map snapshot_id =
          Sandwalk_core.Snapshot_id.of_string
            (Sqlite3.column_text statement 0)
          |> Result.of_option
               ~error:
                 (Error.Database_error "Invalid persisted snapshot reference")
        in
        Some (snapshot_id, Sqlite3.column_text statement 1)
      | Sqlite3.Rc.DONE -> Ok None
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const None))
;;

let query_first_excerpt ?finding database step_key =
  let sql =
    match finding with
    | None ->
      {|
SELECT e.excerpt_ref, e.artifact_path
FROM excerpts e
WHERE e.step_key = ?1
  AND NOT EXISTS (
    SELECT 1 FROM candidate_rejections r
    WHERE r.step_key = ?1
      AND r.candidate_kind = 'excerpt'
      AND r.candidate_ref = e.excerpt_ref
  )
ORDER BY e.rowid
LIMIT 1
|}
    | Some _ ->
      {|
SELECT e.excerpt_ref, e.artifact_path
FROM excerpts e
WHERE e.step_key = ?1
  AND NOT EXISTS (
    SELECT 1 FROM candidate_rejections r
    WHERE r.step_key = ?1
      AND r.candidate_kind = 'excerpt'
      AND r.candidate_ref = e.excerpt_ref
  )
  AND NOT EXISTS (
    SELECT 1
    FROM finding_evidence fe
    WHERE fe.step_key = ?1
      AND fe.finding_key = ?2
      AND fe.revision = ?3
      AND fe.excerpt_ref = e.excerpt_ref
  )
ORDER BY e.rowid
LIMIT 1
|}
  in
  with_statement database sql ~f:(fun statement ->
    let open Result.Let_syntax in
    let%bind () =
      bind_text
        database
        statement
        1
        (Sandwalk_core.Plan_step.Key.to_string step_key)
    in
    let%bind () =
      match finding with
      | None -> Ok ()
      | Some (finding_key, revision) ->
        let%bind () =
          bind_text
            database
            statement
            2
            (Sandwalk_core.Finding_key.to_string finding_key)
        in
        check database (Sqlite3.bind_int statement 3 revision)
    in
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW ->
      let%map excerpt_id =
        Sandwalk_core.Excerpt_id.of_string (Sqlite3.column_text statement 0)
        |> Result.of_option
             ~error:
               (Error.Database_error "Invalid persisted excerpt reference")
      in
      Some (excerpt_id, Sqlite3.column_text statement 1)
    | Sqlite3.Rc.DONE -> Ok None
    | return_code ->
      check database return_code |> Result.map ~f:(Fn.const None))
;;

let query_finding_progress database step_key =
  let findings = ref [] in
  let open Result.Let_syntax in
  let%map () =
    with_statement
      database
      {|
SELECT f.finding_key, f.state, f.current_revision,
       EXISTS (
         SELECT 1
         FROM finding_evidence fe
         WHERE fe.step_key = f.step_key
           AND fe.finding_key = f.finding_key
           AND fe.revision = f.current_revision
           AND fe.relation <> 'context'
       ),
       COALESCE(r.verdict, '')
FROM findings f
LEFT JOIN finding_reviews r
  ON r.step_key = f.step_key
 AND r.finding_key = f.finding_key
 AND r.revision = f.current_revision
WHERE f.step_key = ?1
ORDER BY f.finding_key
|}
      ~f:(fun statement ->
        let%bind () =
          bind_text
            database
            statement
            1
            (Sandwalk_core.Plan_step.Key.to_string step_key)
        in
        let rec collect () =
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW ->
            let%bind finding_key =
              Sandwalk_core.Finding_key.of_string
                (Sqlite3.column_text statement 0)
              |> Result.of_option
                   ~error:
                     (Error.Database_error
                        "Invalid persisted finding key")
            in
            findings :=
              ( finding_key
              , Sqlite3.column_text statement 1
              , Sqlite3.column_int statement 2
              , Sqlite3.column_int statement 3 <> 0
              , Sqlite3.column_text statement 4 )
              :: !findings;
            collect ()
          | Sqlite3.Rc.DONE -> Ok ()
          | return_code -> check database return_code
        in
        collect ())
  in
  List.rev !findings
;;

let query_research_guidance database =
  let open Result.Let_syntax in
  let%bind active_claims = query_active_claims database in
  match active_claims with
  | [] -> Ok None
  | active :: _ ->
    let claim_id = Active_claim.claim_id active in
    let step_key = Active_claim.step_key active in
    let source_guidance () =
      let%bind snapshot = query_first_snapshot database step_key in
      match snapshot with
      | Some (snapshot_id, artifact_path) ->
        Ok
          (Research_guidance.Create_excerpt
             { claim_id
             ; step_key
             ; snapshot_id
             ; document_path = Filename.concat artifact_path "document.md"
             })
      | None ->
        let%bind hit = query_first_unfetched_hit database step_key in
        (match hit with
         | Some (hit_id, title, url, snippet) ->
           Ok
             (Research_guidance.Fetch
                { claim_id; step_key; hit_id; title; url; snippet })
         | None ->
           let%map query = query_step_title database step_key in
           Research_guidance.Search { claim_id; step_key; query })
    in
    let evidence_guidance finding_key revision =
      let%bind excerpt =
        query_first_excerpt
          ~finding:(finding_key, revision)
          database
          step_key
      in
      match excerpt with
      | Some (excerpt_id, excerpt_path) ->
        Ok
          (Research_guidance.Attach_evidence
             { claim_id
             ; step_key
             ; finding_key
             ; excerpt_id
             ; excerpt_path
             })
      | None -> source_guidance ()
    in
    let%bind findings = query_finding_progress database step_key in
    let actionable =
      List.find findings ~f:(fun (_, state, _, _, verdict) ->
        not
          (String.equal state "reviewed"
           && (String.equal verdict "supported"
               || String.equal verdict "partially-supported")))
    in
    (match actionable with
     | Some (finding_key, "draft", revision, false, _) ->
       evidence_guidance finding_key revision
     | Some (finding_key, "draft", _, true, _) ->
       Ok
         (Research_guidance.Seal_finding
            { claim_id; step_key; finding_key })
     | Some (finding_key, "sealed", _, _, _) ->
       Ok
         (Research_guidance.Review_finding
            { claim_id; step_key; finding_key })
     | Some (finding_key, "reviewed", revision, _, verdict)
       when String.equal verdict "unsupported"
            || String.equal verdict "contradicted" ->
       evidence_guidance finding_key revision
     | Some (_, state, _, _, _) ->
       Error (Error.Invalid_step_state state)
     | None ->
       if not (List.is_empty findings)
       then
         Ok
           (Research_guidance.Complete_step
              { claim_id; step_key })
       else (
         let%bind excerpt = query_first_excerpt database step_key in
         match excerpt with
         | Some (excerpt_id, excerpt_path) ->
           Ok
             (Research_guidance.Create_finding
                { claim_id
                ; step_key
                ; excerpt_id
                ; excerpt_path
                })
         | None -> source_guidance ()))
    |> Result.map ~f:Option.some
;;

let read_research_guidance
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < current_schema_version
          then
            Error
              (Error.Database_error
                 "Research guidance requires a migrated workspace.")
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_research_guidance database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let read_current_report_blocks
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 13
          then Ok []
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else (
            let blocks = ref [] in
            let%map () =
              check
                database
                (Sqlite3.exec
                   database
                   {|
SELECT b.report_revision, b.ordinal, b.block_md5, b.block_text
FROM report_blocks b
JOIN reports r ON r.revision = b.report_revision
WHERE r.current = 1
ORDER BY b.ordinal
|}
                   ~cb:(fun row _headers ->
                     match row with
                     | [| Some revision; Some ordinal; Some md5; Some text |] ->
                       blocks :=
                         { Current_report_block.report_revision =
                             Int.of_string revision
                         ; ordinal = Int.of_string ordinal
                         ; block_md5 = md5
                         ; block_text = text
                         }
                         :: !blocks
                     | _ -> failwith "Invalid persisted report block"))
            in
            List.rev !blocks)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let read_step_context
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~step_key
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 16
          then Error (Error.Plan_step_not_found step_key)
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else
            with_statement
              database
              {|
SELECT COALESCE(o.objective_text, p.title), p.title
FROM plan_steps p
LEFT JOIN plan_objective o ON o.singleton = 1
WHERE p.step_key = ?1
|}
              ~f:(fun statement ->
                let%bind () = bind_text database statement 1 step_key in
                match Sqlite3.step statement with
                | Sqlite3.Rc.ROW ->
                  let%bind step_key =
                    Sandwalk_core.Plan_step.Key.of_string step_key
                    |> Result.map_error ~f:(fun _ ->
                      Error.Plan_step_not_found step_key)
                  in
                  Ok
                    { Step_context.objective =
                        Sqlite3.column_text statement 0
                    ; step_key
                    ; step_title = Sqlite3.column_text statement 1
                    }
                | Sqlite3.Rc.DONE ->
                  Error (Error.Plan_step_not_found step_key)
                | return_code ->
                  check database return_code
                  |> Result.map ~f:(fun () -> assert false))
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let read_finding_review_context
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~finding_reference
      ()
  =
  match String.lsplit2 finding_reference ~on:'/' with
  | None -> Error (Error.Finding_not_found finding_reference)
  | Some (step, finding) ->
    (try
       let database = Sqlite3.db_open ~mode:`READONLY database_path in
       Exn.protect
         ~f:(fun () ->
           try
             Sqlite3.busy_timeout database busy_timeout_ms;
             let open Result.Let_syntax in
             let%bind schema_version = query_schema_version database in
             if schema_version < 11
             then Error (Error.Finding_not_found finding_reference)
             else if schema_version > current_schema_version
             then Error (Error.Unsupported_schema_version schema_version)
             else (
               let%bind statement =
                 with_statement
                   database
                   {|
SELECT fr.claim_text
FROM findings f
JOIN finding_revisions fr
  ON fr.step_key = f.step_key
 AND fr.finding_key = f.finding_key
 AND fr.revision = f.current_revision
WHERE f.step_key = ?1 AND f.finding_key = ?2
|}
                   ~f:(fun query ->
                     let%bind () = bind_text database query 1 step in
                     let%bind () = bind_text database query 2 finding in
                     match Sqlite3.step query with
                     | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text query 0)
                     | Sqlite3.Rc.DONE ->
                       Error (Error.Finding_not_found finding_reference)
                     | return_code ->
                       check database return_code
                       |> Result.map ~f:(fun () -> assert false))
               in
               let evidence = ref [] in
               let%map () =
                 with_statement
                   database
                   {|
SELECT fe.excerpt_ref, e.artifact_path, fe.relation
FROM findings f
JOIN finding_evidence fe
  ON fe.step_key = f.step_key
 AND fe.finding_key = f.finding_key
 AND fe.revision = f.current_revision
JOIN excerpts e ON e.excerpt_ref = fe.excerpt_ref
WHERE f.step_key = ?1 AND f.finding_key = ?2
ORDER BY fe.excerpt_ref, fe.relation
|}
                   ~f:(fun query ->
                     let%bind () = bind_text database query 1 step in
                     let%bind () = bind_text database query 2 finding in
                     let rec loop () =
                       match Sqlite3.step query with
                       | Sqlite3.Rc.ROW ->
                         evidence :=
                           ( Sqlite3.column_text query 0
                           , Sqlite3.column_text query 1
                           , Sqlite3.column_text query 2 )
                           :: !evidence;
                         loop ()
                       | Sqlite3.Rc.DONE -> Ok ()
                       | return_code -> check database return_code
                     in
                     loop ())
               in
               { Finding_review_context.statement
               ; evidence = List.rev !evidence
               })
           with
           | exn -> Error (Error.Database_error (Exn.to_string exn)))
         ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
     with
     | exn -> Error (Error.Database_error (Exn.to_string exn)))
;;

let reject_candidate
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~kind
      ~reference
      ~reason_text
      ~reason_path
      ~reason_md5
      ~reason_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Search_wrong_phase phase)
            in
            let claim_reference =
              Sandwalk_core.Claim_id.to_string claim_id
            in
            let%bind step_key =
              with_statement
                database
                {|
SELECT c.step_key
FROM claims c
JOIN step_executions e ON e.step_key = c.step_key
WHERE c.claim_id = ?1
  AND c.ended_at IS NULL
  AND e.state = 'claimed'
  AND e.active_claim_id = c.claim_id
|}
                ~f:(fun statement ->
                  let%bind () =
                    bind_text database statement 1 claim_reference
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Sandwalk_core.Plan_step.Key.of_string
                      (Sqlite3.column_text statement 0)
                    |> Result.map_error ~f:(fun _ ->
                      Error.Invalid_step_state
                        (Sqlite3.column_text statement 0))
                  | Sqlite3.Rc.DONE -> Error Error.Claim_not_active
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let kind_text = Sandwalk_core.Candidate_kind.to_string kind in
            let ownership_query =
              match kind with
              | Sandwalk_core.Candidate_kind.Hit ->
                {|
SELECT q.step_key
FROM search_hits h
JOIN search_queries q ON q.query_id = h.query_id
WHERE h.hit_ref = ?1
|}
              | Snapshot ->
                {|
SELECT COALESCE(s.step_key, p.step_key)
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
WHERE s.snapshot_ref = ?1
|}
              | Excerpt ->
                "SELECT step_key FROM excerpts WHERE excerpt_ref = ?1"
            in
            let%bind owner =
              with_statement database ownership_query ~f:(fun statement ->
                let%bind () = bind_text database statement 1 reference in
                match Sqlite3.step statement with
                | Sqlite3.Rc.ROW ->
                  if Sqlite3.column_is_null statement 0
                  then Error (Error.Candidate_not_owned_by_claim reference)
                  else Ok (Sqlite3.column_text statement 0)
                | Sqlite3.Rc.DONE ->
                  Error (Error.Candidate_not_found reference)
                | return_code ->
                  check database return_code
                  |> Result.map ~f:(fun () -> assert false))
            in
            let%bind () =
              if String.equal owner step
              then Ok ()
              else Error (Error.Candidate_not_owned_by_claim reference)
            in
            let%bind existing =
              with_statement
                database
                {|
SELECT 1 FROM candidate_rejections
WHERE step_key = ?1 AND candidate_kind = ?2 AND candidate_ref = ?3
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 kind_text in
                  let%bind () = bind_text database statement 3 reference in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const false))
            in
            let%bind () =
              if existing
              then Ok ()
              else
                with_statement
                  database
                  {|
INSERT INTO candidate_rejections (
  step_key, candidate_kind, candidate_ref, claim_id,
  reason_text, reason_path, reason_md5, reason_size, rejected_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 step in
                    let%bind () = bind_text database statement 2 kind_text in
                    let%bind () = bind_text database statement 3 reference in
                    let%bind () =
                      bind_text
                        database
                        statement
                        4
                        (Sandwalk_core.Claim_id.to_string claim_id)
                    in
                    let%bind () =
                      bind_text database statement 5 reason_text
                    in
                    let%bind () =
                      bind_text database statement 6 reason_path
                    in
                    let%bind () = bind_text database statement 7 reason_md5 in
                    let%bind () =
                      check
                        database
                        (Sqlite3.bind_int statement 8 reason_size)
                    in
                    let%bind () = bind_text database statement 9 now in
                    step_done database statement)
            in
            Ok
              { Candidate_rejection_result.step_key
              ; kind
              ; reference
              ; rejected = not existing
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let repair_finding
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~step_key
      ~finding_key
      ~reason_text
      ~reason_path
      ~reason_md5
      ~reason_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if
                Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
                || Sandwalk_core.Phase.equal
                     phase
                     Sandwalk_core.Phase.Evidence_review
              then Ok ()
              else Error (Error.Finding_repair_wrong_phase phase)
            in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let finding = Sandwalk_core.Finding_key.to_string finding_key in
            let reference = step ^ "/" ^ finding in
            let%bind state, _, _ = query_step_execution database ~step_key in
            let%bind () =
              if
                Sandwalk_core.Step_state.equal
                  state
                  Sandwalk_core.Step_state.Completed
              then Ok ()
              else
                Error (Error.Finding_repair_requires_completed_step step)
            in
            let%bind completed_dependents =
              with_statement
                database
                {|
WITH RECURSIVE dependents(step_key) AS (
  SELECT step_key FROM plan_dependencies WHERE dependency_key = ?1
  UNION
  SELECT p.step_key
  FROM plan_dependencies p
  JOIN dependents d ON p.dependency_key = d.step_key
)
SELECT COUNT(*)
FROM dependents d
JOIN step_executions e ON e.step_key = d.step_key
WHERE e.state = 'completed'
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const 0))
            in
            let%bind () =
              if completed_dependents = 0
              then Ok ()
              else
                Error
                  (Error.Finding_repair_has_completed_dependents reference)
            in
            let%bind previous_revision =
              with_statement
                database
                {|
SELECT current_revision FROM findings
WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Finding_not_found reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let repair_revision = previous_revision + 1 in
            let%bind suspended_claims =
              with_statement
                database
                "SELECT COUNT(*) FROM step_executions WHERE state = 'claimed'"
                ~f:(fun statement ->
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const 0))
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE claims
SET ended_at = ?1, end_reason = 'suspended'
WHERE claim_id IN (
  SELECT active_claim_id FROM step_executions
  WHERE state = 'claimed' AND active_claim_id IS NOT NULL
)
  AND ended_at IS NULL
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 now in
                  step_done database statement)
            in
            let%bind () =
              execute
                database
                {|
UPDATE step_executions
SET state = 'suspended', active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE state = 'claimed'
|}
            in
            let%bind rejected_excerpts =
              with_statement
                database
                {|
SELECT COUNT(*) FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 previous_revision)
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const 0))
            in
            let%bind () =
              with_statement
                database
                {|
INSERT OR IGNORE INTO candidate_rejections (
  step_key, candidate_kind, candidate_ref, claim_id,
  reason_text, reason_path, reason_md5, reason_size, rejected_at
)
SELECT ?1, 'excerpt', excerpt_ref, NULL, ?4, ?5, ?6, ?7, ?8
FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 previous_revision)
                  in
                  let%bind () = bind_text database statement 4 reason_text in
                  let%bind () = bind_text database statement 5 reason_path in
                  let%bind () = bind_text database statement 6 reason_md5 in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 7 reason_size)
                  in
                  let%bind () = bind_text database statement 8 now in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO finding_revisions (
  step_key, finding_key, revision, claim_text, claim_md5, claim_size, created_at
)
SELECT step_key, finding_key, ?3, claim_text, claim_md5, claim_size, ?4
FROM finding_revisions
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?5
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 repair_revision)
                  in
                  let%bind () = bind_text database statement 4 now in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 5 previous_revision)
                  in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE findings
SET current_revision = ?3, state = 'draft', updated_at = ?4
WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 repair_revision)
                  in
                  let%bind () = bind_text database statement 4 now in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE step_executions
SET state = 'suspended', active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE step_key = ?1
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO finding_repairs (
  step_key, finding_key, previous_revision, repair_revision,
  reason_text, reason_path, reason_md5, reason_size, created_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 finding in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 previous_revision)
                  in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 4 repair_revision)
                  in
                  let%bind () = bind_text database statement 5 reason_text in
                  let%bind () = bind_text database statement 6 reason_path in
                  let%bind () = bind_text database statement 7 reason_md5 in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 8 reason_size)
                  in
                  let%bind () = bind_text database statement 9 now in
                  step_done database statement)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else update_phase database ~phase:Sandwalk_core.Phase.Researching ~now
            in
            Ok
              { Repair_finding_result.step_key
              ; finding_key
              ; revision = repair_revision
              ; suspended_claims
              ; rejected_excerpts
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_resume_entities database ~schema_version =
  let entities = ref [] in
  let query kind sql =
    check
      database
      (Sqlite3.exec database sql ~cb:(fun row _headers ->
         match row with
         | [| Some reference; step; Some detail |] ->
           entities := { Resume_entity.kind; reference; step; detail } :: !entities
         | _ -> failwith "Invalid persisted resume entity."))
  in
  let open Result.Let_syntax in
  let%bind () =
    if schema_version < 7
    then Ok ()
    else
      query
        "hit"
        {|
SELECT h.hit_ref, q.step_key, h.url
FROM search_hits h
JOIN search_queries q ON q.query_id = h.query_id
ORDER BY h.rowid DESC
LIMIT 10
|}
  in
  let%bind () =
    if schema_version < 8
    then Ok ()
    else if schema_version >= 20
    then
      query
        "snapshot"
        {|
SELECT s.snapshot_ref, COALESCE(s.step_key, p.step_key), s.artifact_path
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
ORDER BY s.rowid DESC
LIMIT 10
|}
    else
      query
        "snapshot"
        {|
SELECT snapshot_ref, step_key, artifact_path
FROM snapshots
ORDER BY rowid DESC
LIMIT 10
|}
  in
  let%bind () =
    if schema_version < 9
    then Ok ()
    else
      query
        "excerpt"
        {|
SELECT excerpt_ref, step_key, artifact_path
FROM excerpts
ORDER BY rowid DESC
LIMIT 10
|}
  in
  let%map () =
    if schema_version < 10
    then Ok ()
    else
      query
        "finding"
        {|
SELECT step_key || '/' || finding_key, step_key,
       'revision ' || current_revision || ', ' || state
FROM findings
ORDER BY rowid DESC
LIMIT 10
|}
  in
  List.rev !entities
;;

let read_resume_entities ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_resume_entities database ~schema_version
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_claim_for_checkpoint database claim_id =
  with_statement
    database
    {|
SELECT c.step_key, e.state, e.active_claim_id
FROM claims c
JOIN step_executions e ON e.step_key = c.step_key
WHERE c.claim_id = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let step_key_text = Sqlite3.column_text statement 0 in
        let%bind step_key =
          Sandwalk_core.Plan_step.Key.of_string step_key_text
          |> Result.map_error ~f:(fun _ ->
            Error.Database_error "Invalid persisted checkpoint step key")
        in
        let state_text = Sqlite3.column_text statement 1 in
        let%map state =
          Sandwalk_core.Step_state.of_string state_text
          |> Result.of_option ~error:(Error.Invalid_step_state state_text)
        in
        let active_claim_id =
          if Sqlite3.column_is_null statement 2
          then None
          else Some (Sqlite3.column_text statement 2)
        in
        step_key, state, active_claim_id
      | Sqlite3.Rc.DONE -> Error Error.Claim_not_found
      | return_code ->
        check database return_code
        |> Result.map ~f:(fun () -> assert false))
;;

let active_claim_step database claim_id =
  let open Result.Let_syntax in
  let%bind step_key, state, active_claim_id =
    query_claim_for_checkpoint database claim_id
  in
  let claim_text = Sandwalk_core.Claim_id.to_string claim_id in
  let%map () =
    if
      Sandwalk_core.Step_state.equal state Sandwalk_core.Step_state.Claimed
      && Option.value_map
           active_claim_id
           ~default:false
           ~f:(String.equal claim_text)
    then Ok ()
    else Error Error.Claim_not_active
  in
  step_key
;;

let next_checkpoint_number database ~step_key =
  with_statement
    database
    {|
SELECT COALESCE(MAX(checkpoint_number), 0) + 1
FROM checkpoints
WHERE step_key = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
      | Sqlite3.Rc.DONE -> Ok 1
      | return_code -> check database return_code |> Result.map ~f:(Fn.const 1))
;;

let insert_checkpoint
      database
      ~step_key
      ~claim_id
      ~checkpoint_number
      ~checkpoint
      ~summary_path
      ~summary_md5
      ~summary_size
      ~next_path
      ~next_md5
      ~next_size
      ~now
  =
  with_statement
    database
    {|
INSERT INTO checkpoints (
  step_key, claim_id, checkpoint_number, created_at, summary, next,
  summary_path, summary_md5, summary_size, next_path, next_md5, next_size
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let bind_int index value =
        check database (Sqlite3.bind_int statement index value)
      in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Plan_step.Key.to_string step_key)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Claim_id.to_string claim_id)
      in
      let%bind () = bind_int 3 checkpoint_number in
      let%bind () = bind_text database statement 4 now in
      let%bind () =
        bind_text database statement 5 (Sandwalk_core.Checkpoint.summary checkpoint)
      in
      let%bind () =
        bind_text database statement 6 (Sandwalk_core.Checkpoint.next checkpoint)
      in
      let%bind () = bind_text database statement 7 summary_path in
      let%bind () = bind_text database statement 8 summary_md5 in
      let%bind () = bind_int 9 summary_size in
      let%bind () = bind_text database statement 10 next_path in
      let%bind () = bind_text database statement 11 next_md5 in
      let%bind () = bind_int 12 next_size in
      step_done database statement)
;;

let save_checkpoint
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~checkpoint
      ~summary_path
      ~summary_md5
      ~summary_size
      ~next_path
      ~next_md5
      ~next_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, _phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind step_key, state, active_claim_id =
              query_claim_for_checkpoint database claim_id
            in
            let claim_text = Sandwalk_core.Claim_id.to_string claim_id in
            let%bind () =
              if
                Sandwalk_core.Step_state.equal
                  state
                  Sandwalk_core.Step_state.Claimed
                && Option.value_map
                     active_claim_id
                     ~default:false
                     ~f:(String.equal claim_text)
              then Ok ()
              else Error Error.Claim_not_active
            in
            let%bind checkpoint_number =
              next_checkpoint_number database ~step_key
            in
            let%map () =
              insert_checkpoint
                database
                ~step_key
                ~claim_id
                ~checkpoint_number
                ~checkpoint
                ~summary_path
                ~summary_md5
                ~summary_size
                ~next_path
                ~next_md5
                ~next_size
                ~now
            in
            { Save_checkpoint_result.previous_schema_version
            ; step_key
            ; checkpoint_number
            }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             Error error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_latest_checkpoint database =
  with_statement
    database
    {|
SELECT step_key, summary, next, created_at
FROM checkpoints
ORDER BY checkpoint_id DESC
LIMIT 1
|}
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let step_key =
          Sqlite3.column_text statement 0
          |> Sandwalk_core.Plan_step.Key.of_string
          |> Result.ok
          |> Option.value_exn
        in
        Ok
          (Some
             { Latest_checkpoint.step_key
             ; summary = Sqlite3.column_text statement 1
             ; next = Sqlite3.column_text statement 2
             ; created_at = Sqlite3.column_text statement 3
             })
      | Sqlite3.Rc.DONE -> Ok None
      | return_code -> check database return_code |> Result.map ~f:(Fn.const None))
;;

let read_latest_checkpoint ?(busy_timeout_ms = 5_000) ~database_path () =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          if schema_version < 6
          then Ok None
          else if schema_version > current_schema_version
          then Error (Error.Unsupported_schema_version schema_version)
          else query_latest_checkpoint database
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let insert_search_query
      database
      ~query
      ~phase
      ~claim_id
      ~step_key
      ~adapter
      ~now
  =
  with_statement
    database
    {|
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let bind_optional_text index value =
        check
          database
          (Sqlite3.bind
             statement
             index
             (Sqlite3.Data.opt_text value))
      in
      let%bind () = bind_text database statement 1 query in
      let%bind () =
        bind_text database statement 2 (Sandwalk_core.Phase.to_string phase)
      in
      let%bind () =
        bind_optional_text
          3
          (Option.map claim_id ~f:Sandwalk_core.Claim_id.to_string)
      in
      let%bind () =
        bind_optional_text
          4
          (Option.map step_key ~f:Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () = bind_text database statement 5 adapter in
      let%bind () = bind_text database statement 6 now in
      let%map () = step_done database statement in
      Sqlite3.last_insert_rowid database)
;;

let hit_id_exists database hit_id =
  with_statement database "SELECT 1 FROM search_hits WHERE hit_ref = ?1" ~f:(fun statement ->
    let open Result.Let_syntax in
    let%bind () =
      bind_text database statement 1 (Sandwalk_core.Hit_id.to_string hit_id)
    in
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok true
    | Sqlite3.Rc.DONE -> Ok false
    | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let insert_search_hit database ~query_id ~position (hit_id, url, title, snippet) =
  with_statement
    database
    {|
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text database statement 1 (Sandwalk_core.Hit_id.to_string hit_id)
      in
      let%bind () = check database (Sqlite3.bind_int64 statement 2 query_id) in
      let%bind () = check database (Sqlite3.bind_int statement 3 position) in
      let%bind () = bind_text database statement 4 url in
      let%bind () = bind_text database statement 5 title in
      let%bind () = bind_text database statement 6 snippet in
      let%map () = step_done database statement in
      { Stored_hit.hit_id = hit_id; position; url; title; snippet })
;;

let record_search
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~query
      ~adapter
      ~hits
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind step_key =
              match phase, claim_id with
              | Sandwalk_core.Phase.Reconnaissance, None -> Ok None
              | Sandwalk_core.Phase.Researching, None ->
                Error Error.Search_requires_claim
              | Sandwalk_core.Phase.Researching, Some claim_id ->
                active_claim_step database claim_id |> Result.map ~f:Option.some
              | Sandwalk_core.Phase.Reconnaissance, Some _ ->
                Error Error.Claim_not_active
              | _ -> Error (Error.Search_wrong_phase phase)
            in
            let%bind () =
              List.fold_result hits ~init:() ~f:(fun () (hit_id, _, _, _) ->
                let%bind exists = hit_id_exists database hit_id in
                if exists then Error Error.Hit_id_collision else Ok ())
            in
            let%bind query_id =
              insert_search_query
                database
                ~query
                ~phase
                ~claim_id
                ~step_key
                ~adapter
                ~now
            in
            let%bind stored_hits =
              List.mapi hits ~f:(fun index hit ->
                insert_search_hit database ~query_id ~position:(index + 1) hit)
              |> Result.all
            in
            Ok
              { Record_search_result.previous_schema_version
              ; hits = stored_hits
              ; step_key
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let hit_for_fetch
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~hit_id
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind slug_text, _ = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          with_statement
            database
            "SELECT url FROM search_hits WHERE hit_ref = ?1"
            ~f:(fun statement ->
              let reference = Sandwalk_core.Hit_id.to_string hit_id in
              let%bind () = bind_text database statement 1 reference in
              match Sqlite3.step statement with
              | Sqlite3.Rc.ROW ->
                Ok { Hit_for_fetch.hit_id; url = Sqlite3.column_text statement 0 }
              | Sqlite3.Rc.DONE -> Error (Error.Hit_not_found reference)
              | return_code ->
                check database return_code
                |> Result.map ~f:(fun () -> assert false))
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let snapshot_id_exists database snapshot_id =
  with_statement
    database
    "SELECT 1 FROM snapshots WHERE snapshot_ref = ?1"
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Snapshot_id.to_string snapshot_id)
      in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> Ok true
      | Sqlite3.Rc.DONE -> Ok false
      | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let query_hit_step database hit_id =
  with_statement
    database
    {|
SELECT q.step_key
FROM search_hits AS h
JOIN search_queries AS q ON q.query_id = h.query_id
WHERE h.hit_ref = ?1
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let reference = Sandwalk_core.Hit_id.to_string hit_id in
      let%bind () = bind_text database statement 1 reference in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        (match Sqlite3.column statement 0 with
         | Sqlite3.Data.NULL -> Ok None
         | Sqlite3.Data.TEXT value ->
           Sandwalk_core.Plan_step.Key.of_string value
           |> Result.ok
           |> Result.of_option
                ~error:(Error.Database_error "Invalid persisted search-hit step.")
           |> Result.map ~f:Option.some
         | _ -> Error (Error.Database_error "Invalid persisted search-hit step."))
      | Sqlite3.Rc.DONE -> Error (Error.Hit_not_found reference)
      | return_code ->
        check database return_code |> Result.map ~f:(Fn.const None))
;;

let insert_snapshot
      database
      ~hit_id
      ~claim_id
      ~step_key
      ~snapshot_id
      ~artifact_path
      ~final_url
      ~input_sha256
      ~markdown_sha256
      ~manifest_json
      ~now
  =
  with_statement
    database
    {|
INSERT INTO snapshots (
  snapshot_ref, hit_ref, claim_id, step_key, artifact_path, final_url,
  input_sha256, markdown_sha256, manifest_json, retrieved_at
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let optional_text index value =
        check database (Sqlite3.bind statement index (Sqlite3.Data.opt_text value))
      in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Snapshot_id.to_string snapshot_id)
      in
      let%bind () =
        bind_text database statement 2 (Sandwalk_core.Hit_id.to_string hit_id)
      in
      let%bind () =
        optional_text 3 (Option.map claim_id ~f:Sandwalk_core.Claim_id.to_string)
      in
      let%bind () =
        optional_text
          4
          (Option.map step_key ~f:Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () = bind_text database statement 5 artifact_path in
      let%bind () = bind_text database statement 6 final_url in
      let%bind () = bind_text database statement 7 input_sha256 in
      let%bind () = bind_text database statement 8 markdown_sha256 in
      let%bind () = bind_text database statement 9 manifest_json in
      let%bind () = bind_text database statement 10 now in
      step_done database statement)
;;

let record_snapshot
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~hit_id
      ~snapshot_id
      ~artifact_path
      ~final_url
      ~input_sha256
      ~markdown_sha256
      ~manifest_json
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind step_key =
              match phase, claim_id with
              | Sandwalk_core.Phase.Reconnaissance, None -> Ok None
              | Sandwalk_core.Phase.Researching, None ->
                Error Error.Fetch_requires_claim
              | Sandwalk_core.Phase.Researching, Some claim_id ->
                active_claim_step database claim_id |> Result.map ~f:Option.some
              | Sandwalk_core.Phase.Reconnaissance, Some _ ->
                Error Error.Claim_not_active
              | _ -> Error (Error.Fetch_wrong_phase phase)
            in
            let reference = Sandwalk_core.Hit_id.to_string hit_id in
            let%bind hit_step_key = query_hit_step database hit_id in
            let%bind () =
              match step_key, hit_step_key with
              | Some active_step, Some owner
                when not
                       (String.equal
                          (Sandwalk_core.Plan_step.Key.to_string active_step)
                          (Sandwalk_core.Plan_step.Key.to_string owner)) ->
                Error (Error.Hit_not_owned_by_claim reference)
              | Some _, None ->
                Error (Error.Hit_not_owned_by_claim reference)
              | None, _ | Some _, Some _ -> Ok ()
            in
            let%bind collision = snapshot_id_exists database snapshot_id in
            let%bind () =
              if collision then Error Error.Snapshot_id_collision else Ok ()
            in
            let%bind () =
              insert_snapshot
                database
                ~hit_id
                ~claim_id
                ~step_key
                ~snapshot_id
                ~artifact_path
                ~final_url
                ~input_sha256
                ~markdown_sha256
                ~manifest_json
                ~now
            in
            Ok
              { Record_snapshot_result.previous_schema_version
              ; step_key
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let promote_snapshot
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~snapshot_id
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Snapshot_promotion_wrong_phase phase)
            in
            let%bind step_key = active_claim_step database claim_id in
            let claim_text = Sandwalk_core.Claim_id.to_string claim_id in
            let reference = Sandwalk_core.Snapshot_id.to_string snapshot_id in
            let parse_step statement column =
              match Sqlite3.column statement column with
              | Sqlite3.Data.NULL -> Ok None
              | Sqlite3.Data.TEXT value ->
                Sandwalk_core.Plan_step.Key.of_string value
                |> Result.map ~f:Option.some
                |> Result.map_error ~f:(fun _ ->
                  Error.Database_error "Invalid persisted snapshot owner.")
              | _ ->
                Error
                  (Error.Database_error "Invalid persisted snapshot owner.")
            in
            let%bind base_owner, promoted_owner =
              with_statement
                database
                {|
SELECT s.step_key, p.step_key
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
WHERE s.snapshot_ref = ?1
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 reference in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    let%bind base_owner = parse_step statement 0 in
                    let%map promoted_owner = parse_step statement 1 in
                    base_owner, promoted_owner
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Snapshot_not_found reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const (None, None)))
            in
            let same_step owner =
              String.equal
                (Sandwalk_core.Plan_step.Key.to_string owner)
                (Sandwalk_core.Plan_step.Key.to_string step_key)
            in
            let%bind promoted =
              match base_owner, promoted_owner with
              | Some owner, _ | None, Some owner ->
                if same_step owner
                then Ok false
                else Error (Error.Snapshot_promotion_conflict reference)
              | None, None ->
                with_statement
                  database
                  {|
INSERT INTO snapshot_promotions (
  snapshot_ref, step_key, claim_id, promoted_at
) VALUES (?1, ?2, ?3, ?4)
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 reference in
                    let%bind () =
                      bind_text
                        database
                        statement
                        2
                        (Sandwalk_core.Plan_step.Key.to_string step_key)
                    in
                    let%bind () = bind_text database statement 3 claim_text in
                    let%bind () = bind_text database statement 4 now in
                    let%map () = step_done database statement in
                    true)
            in
            Ok
              { Promote_snapshot_result.previous_schema_version
              ; step_key
              ; promoted
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let snapshot_for_excerpt
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~snapshot_id
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          let%bind () =
            if schema_version < 8
            then
              Error
                (Error.Snapshot_not_found
                   (Sandwalk_core.Snapshot_id.to_string snapshot_id))
            else if schema_version > current_schema_version
            then Error (Error.Unsupported_schema_version schema_version)
            else Ok ()
          in
          let%bind slug_text, _ = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let query =
            if schema_version >= 20
            then
              {|
SELECT s.artifact_path, s.markdown_sha256,
       COALESCE(s.step_key, p.step_key)
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
WHERE s.snapshot_ref = ?1
|}
            else
              {|
SELECT artifact_path, markdown_sha256, step_key
FROM snapshots
WHERE snapshot_ref = ?1
|}
          in
          with_statement
            database
            query
            ~f:(fun statement ->
              let reference = Sandwalk_core.Snapshot_id.to_string snapshot_id in
              let%bind () = bind_text database statement 1 reference in
              match Sqlite3.step statement with
              | Sqlite3.Rc.ROW ->
                let%bind step_key =
                  match Sqlite3.column statement 2 with
                  | Sqlite3.Data.NULL -> Ok None
                  | Sqlite3.Data.TEXT value ->
                    Sandwalk_core.Plan_step.Key.of_string value
                    |> Result.ok
                    |> Result.of_option
                         ~error:
                           (Error.Database_error
                              "Invalid persisted snapshot step.")
                    |> Result.map ~f:Option.some
                  | _ ->
                    Error
                      (Error.Database_error "Invalid persisted snapshot step.")
                in
                Ok
                  { Snapshot_for_excerpt.snapshot_id
                  ; artifact_path = Sqlite3.column_text statement 0
                  ; markdown_sha256 = Sqlite3.column_text statement 1
                  ; step_key
                  }
              | Sqlite3.Rc.DONE -> Error (Error.Snapshot_not_found reference)
              | return_code ->
                check database return_code
                |> Result.map ~f:(fun () -> assert false))
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_existing_excerpt database ~snapshot_id ~byte_start ~byte_end =
  with_statement
    database
    {|
SELECT excerpt_ref
FROM excerpts
WHERE snapshot_ref = ?1 AND byte_start = ?2 AND byte_end = ?3
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Snapshot_id.to_string snapshot_id)
      in
      let%bind () = check database (Sqlite3.bind_int statement 2 byte_start) in
      let%bind () = check database (Sqlite3.bind_int statement 3 byte_end) in
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        Sqlite3.column_text statement 0
        |> Sandwalk_core.Excerpt_id.of_string
        |> Result.of_option
             ~error:(Error.Database_error "Invalid persisted excerpt reference.")
        |> Result.map ~f:Option.some
      | Sqlite3.Rc.DONE -> Ok None
      | return_code -> check database return_code |> Result.map ~f:(Fn.const None))
;;

let excerpt_id_exists database excerpt_id =
  with_statement database "SELECT 1 FROM excerpts WHERE excerpt_ref = ?1" ~f:(fun statement ->
    let open Result.Let_syntax in
    let%bind () =
      bind_text
        database
        statement
        1
        (Sandwalk_core.Excerpt_id.to_string excerpt_id)
    in
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Ok true
    | Sqlite3.Rc.DONE -> Ok false
    | return_code -> check database return_code |> Result.map ~f:(Fn.const false))
;;

let insert_excerpt
      database
      ~excerpt_id
      ~snapshot_id
      ~claim_id
      ~step_key
      ~artifact_path
      ~markdown_sha256
      ~line_start
      ~line_end
      ~byte_start
      ~byte_end
      ~excerpt_md5
      ~excerpt_size
      ~now
  =
  with_statement
    database
    {|
INSERT INTO excerpts (
  excerpt_ref, snapshot_ref, claim_id, step_key, artifact_path,
  markdown_sha256, line_start, line_end, byte_start, byte_end,
  excerpt_md5, excerpt_size, created_at
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
|}
    ~f:(fun statement ->
      let open Result.Let_syntax in
      let optional_text index value =
        check database (Sqlite3.bind statement index (Sqlite3.Data.opt_text value))
      in
      let%bind () =
        bind_text
          database
          statement
          1
          (Sandwalk_core.Excerpt_id.to_string excerpt_id)
      in
      let%bind () =
        bind_text
          database
          statement
          2
          (Sandwalk_core.Snapshot_id.to_string snapshot_id)
      in
      let%bind () =
        optional_text 3 (Option.map claim_id ~f:Sandwalk_core.Claim_id.to_string)
      in
      let%bind () =
        optional_text
          4
          (Option.map step_key ~f:Sandwalk_core.Plan_step.Key.to_string)
      in
      let%bind () = bind_text database statement 5 artifact_path in
      let%bind () = bind_text database statement 6 markdown_sha256 in
      let%bind () = check database (Sqlite3.bind_int statement 7 line_start) in
      let%bind () = check database (Sqlite3.bind_int statement 8 line_end) in
      let%bind () = check database (Sqlite3.bind_int statement 9 byte_start) in
      let%bind () = check database (Sqlite3.bind_int statement 10 byte_end) in
      let%bind () = bind_text database statement 11 excerpt_md5 in
      let%bind () = check database (Sqlite3.bind_int statement 12 excerpt_size) in
      let%bind () = bind_text database statement 13 now in
      step_done database statement)
;;

let record_excerpt
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~snapshot_id
      ~excerpt_id
      ~artifact_path
      ~markdown_sha256
      ~line_start
      ~line_end
      ~byte_start
      ~byte_end
      ~excerpt_md5
      ~excerpt_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind step_key =
              match phase, claim_id with
              | Sandwalk_core.Phase.Reconnaissance, None -> Ok None
              | Sandwalk_core.Phase.Researching, None ->
                Error Error.Excerpt_requires_claim
              | Sandwalk_core.Phase.Researching, Some claim_id ->
                active_claim_step database claim_id |> Result.map ~f:Option.some
              | Sandwalk_core.Phase.Reconnaissance, Some _ ->
                Error Error.Claim_not_active
              | _ -> Error (Error.Excerpt_wrong_phase phase)
            in
            let snapshot_reference =
              Sandwalk_core.Snapshot_id.to_string snapshot_id
            in
            let%bind snapshot_step =
              with_statement
                database
                {|
SELECT COALESCE(s.step_key, p.step_key)
FROM snapshots s
LEFT JOIN snapshot_promotions p ON p.snapshot_ref = s.snapshot_ref
WHERE s.snapshot_ref = ?1
|}
                ~f:(fun statement ->
                  let%bind () =
                    bind_text database statement 1 snapshot_reference
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Snapshot_not_found snapshot_reference)
                  | Sqlite3.Rc.ROW ->
                    (match Sqlite3.column statement 0 with
                     | Sqlite3.Data.NULL -> Ok None
                     | Sqlite3.Data.TEXT value ->
                       Sandwalk_core.Plan_step.Key.of_string value
                       |> Result.ok
                       |> Result.of_option
                            ~error:
                              (Error.Database_error
                                 "Invalid persisted snapshot step.")
                       |> Result.map ~f:Option.some
                     | _ ->
                       Error
                         (Error.Database_error
                            "Invalid persisted snapshot step."))
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const None))
            in
            let%bind () =
              match step_key, snapshot_step with
              | Some active, Some owner
                when not
                       (String.equal
                          (Sandwalk_core.Plan_step.Key.to_string active)
                          (Sandwalk_core.Plan_step.Key.to_string owner)) ->
                Error (Error.Snapshot_not_owned_by_claim snapshot_reference)
              | Some _, None ->
                Error (Error.Snapshot_not_owned_by_claim snapshot_reference)
              | None, _ | Some _, Some _ -> Ok ()
            in
            let%bind existing =
              query_existing_excerpt
                database
                ~snapshot_id
                ~byte_start
                ~byte_end
            in
            let%bind stored_id, created =
              match existing with
              | Some existing_id -> Ok (existing_id, false)
              | None ->
                let%bind collision = excerpt_id_exists database excerpt_id in
                let%bind () =
                  if collision then Error Error.Excerpt_id_collision else Ok ()
                in
                let%map () =
                  insert_excerpt
                    database
                    ~excerpt_id
                    ~snapshot_id
                    ~claim_id
                    ~step_key
                    ~artifact_path
                    ~markdown_sha256
                    ~line_start
                    ~line_end
                    ~byte_start
                    ~byte_end
                    ~excerpt_md5
                    ~excerpt_size
                    ~now
                in
                excerpt_id, true
            in
            Ok
              { Record_excerpt_result.excerpt_id = stored_id
              ; created
              ; step_key
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let create_finding
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~step_key
      ~finding_key
      ~claim_text
      ~claim_md5
      ~claim_size
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind previous_schema_version = query_schema_version database in
            let%bind () =
              migrate database ~from_version:previous_schema_version ~now
            in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Finding_wrong_phase phase)
            in
            let%bind claimed_step = active_claim_step database claim_id in
            let%bind () =
              if
                String.equal
                  (Sandwalk_core.Plan_step.Key.to_string claimed_step)
                  (Sandwalk_core.Plan_step.Key.to_string step_key)
              then Ok ()
              else Error Error.Finding_step_mismatch
            in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let key = Sandwalk_core.Finding_key.to_string finding_key in
            let reference = step ^ "/" ^ key in
            let%bind exists =
              with_statement
                database
                {|
SELECT 1 FROM findings WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const false))
            in
            let%bind () =
              if exists then Error (Error.Finding_exists reference) else Ok ()
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO findings (
  step_key, finding_key, current_revision, state, created_at, updated_at
) VALUES (?1, ?2, 1, 'draft', ?3, ?3)
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () = bind_text database statement 3 now in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO finding_revisions (
  step_key, finding_key, revision, claim_text, claim_md5, claim_size, created_at
) VALUES (?1, ?2, 1, ?3, ?4, ?5, ?6)
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () = bind_text database statement 3 claim_text in
                  let%bind () = bind_text database statement 4 claim_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 5 claim_size)
                  in
                  let%bind () = bind_text database statement 6 now in
                  step_done database statement)
            in
            Ok
              { Create_finding_result.step_key
              ; finding_key
              ; revision = 1
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let attach_evidence
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~step_key
      ~finding_key
      ~excerpt_id
      ~relation
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Finding_wrong_phase phase)
            in
            let%bind claimed_step = active_claim_step database claim_id in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let%bind () =
              if
                String.equal
                  (Sandwalk_core.Plan_step.Key.to_string claimed_step)
                  step
              then Ok ()
              else Error Error.Finding_step_mismatch
            in
            let key = Sandwalk_core.Finding_key.to_string finding_key in
            let finding_reference = step ^ "/" ^ key in
            let%bind revision, finding_state =
              with_statement
                database
                {|
SELECT current_revision, state
FROM findings
WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok
                      ( Sqlite3.column_int statement 0
                      , Sqlite3.column_text statement 1 )
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Finding_not_found finding_reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let excerpt_reference =
              Sandwalk_core.Excerpt_id.to_string excerpt_id
            in
            let%bind excerpt_step, excerpt_hash, snapshot_hash =
              with_statement
                database
                {|
SELECT e.step_key, e.markdown_sha256, s.markdown_sha256
FROM excerpts AS e
JOIN snapshots AS s ON s.snapshot_ref = e.snapshot_ref
WHERE e.excerpt_ref = ?1
|}
                ~f:(fun statement ->
                  let%bind () =
                    bind_text database statement 1 excerpt_reference
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok
                      ( Sqlite3.column_text statement 0
                      , Sqlite3.column_text statement 1
                      , Sqlite3.column_text statement 2 )
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Excerpt_not_found excerpt_reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let%bind () =
              if String.equal excerpt_step step
              then Ok ()
              else Error Error.Finding_excerpt_step_mismatch
            in
            let%bind () =
              if String.equal excerpt_hash snapshot_hash
              then Ok ()
              else Error (Error.Excerpt_stale excerpt_reference)
            in
            let relation_text =
              Sandwalk_core.Finding_relation.to_string relation
            in
            let%bind attached_to_current =
              with_statement
                database
                {|
SELECT 1 FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
  AND excerpt_ref = ?4 AND relation = ?5
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 3 revision)
                  in
                  let%bind () =
                    bind_text database statement 4 excerpt_reference
                  in
                  let%bind () = bind_text database statement 5 relation_text in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const false))
            in
            let revised =
              not attached_to_current
              && not (String.equal finding_state "draft")
            in
            let target_revision = if revised then revision + 1 else revision in
            let%bind () =
              if revised
              then (
                let%bind () =
                  with_statement
                    database
                    {|
INSERT INTO finding_revisions (
  step_key, finding_key, revision, claim_text, claim_md5, claim_size, created_at
)
SELECT step_key, finding_key, ?3, claim_text, claim_md5, claim_size, ?4
FROM finding_revisions
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?5
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 step in
                      let%bind () = bind_text database statement 2 key in
                      let%bind () =
                        check
                          database
                          (Sqlite3.bind_int statement 3 target_revision)
                      in
                      let%bind () = bind_text database statement 4 now in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 5 revision)
                      in
                      step_done database statement)
                in
                let%bind () =
                  with_statement
                    database
                    {|
INSERT INTO finding_evidence (
  step_key, finding_key, revision, excerpt_ref, relation, attached_at
)
SELECT step_key, finding_key, ?3, excerpt_ref, relation, attached_at
FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?4
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 step in
                      let%bind () = bind_text database statement 2 key in
                      let%bind () =
                        check
                          database
                          (Sqlite3.bind_int statement 3 target_revision)
                      in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 4 revision)
                      in
                      step_done database statement)
                in
                with_statement
                  database
                  {|
UPDATE findings
SET current_revision = ?3, state = 'draft', updated_at = ?4
WHERE step_key = ?1 AND finding_key = ?2
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 step in
                    let%bind () = bind_text database statement 2 key in
                    let%bind () =
                      check
                        database
                        (Sqlite3.bind_int statement 3 target_revision)
                    in
                    let%bind () = bind_text database statement 4 now in
                    step_done database statement))
              else Ok ()
            in
            let%bind already_attached =
              with_statement
                database
                {|
SELECT 1 FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
  AND excerpt_ref = ?4 AND relation = ?5
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 3 target_revision)
                  in
                  let%bind () =
                    bind_text database statement 4 excerpt_reference
                  in
                  let%bind () = bind_text database statement 5 relation_text in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok true
                  | Sqlite3.Rc.DONE -> Ok false
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const false))
            in
            let%bind () =
              if already_attached
              then Ok ()
              else
                with_statement
                  database
                  {|
INSERT INTO finding_evidence (
  step_key, finding_key, revision, excerpt_ref, relation, attached_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 step in
                    let%bind () = bind_text database statement 2 key in
                    let%bind () =
                      check
                        database
                        (Sqlite3.bind_int statement 3 target_revision)
                    in
                    let%bind () =
                      bind_text database statement 4 excerpt_reference
                    in
                    let%bind () =
                      bind_text database statement 5 relation_text
                    in
                    let%bind () = bind_text database statement 6 now in
                    step_done database statement)
            in
            Ok
              { Attach_evidence_result.revision = target_revision
              ; attached = not already_attached
              ; revised
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let seal_finding
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~step_key
      ~finding_key
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Finding_wrong_phase phase)
            in
            let%bind claimed_step = active_claim_step database claim_id in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let%bind () =
              if
                String.equal
                  (Sandwalk_core.Plan_step.Key.to_string claimed_step)
                  step
              then Ok ()
              else Error Error.Finding_step_mismatch
            in
            let key = Sandwalk_core.Finding_key.to_string finding_key in
            let reference = step ^ "/" ^ key in
            let%bind revision, finding_state =
              with_statement
                database
                {|
SELECT current_revision, state
FROM findings
WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok
                      ( Sqlite3.column_int statement 0
                      , Sqlite3.column_text statement 1 )
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Finding_not_found reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let already_sealed = not (String.equal finding_state "draft") in
            let%bind () =
              if already_sealed
              then Ok ()
              else (
                let%bind evidence_count, claim_evidence_count =
                  with_statement
                    database
                    {|
SELECT
  COUNT(*),
  COALESCE(SUM(CASE WHEN relation <> 'context' THEN 1 ELSE 0 END), 0)
FROM finding_evidence
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 step in
                      let%bind () = bind_text database statement 2 key in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 3 revision)
                      in
                      match Sqlite3.step statement with
                      | Sqlite3.Rc.ROW ->
                        Ok
                          ( Sqlite3.column_int statement 0
                          , Sqlite3.column_int statement 1 )
                      | return_code ->
                        check database return_code
                        |> Result.map ~f:(Fn.const (0, 0)))
                in
                let%bind () =
                  if evidence_count = 0 || claim_evidence_count = 0
                  then Error (Error.Finding_has_no_evidence reference)
                  else Ok ()
                in
                let%bind () =
                  with_statement
                    database
                    {|
UPDATE findings
SET state = 'sealed', updated_at = ?3
WHERE step_key = ?1 AND finding_key = ?2
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 step in
                      let%bind () = bind_text database statement 2 key in
                      let%bind () = bind_text database statement 3 now in
                      step_done database statement)
                in
                with_statement
                  database
                  {|
UPDATE finding_revisions
SET sealed_at = ?4
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 step in
                    let%bind () = bind_text database statement 2 key in
                    let%bind () =
                      check database (Sqlite3.bind_int statement 3 revision)
                    in
                    let%bind () = bind_text database statement 4 now in
                    step_done database statement))
            in
            Ok
              { Seal_finding_result.revision
              ; already_sealed
              ; state = if already_sealed then finding_state else "sealed"
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let review_finding
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~step_key
      ~finding_key
      ~verdict
      ~summary
      ~source_quality
      ~conflicts
      ~qualifications
      ~review_json
      ~review_md5
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Finding_wrong_phase phase)
            in
            let%bind claimed_step = active_claim_step database claim_id in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let%bind () =
              if
                String.equal
                  (Sandwalk_core.Plan_step.Key.to_string claimed_step)
                  step
              then Ok ()
              else Error Error.Finding_step_mismatch
            in
            let key = Sandwalk_core.Finding_key.to_string finding_key in
            let reference = step ^ "/" ^ key in
            let%bind revision, finding_state =
              with_statement
                database
                {|
SELECT current_revision, state
FROM findings
WHERE step_key = ?1 AND finding_key = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok
                      ( Sqlite3.column_int statement 0
                      , Sqlite3.column_text statement 1 )
                  | Sqlite3.Rc.DONE ->
                    Error (Error.Finding_not_found reference)
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> assert false))
            in
            let%bind () =
              if String.equal finding_state "draft"
              then Error (Error.Finding_not_sealed reference)
              else Ok ()
            in
            let%bind existing_hash =
              with_statement
                database
                {|
SELECT review_md5
FROM finding_reviews
WHERE step_key = ?1 AND finding_key = ?2 AND revision = ?3
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () = bind_text database statement 2 key in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 3 revision)
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok (Some (Sqlite3.column_text statement 0))
                  | Sqlite3.Rc.DONE -> Ok None
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const None))
            in
            let%bind reviewed =
              match existing_hash with
              | Some hash when String.equal hash review_md5 -> Ok false
              | Some _ -> Error (Error.Finding_review_conflict reference)
              | None ->
                let%map () =
                  with_statement
                    database
                    {|
INSERT INTO finding_reviews (
  step_key, finding_key, revision, verdict, summary, source_quality,
  conflicts, qualifications, review_json, review_md5, reviewed_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 step in
                      let%bind () = bind_text database statement 2 key in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 3 revision)
                      in
                      let%bind () = bind_text database statement 4 verdict in
                      let%bind () = bind_text database statement 5 summary in
                      let%bind () =
                        bind_text database statement 6 source_quality
                      in
                      let%bind () = bind_text database statement 7 conflicts in
                      let%bind () =
                        bind_text database statement 8 qualifications
                      in
                      let%bind () =
                        bind_text database statement 9 review_json
                      in
                      let%bind () = bind_text database statement 10 review_md5 in
                      let%bind () = bind_text database statement 11 now in
                      step_done database statement)
                in
                true
            in
            let%bind () =
              if reviewed
              then
                with_statement
                  database
                  {|
UPDATE findings
SET state = 'reviewed', updated_at = ?3
WHERE step_key = ?1 AND finding_key = ?2
|}
                  ~f:(fun statement ->
                    let%bind () = bind_text database statement 1 step in
                    let%bind () = bind_text database statement 2 key in
                    let%bind () = bind_text database statement 3 now in
                    step_done database statement)
              else Ok ()
            in
            Ok
              { Review_finding_result.revision
              ; reviewed
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let complete_step
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~claim_id
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
              then Ok ()
              else Error (Error.Step_claim_wrong_phase phase)
            in
            let%bind step_key = active_claim_step database claim_id in
            let claim_reference = Sandwalk_core.Claim_id.to_string claim_id in
            let step = Sandwalk_core.Plan_step.Key.to_string step_key in
            let%bind total, reviewed, rejected =
              with_statement
                database
                {|
SELECT
  COUNT(*),
  COALESCE(SUM(CASE WHEN f.state = 'reviewed' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE
    WHEN r.verdict IN ('unsupported', 'contradicted') THEN 1 ELSE 0 END), 0)
FROM findings AS f
LEFT JOIN finding_reviews AS r
  ON r.step_key = f.step_key
 AND r.finding_key = f.finding_key
 AND r.revision = f.current_revision
WHERE f.step_key = ?1
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW ->
                    Ok
                      ( Sqlite3.column_int statement 0
                      , Sqlite3.column_int statement 1
                      , Sqlite3.column_int statement 2 )
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(fun () -> 0, 0, 0))
            in
            let%bind () =
              if total = 0
              then Error (Error.Step_has_no_findings step)
              else if reviewed <> total
              then Error (Error.Step_has_unreviewed_findings step)
              else if rejected > 0
              then Error (Error.Step_has_rejected_findings step)
              else Ok ()
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE step_executions
SET state = 'completed', active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE step_key = ?1 AND active_claim_id = ?2
|}
                ~f:(fun statement ->
                  let%bind () = bind_text database statement 1 step in
                  let%bind () =
                    bind_text database statement 2 claim_reference
                  in
                  step_done database statement)
            in
            let%bind () =
              with_statement
                database
                {|
UPDATE claims
SET ended_at = ?2, end_reason = 'completed'
WHERE claim_id = ?1 AND ended_at IS NULL
|}
                ~f:(fun statement ->
                  let%bind () =
                    bind_text database statement 1 claim_reference
                  in
                  let%bind () = bind_text database statement 2 now in
                  step_done database statement)
            in
            let%bind remaining_required =
              with_statement
                database
                {|
SELECT COUNT(*)
FROM plan_steps AS p
JOIN step_executions AS e ON e.step_key = p.step_key
WHERE p.required = 1 AND e.state <> 'completed'
|}
                ~f:(fun statement ->
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code |> Result.map ~f:(Fn.const 1))
            in
            let next_phase =
              if remaining_required = 0
              then Sandwalk_core.Phase.Evidence_review
              else Sandwalk_core.Phase.Researching
            in
            let%bind () =
              if remaining_required = 0
              then (
                let%bind _ =
                  Sandwalk_core.transition
                    ~from:Sandwalk_core.Phase.Researching
                    ~into:Sandwalk_core.Phase.Evidence_review
                  |> Result.map_error ~f:(fun _ ->
                    Error.Step_claim_wrong_phase phase)
                in
                let%bind () =
                  with_statement
                    database
                    {|
UPDATE claims
SET ended_at = ?1, end_reason = 'suspended'
WHERE claim_id IN (
  SELECT active_claim_id
  FROM step_executions
  WHERE state = 'claimed' AND active_claim_id IS NOT NULL
)
|}
                    ~f:(fun statement ->
                      let%bind () = bind_text database statement 1 now in
                      step_done database statement)
                in
                let%bind () =
                  execute
                    database
                    {|
UPDATE step_executions
SET state = 'suspended', active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE state = 'claimed'
|}
                in
                update_phase database ~phase:next_phase ~now)
              else Ok ()
            in
            Ok { Complete_step_result.step_key; phase = next_phase }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let check_draft_gate database =
  let open Result.Let_syntax in
  let%bind required_incomplete =
    with_statement
      database
      {|
SELECT COUNT(*)
FROM plan_steps AS p
JOIN step_executions AS e ON e.step_key = p.step_key
WHERE p.required = 1 AND e.state <> 'completed'
|}
      ~f:(fun statement ->
        match Sqlite3.step statement with
        | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
        | return_code ->
          check database return_code |> Result.map ~f:(Fn.const 1))
  in
  let%bind invalid_findings =
    with_statement
      database
      {|
SELECT COUNT(*)
FROM findings AS f
JOIN step_executions AS e ON e.step_key = f.step_key
LEFT JOIN finding_reviews AS r
  ON r.step_key = f.step_key
 AND r.finding_key = f.finding_key
 AND r.revision = f.current_revision
WHERE e.state = 'completed'
  AND (
    f.state <> 'reviewed'
    OR r.verdict IS NULL
    OR r.verdict IN ('unsupported', 'contradicted')
  )
|}
      ~f:(fun statement ->
        match Sqlite3.step statement with
        | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
        | return_code ->
          check database return_code |> Result.map ~f:(Fn.const 1))
  in
  let%bind invalid_evidence =
    with_statement
      database
      {|
SELECT COUNT(*)
FROM findings AS f
JOIN step_executions AS se ON se.step_key = f.step_key
WHERE se.state = 'completed'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM finding_evidence AS fe
      WHERE fe.step_key = f.step_key
        AND fe.finding_key = f.finding_key
        AND fe.revision = f.current_revision
    )
    OR EXISTS (
      SELECT 1
      FROM finding_evidence AS fe
      JOIN excerpts AS e ON e.excerpt_ref = fe.excerpt_ref
      JOIN snapshots AS s ON s.snapshot_ref = e.snapshot_ref
      WHERE fe.step_key = f.step_key
        AND fe.finding_key = f.finding_key
        AND fe.revision = f.current_revision
        AND e.markdown_sha256 <> s.markdown_sha256
    )
  )
|}
      ~f:(fun statement ->
        match Sqlite3.step statement with
        | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
        | return_code ->
          check database return_code |> Result.map ~f:(Fn.const 1))
  in
  if
    required_incomplete = 0
    && invalid_findings = 0
    && invalid_evidence = 0
  then Ok ()
  else Error Error.Draft_gate_failed
;;

let read_writer_evidence
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind schema_version = query_schema_version database in
          let%bind () =
            if schema_version > current_schema_version
            then Error (Error.Unsupported_schema_version schema_version)
            else if schema_version < 12
            then Error Error.Draft_gate_failed
            else Ok ()
          in
          let%bind slug_text, phase_text = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind phase =
            Sandwalk_core.Phase.of_string phase_text
            |> Result.of_option
                 ~error:(Error.Invalid_persisted_phase phase_text)
          in
          let%bind () =
            if
              Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Evidence_review
            then Ok ()
            else Error (Error.Draft_wrong_phase phase)
          in
          let%bind () = check_draft_gate database in
          let rows = ref [] in
          let return_code =
            Sqlite3.exec
              database
              {|
SELECT f.step_key, f.finding_key, r.verdict, fr.claim_text,
       fe.relation, e.excerpt_ref, e.artifact_path, e.excerpt_md5,
       s.snapshot_ref, s.final_url, e.line_start, e.line_end
FROM findings AS f
JOIN step_executions AS se
  ON se.step_key = f.step_key AND se.state = 'completed'
JOIN finding_revisions AS fr
  ON fr.step_key = f.step_key
 AND fr.finding_key = f.finding_key
 AND fr.revision = f.current_revision
JOIN finding_reviews AS r
  ON r.step_key = f.step_key
 AND r.finding_key = f.finding_key
 AND r.revision = f.current_revision
JOIN finding_evidence AS fe
  ON fe.step_key = f.step_key
 AND fe.finding_key = f.finding_key
 AND fe.revision = f.current_revision
JOIN excerpts AS e ON e.excerpt_ref = fe.excerpt_ref
JOIN snapshots AS s ON s.snapshot_ref = e.snapshot_ref
JOIN plan_steps AS p ON p.step_key = f.step_key
ORDER BY p.position, f.finding_key, e.line_start, e.excerpt_ref, fe.relation
|}
              ~cb:(fun row _headers ->
                match row with
                | [| Some step
                   ; Some finding
                   ; Some verdict
                   ; Some claim
                   ; Some relation
                   ; Some excerpt
                   ; Some excerpt_path
                   ; Some excerpt_md5
                   ; Some snapshot
                   ; Some source_url
                   ; Some line_start
                   ; Some line_end
                  |] ->
                  rows :=
                    { Writer_evidence.step
                    ; finding
                    ; verdict
                    ; claim
                    ; relation
                    ; excerpt
                    ; excerpt_path
                    ; excerpt_md5
                    ; snapshot
                    ; source_url
                    ; line_start = Int.of_string line_start
                    ; line_end = Int.of_string line_end
                    }
                    :: !rows
                | _ -> failwith "Invalid persisted writer evidence.")
          in
          let%map () = check database return_code in
          List.rev !rows
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let begin_drafting
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if
                Sandwalk_core.Phase.equal
                  phase
                  Sandwalk_core.Phase.Evidence_review
              then Ok ()
              else Error (Error.Draft_wrong_phase phase)
            in
            let%bind () = check_draft_gate database in
            let%bind _ =
              Sandwalk_core.transition
                ~from:phase
                ~into:Sandwalk_core.Phase.Drafting
              |> Result.map_error ~f:(fun _ -> Error.Draft_wrong_phase phase)
            in
            let%map () =
              update_phase database ~phase:Sandwalk_core.Phase.Drafting ~now
            in
            Sandwalk_core.Phase.Drafting
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let validate_report_citations_in_database database citations =
  List.fold_result citations ~init:() ~f:(fun () reference ->
    let open Result.Let_syntax in
    match String.lsplit2 reference ~on:'/' with
    | None -> Error (Error.Report_citation_invalid reference)
    | Some (step, finding) ->
      with_statement
        database
        {|
SELECT 1
FROM findings AS f
JOIN finding_reviews AS r
  ON r.step_key = f.step_key
 AND r.finding_key = f.finding_key
 AND r.revision = f.current_revision
WHERE f.step_key = ?1 AND f.finding_key = ?2
  AND f.state = 'reviewed'
  AND r.verdict IN ('supported', 'partially-supported')
|}
        ~f:(fun statement ->
          let%bind () = bind_text database statement 1 step in
          let%bind () = bind_text database statement 2 finding in
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW -> Ok ()
          | Sqlite3.Rc.DONE ->
            Error (Error.Report_citation_invalid reference)
          | return_code -> check database return_code))
;;

let validate_report_citations
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~citations
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind slug_text, phase_text = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind phase =
            Sandwalk_core.Phase.of_string phase_text
            |> Result.of_option
                 ~error:(Error.Invalid_persisted_phase phase_text)
          in
          let%bind () =
            if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Drafting
            then Ok ()
            else Error (Error.Report_wrong_phase phase)
          in
          validate_report_citations_in_database database citations
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let submit_report
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~report_path
      ~report_text
      ~report_md5
      ~report_size
      ~blocks
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Drafting
              then Ok ()
              else Error (Error.Report_wrong_phase phase)
            in
            let citations =
              List.concat_map blocks ~f:(fun (_, _, citations) -> citations)
              |> List.dedup_and_sort ~compare:String.compare
            in
            let%bind () =
              validate_report_citations_in_database database citations
            in
            let%bind revision =
              with_statement
                database
                "SELECT COALESCE(MAX(revision), 0) + 1 FROM reports"
                ~f:(fun statement ->
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code |> Result.map ~f:(Fn.const 1))
            in
            let%bind () = execute database "UPDATE reports SET current = 0" in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO reports (
  revision, report_path, report_text, report_md5, report_size, submitted_at, current
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)
|}
                ~f:(fun statement ->
                  let%bind () =
                    check database (Sqlite3.bind_int statement 1 revision)
                  in
                  let%bind () = bind_text database statement 2 report_path in
                  let%bind () = bind_text database statement 3 report_text in
                  let%bind () = bind_text database statement 4 report_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 5 report_size)
                  in
                  let%bind () = bind_text database statement 6 now in
                  step_done database statement)
            in
            let%bind () =
              List.mapi blocks ~f:(fun index (text, md5, citations) ->
                let citations_json =
                  `List
                    (List.map citations ~f:(fun citation -> `String citation))
                  |> Yojson.Safe.to_string
                in
                with_statement
                  database
                  {|
INSERT INTO report_blocks (
  report_revision, ordinal, block_text, block_md5, citations_json
) VALUES (?1, ?2, ?3, ?4, ?5)
|}
                  ~f:(fun statement ->
                    let%bind () =
                      check database (Sqlite3.bind_int statement 1 revision)
                    in
                    let%bind () =
                      check database (Sqlite3.bind_int statement 2 (index + 1))
                    in
                    let%bind () = bind_text database statement 3 text in
                    let%bind () = bind_text database statement 4 md5 in
                    let%bind () =
                      bind_text database statement 5 citations_json
                    in
                    step_done database statement))
              |> Result.all_unit
            in
            let%bind _ =
              Sandwalk_core.transition
                ~from:phase
                ~into:Sandwalk_core.Phase.Draft_review
              |> Result.map_error ~f:(fun _ -> Error.Report_wrong_phase phase)
            in
            let%bind () =
              update_phase database ~phase:Sandwalk_core.Phase.Draft_review ~now
            in
            Ok
              { Submit_report_result.revision
              ; block_count = List.length blocks
              ; phase = Sandwalk_core.Phase.Draft_review
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let review_report
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~report_revision
      ~reviews
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Draft_review
              then Ok ()
              else Error (Error.Report_review_wrong_phase phase)
            in
            let%bind current_revision =
              with_statement
                database
                "SELECT revision FROM reports WHERE current = 1"
                ~f:(fun statement ->
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | Sqlite3.Rc.DONE -> Error Error.Report_revision_stale
                  | return_code ->
                    check database return_code
                    |> Result.map ~f:(Fn.const (-1)))
            in
            let%bind () =
              if current_revision = report_revision
              then Ok ()
              else Error Error.Report_revision_stale
            in
            let%bind block_count =
              with_statement
                database
                "SELECT COUNT(*) FROM report_blocks WHERE report_revision = ?1"
                ~f:(fun statement ->
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 1 report_revision)
                  in
                  match Sqlite3.step statement with
                  | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int statement 0)
                  | return_code ->
                    check database return_code |> Result.map ~f:(Fn.const 0))
            in
            let%bind () =
              if List.length reviews = block_count
              then Ok ()
              else Error Error.Report_review_incomplete
            in
            let%bind () =
              List.fold_result
                reviews
                ~init:()
                ~f:(fun () (ordinal, block_md5, _verdict, _summary) ->
                  with_statement
                    database
                    {|
SELECT block_md5
FROM report_blocks
WHERE report_revision = ?1 AND ordinal = ?2
|}
                    ~f:(fun statement ->
                      let%bind () =
                        check
                          database
                          (Sqlite3.bind_int statement 1 report_revision)
                      in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 2 ordinal)
                      in
                      match Sqlite3.step statement with
                      | Sqlite3.Rc.ROW
                        when String.equal
                               (Sqlite3.column_text statement 0)
                               block_md5 ->
                        Ok ()
                      | Sqlite3.Rc.ROW | Sqlite3.Rc.DONE ->
                        Error (Error.Report_block_stale ordinal)
                      | return_code -> check database return_code))
            in
            let%bind () =
              List.map
                reviews
                ~f:(fun (ordinal, block_md5, verdict, summary) ->
                  with_statement
                    database
                    {|
INSERT INTO report_block_reviews (
  report_revision, ordinal, verdict, summary, block_md5, reviewed_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
|}
                    ~f:(fun statement ->
                      let%bind () =
                        check
                          database
                          (Sqlite3.bind_int statement 1 report_revision)
                      in
                      let%bind () =
                        check database (Sqlite3.bind_int statement 2 ordinal)
                      in
                      let%bind () = bind_text database statement 3 verdict in
                      let%bind () = bind_text database statement 4 summary in
                      let%bind () = bind_text database statement 5 block_md5 in
                      let%bind () = bind_text database statement 6 now in
                      step_done database statement))
              |> Result.all_unit
            in
            let accepted =
              not
                (List.exists reviews ~f:(fun (_, _, verdict, _) ->
                   String.equal verdict "unsupported"
                   || String.equal verdict "contradicted"))
            in
            let next_phase =
              if accepted
              then Sandwalk_core.Phase.Finalizing
              else Sandwalk_core.Phase.Drafting
            in
            let%bind _ =
              Sandwalk_core.transition ~from:phase ~into:next_phase
              |> Result.map_error ~f:(fun _ ->
                Error.Report_review_wrong_phase phase)
            in
            let%bind () = update_phase database ~phase:next_phase ~now in
            Ok
              { Review_report_result.revision = report_revision
              ; accepted
              ; phase = next_phase
              }
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let query_final_report database =
  with_statement
    database
    {|
SELECT r.revision, r.report_path, r.report_text, r.report_md5,
       (SELECT COUNT(*) FROM report_blocks b
        WHERE b.report_revision = r.revision),
       (SELECT COUNT(*)
        FROM report_block_reviews br
        JOIN report_blocks b
          ON b.report_revision = br.report_revision
         AND b.ordinal = br.ordinal
        WHERE br.report_revision = r.revision
          AND br.block_md5 = b.block_md5
          AND br.verdict IN ('supported', 'partially-supported'))
FROM reports r
WHERE r.current = 1
|}
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        let block_count = Sqlite3.column_int statement 4 in
        let accepted_count = Sqlite3.column_int statement 5 in
        if block_count > 0 && block_count = accepted_count
        then
          Ok
            ( Sqlite3.column_int statement 0
            , Sqlite3.column_text statement 1
            , Sqlite3.column_text statement 2
            , Sqlite3.column_text statement 3 )
        else Error Error.Finalize_gate_failed
      | Sqlite3.Rc.DONE -> Error Error.Finalize_gate_failed
      | return_code ->
        check database return_code
        |> Result.map ~f:(fun () -> assert false))
;;

let query_report_citations database report_revision =
  let citations = ref [] in
  let statement =
    Sqlite3.prepare
      database
      "SELECT citations_json FROM report_blocks WHERE report_revision = ?1 ORDER BY ordinal"
  in
  Exn.protect
    ~f:(fun () ->
      let open Result.Let_syntax in
      let%bind () =
        check database (Sqlite3.bind_int statement 1 report_revision)
      in
      let rec loop () =
        match Sqlite3.step statement with
        | Sqlite3.Rc.ROW ->
          let values =
            Sqlite3.column_text statement 0 |> Yojson.Safe.from_string
          in
          (match values with
           | `List values ->
             List.iter values ~f:(function
               | `String reference -> citations := reference :: !citations
               | _ -> failwith "Invalid persisted report citation.")
           | _ -> failwith "Invalid persisted report citations.");
          loop ()
        | Sqlite3.Rc.DONE ->
          Ok
            (List.dedup_and_sort !citations ~compare:String.compare)
        | return_code ->
          check database return_code |> Result.map ~f:(fun () -> [])
      in
      loop ())
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
;;

let query_finding_sources database reference =
  match String.lsplit2 reference ~on:'/' with
  | None -> Error Error.Finalize_gate_failed
  | Some (step, finding) ->
    let sources = ref [] in
    with_statement
      database
      {|
SELECT DISTINCT s.final_url
FROM findings f
JOIN finding_evidence fe
  ON fe.step_key = f.step_key
 AND fe.finding_key = f.finding_key
 AND fe.revision = f.current_revision
JOIN excerpts e ON e.excerpt_ref = fe.excerpt_ref
JOIN snapshots s ON s.snapshot_ref = e.snapshot_ref
WHERE f.step_key = ?1 AND f.finding_key = ?2 AND f.state = 'reviewed'
ORDER BY s.final_url
|}
      ~f:(fun statement ->
        let open Result.Let_syntax in
        let%bind () = bind_text database statement 1 step in
        let%bind () = bind_text database statement 2 finding in
        let rec loop () =
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW ->
            sources := Sqlite3.column_text statement 0 :: !sources;
            loop ()
          | Sqlite3.Rc.DONE ->
            if List.is_empty !sources
            then Error Error.Finalize_gate_failed
            else Ok (reference, List.rev !sources)
          | return_code ->
            check database return_code
            |> Result.map ~f:(fun () -> reference, [])
        in
        loop ())
;;

let read_finalization_state
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind slug_text, phase_text = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind phase =
            Sandwalk_core.Phase.of_string phase_text
            |> Result.of_option
                 ~error:(Error.Invalid_persisted_phase phase_text)
          in
          let%bind () =
            if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Finalizing
            then Ok ()
            else Error (Error.Finalize_wrong_phase phase)
          in
          let%bind report_revision, report_path, report_text, report_md5 =
            query_final_report database
          in
          let%bind citations =
            query_report_citations database report_revision
          in
          let%map sources_by_finding =
            List.map citations ~f:(query_finding_sources database)
            |> Result.all
          in
          { Finalization_state.report_revision
          ; report_path
          ; report_text
          ; report_md5
          ; sources_by_finding
          }
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let finalize_workspace
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~report_revision
      ~final_report_md5
      ~sources_md5
      ~source_count
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "PRAGMA foreign_keys = ON" in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, phase_text = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind phase =
              Sandwalk_core.Phase.of_string phase_text
              |> Result.of_option
                   ~error:(Error.Invalid_persisted_phase phase_text)
            in
            let%bind () =
              if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Finalizing
              then Ok ()
              else Error (Error.Finalize_wrong_phase phase)
            in
            let%bind current_revision, _, _, _ = query_final_report database in
            let%bind () =
              if current_revision = report_revision
              then Ok ()
              else Error Error.Finalize_gate_failed
            in
            let%bind () =
              with_statement
                database
                {|
INSERT INTO finalizations (
  singleton, report_revision, final_report_md5, sources_md5,
  source_count, completed_at
) VALUES (1, ?1, ?2, ?3, ?4, ?5)
|}
                ~f:(fun statement ->
                  let%bind () =
                    check
                      database
                      (Sqlite3.bind_int statement 1 report_revision)
                  in
                  let%bind () =
                    bind_text database statement 2 final_report_md5
                  in
                  let%bind () = bind_text database statement 3 sources_md5 in
                  let%bind () =
                    check database (Sqlite3.bind_int statement 4 source_count)
                  in
                  let%bind () = bind_text database statement 5 now in
                  step_done database statement)
            in
            let%bind _ =
              Sandwalk_core.transition
                ~from:phase
                ~into:Sandwalk_core.Phase.Completed
              |> Result.map_error ~f:(fun _ ->
                Error.Finalize_wrong_phase phase)
            in
            let%map () =
              update_phase database ~phase:Sandwalk_core.Phase.Completed ~now
            in
            Sandwalk_core.Phase.Completed
          in
          (match outcome with
           | Ok result ->
             let%map () = execute database "COMMIT" in
             result
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let ensure_no_active_claims database =
  with_statement
    database
    "SELECT COUNT(*) FROM step_executions WHERE state = 'claimed'"
    ~f:(fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
        if Sqlite3.column_int statement 0 = 0
        then Ok ()
        else Error Error.Gc_active_claims
      | return_code -> check database return_code)
;;

let read_raw_gc_candidates
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind slug_text, _ = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind () = ensure_no_active_claims database in
          let paths = ref [] in
          let%map () =
            check
              database
              (Sqlite3.exec
                 database
                 "SELECT artifact_path FROM snapshots ORDER BY snapshot_ref"
                 ~cb:(fun row _ ->
                   match row with
                   | [| Some path |] -> paths := path :: !paths
                   | _ -> failwith "Invalid persisted snapshot path."))
          in
          List.rev !paths
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let record_raw_gc_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~plan_path
      ~plan_json
      ~plan_md5
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind schema_version = query_schema_version database in
            let%bind () = migrate database ~from_version:schema_version ~now in
            let%bind slug_text, _ = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind () = ensure_no_active_claims database in
            with_statement
              database
              {|
INSERT INTO raw_gc_plan (
  singleton, plan_path, plan_json, plan_md5, created_at, applied_at
) VALUES (1, ?1, ?2, ?3, ?4, NULL)
ON CONFLICT(singleton) DO UPDATE SET
  plan_path = excluded.plan_path,
  plan_json = excluded.plan_json,
  plan_md5 = excluded.plan_md5,
  created_at = excluded.created_at,
  applied_at = NULL
|}
              ~f:(fun statement ->
                let%bind () = bind_text database statement 1 plan_path in
                let%bind () = bind_text database statement 2 plan_json in
                let%bind () = bind_text database statement 3 plan_md5 in
                let%bind () = bind_text database statement 4 now in
                step_done database statement)
          in
          (match outcome with
           | Ok () -> execute database "COMMIT"
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let decode_raw_gc_plan ~plan_path ~plan_json ~plan_md5 =
  try
    match Yojson.Safe.from_string plan_json with
    | `Assoc fields ->
      (match
         List.Assoc.find fields "protocol" ~equal:String.equal,
         List.Assoc.find fields "artifacts" ~equal:String.equal
       with
       | Some (`String "sandwalk.gc-raw-plan.v1"), Some (`List values) ->
         values
         |> List.map ~f:(function
           | `String path -> Some path
           | _ -> None)
         |> Option.all
         |> Result.of_option ~error:Error.Gc_plan_stale
         |> Result.map ~f:(fun artifact_paths ->
           { Raw_gc_plan.plan_path
           ; plan_json
           ; plan_md5
           ; artifact_paths
           })
       | _ -> Error Error.Gc_plan_stale)
    | _ -> Error Error.Gc_plan_stale
  with
  | _ -> Error Error.Gc_plan_stale
;;

let read_raw_gc_plan
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`READONLY database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind slug_text, _ = query_workspace database in
          let expected = Sandwalk_core.Slug.to_string expected_slug in
          let%bind () =
            if String.equal expected slug_text
            then Ok ()
            else
              Error
                (Error.Workspace_slug_mismatch
                   { expected; actual = slug_text })
          in
          let%bind () = ensure_no_active_claims database in
          with_statement
            database
            {|
SELECT plan_path, plan_json, plan_md5
FROM raw_gc_plan
WHERE singleton = 1 AND applied_at IS NULL
|}
            ~f:(fun statement ->
              match Sqlite3.step statement with
              | Sqlite3.Rc.ROW ->
                decode_raw_gc_plan
                  ~plan_path:(Sqlite3.column_text statement 0)
                  ~plan_json:(Sqlite3.column_text statement 1)
                  ~plan_md5:(Sqlite3.column_text statement 2)
              | Sqlite3.Rc.DONE -> Error Error.Gc_no_plan
              | return_code ->
                check database return_code
                |> Result.map ~f:(fun () -> assert false))
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;

let mark_raw_gc_applied
      ?(busy_timeout_ms = 5_000)
      ~database_path
      ~expected_slug
      ~plan_md5
      ~now
      ()
  =
  try
    let database = Sqlite3.db_open ~mode:`NO_CREATE database_path in
    Exn.protect
      ~f:(fun () ->
        try
          Sqlite3.busy_timeout database busy_timeout_ms;
          let open Result.Let_syntax in
          let%bind () = execute database "BEGIN IMMEDIATE" in
          let outcome =
            let%bind slug_text, _ = query_workspace database in
            let expected = Sandwalk_core.Slug.to_string expected_slug in
            let%bind () =
              if String.equal expected slug_text
              then Ok ()
              else
                Error
                  (Error.Workspace_slug_mismatch
                     { expected; actual = slug_text })
            in
            let%bind () = ensure_no_active_claims database in
            with_statement
              database
              {|
UPDATE raw_gc_plan
SET applied_at = ?1
WHERE singleton = 1 AND applied_at IS NULL AND plan_md5 = ?2
|}
              ~f:(fun statement ->
                let%bind () = bind_text database statement 1 now in
                let%bind () = bind_text database statement 2 plan_md5 in
                let%bind () = step_done database statement in
                if Sqlite3.changes database = 1
                then Ok ()
                else Error Error.Gc_plan_stale)
          in
          (match outcome with
           | Ok () -> execute database "COMMIT"
           | Error _ as error ->
             ignore (execute database "ROLLBACK" : (unit, Error.t) Result.t);
             error)
        with
        | exn -> Error (Error.Database_error (Exn.to_string exn)))
      ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
  with
  | exn -> Error (Error.Database_error (Exn.to_string exn))
;;
