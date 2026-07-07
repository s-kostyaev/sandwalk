open! Core
open! Async

let version = "0.1.0-dev"

let about_command =
  Async.Command.async
    ~summary:"Print Sandwalk build information as a JSON response."
    (let%map_open.Command () = return () in
     fun () ->
       let result =
         `Assoc [ "name", `String "sandwalk"; "version", `String version ]
       in
       Sandwalk_protocol.Envelope.success ~result ()
       |> Sandwalk_protocol.Envelope.render
       |> print_endline;
       Deferred.unit)
;;

let parsed_arguments ~slug ~directory_prefix =
  `Assoc
    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
    ; "directory_prefix", `String directory_prefix
    ]
;;

let command_line_flag name =
  let rec find = function
    | [] | [ _ ] -> None
    | flag :: value :: _ when String.equal flag name -> Some value
    | _ :: rest -> find rest
  in
  Sys.get_argv () |> Array.to_list |> find
;;

let hint_mode () =
  match Sys.getenv "SANDWALK_HINT_MODE" with
  | Some "none" -> `None
  | Some "full" -> `Full
  | Some "compact" | Some _ | None -> `Compact
;;

let workspace_hint words =
  match command_line_flag "--slug" with
  | None -> None
  | Some slug ->
    let words = [ "sandwalk" ] @ words @ [ "--slug"; slug ] in
    let words =
      match command_line_flag "--directory-prefix" with
      | None -> words
      | Some prefix -> words @ [ "--directory-prefix"; prefix ]
    in
    Some (Sandwalk_protocol.Shell_command.of_words words)
;;

let compact_hint code =
  match code with
  | "PLAN_NOT_VALIDATED" | "PLAN_VALIDATION_STALE" ->
    workspace_hint [ "plan"; "validate" ]
  | "STEP_DEPENDENCIES_INCOMPLETE" ->
    workspace_hint [ "next" ]
  | "STEP_ALREADY_CLAIMED" | "CLAIM_NOT_FOUND" | "CLAIM_NOT_ACTIVE" ->
    workspace_hint [ "resume" ]
  | "PLAN_MUTATION_NOT_ALLOWED"
  | "PLAN_VALIDATION_NOT_ALLOWED"
  | "PLAN_SEAL_NOT_ALLOWED"
  | "PLAN_OBJECTIVE_NOT_ALLOWED"
  | "PLAN_DEPENDENCY_NOT_ALLOWED"
  | "PLAN_EXTENSION_NOT_ALLOWED"
  | "RECON_START_NOT_ALLOWED"
  | "STEP_CLAIM_NOT_ALLOWED"
  | "STEP_COMPLETED"
  | "SEARCH_REQUIRES_CLAIM"
  | "FETCH_REQUIRES_CLAIM"
  | "EXCERPT_REQUIRES_CLAIM"
  | "SEARCH_NOT_ALLOWED"
  | "FETCH_NOT_ALLOWED"
  | "SNAPSHOT_PROMOTION_NOT_ALLOWED"
  | "EXCERPT_NOT_ALLOWED"
  | "FINDING_NOT_ALLOWED"
  | "DRAFT_NOT_ALLOWED"
  | "REPORT_NOT_ALLOWED"
  | "REPORT_REVIEW_NOT_ALLOWED"
  | "FINALIZE_NOT_ALLOWED"
  | "STEP_HAS_NO_FINDINGS"
  | "STEP_HAS_UNREVIEWED_FINDINGS"
  | "STEP_HAS_REJECTED_FINDINGS"
  | "FINDING_HAS_NO_EVIDENCE"
  | "FINDING_NOT_SEALED"
  | "DRAFT_GATE_FAILED"
  | "FINALIZE_GATE_FAILED"
  | "GC_ACTIVE_CLAIMS" ->
    workspace_hint [ "next" ]
  | "GC_PLAN_STALE" -> workspace_hint [ "gc"; "--raw"; "--plan" ]
  | _ -> None
;;

let phase_error_message operation phase =
  sprintf
    "%s is not allowed while the workspace phase is %s."
    operation
    (Sandwalk_core.Phase.to_string phase)
;;

let print_failure_and_exit ~code ~message =
  let next =
    match hint_mode () with
    | `None -> None
    | `Compact -> compact_hint code
    | `Full ->
      if String.equal code "UNKNOWN_ERROR_CODE"
      then None
      else
        Some
          (Sandwalk_protocol.Shell_command.of_words
             [ "sandwalk"; "explain"; code ])
  in
  Sandwalk_protocol.Envelope.failure ~code ~message ?next ()
  |> Sandwalk_protocol.Envelope.render
  |> print_endline;
  Shutdown.exit 1
;;

let explanation = function
  | "WORKSPACE_IO_ERROR" ->
    Some
      ( "Sandwalk could not create or update the selected workspace directory."
      , "Choose a writable `--directory-prefix` or set `SANDWALK_DIRECTORY_PREFIX` to one, then retry." )
  | "SEARCH_ADAPTER_FAILED" ->
    Some
      ( "The search adapter exited unsuccessfully, timed out, or returned invalid JSON."
      , "Verify the selected adapter and its search tool (`ddgr` or `ugrep+`) are on PATH and allowed by the filesystem or network sandbox." )
  | "FETCH_ADAPTER_FAILED" ->
    Some
      ( "The fetch adapter exited unsuccessfully, timed out, or returned invalid JSON."
      , "Verify the selected adapter and its normalizer are on PATH; local-file fetches require `sandwalk-fetch-file`, Docling for rich documents, and a sandbox-readable source root." )
  | "PLAN_EMPTY" ->
    Some
      ( "The plan has no steps, so it cannot be validated."
      , "Add at least one step with `sandwalk plan add-step`, then validate the plan." )
  | "PLAN_NOT_VALIDATED" ->
    Some
      ( "The current plan revision has not passed the explicit validation gate."
      , "Run `sandwalk plan validate --slug <slug>`, then retry sealing." )
  | "PLAN_VALIDATION_STALE" ->
    Some
      ( "The plan changed after validation, so the validation does not cover the current revision."
      , "Run `sandwalk plan validate --slug <slug>`, then retry sealing." )
  | "PLAN_EXTENSION_NOT_ALLOWED" ->
    Some
      ( "A sealed plan can accept append-only extensions only while research is active."
      , "Add the extension during `researching`; existing steps cannot be changed." )
  | "STEP_DEPENDENCIES_INCOMPLETE" ->
    Some
      ( "At least one declared dependency of this step has not completed."
      , "Complete the prerequisite steps before claiming this step." )
  | "STEP_ALREADY_CLAIMED" ->
    Some
      ( "The step already has an active exclusive claim."
      , "Resume the existing work with its claim identifier." )
  | "FINDING_HAS_NO_EVIDENCE" ->
    Some
      ( "A finding must cite at least one exact excerpt with a claim-bearing relation; context alone cannot support a finding."
      , "Attach an excerpt as `supports`, `contradicts`, or `qualifies`, then seal the finding." )
  | "FINDING_NOT_SEALED" ->
    Some
      ( "Only sealed finding revisions can receive an independent review."
      , "Seal the finding revision, then submit its review." )
  | "STEP_HAS_UNREVIEWED_FINDINGS" ->
    Some
      ( "Every current finding revision must have a review before the step can complete."
      , "Review each sealed finding, then retry `sandwalk step complete`." )
  | "STEP_HAS_REJECTED_FINDINGS" ->
    Some
      ( "At least one current finding review rejected or contradicted the finding."
      , "Revise the finding and evidence, seal the new revision, and review it again." )
  | "DRAFT_GATE_FAILED" ->
    Some
      ( "Drafting cannot start until all required research steps and finding reviews pass."
      , "Complete the remaining required evidence work, then retry draft preparation." )
  | "INVALID_WORK_PACKET" ->
    Some
      ( "The current work packet is malformed, unsupported, applied from the wrong path, or has modified fixed context."
      , "Run `sandwalk continue --slug <slug>` once, edit only `editable`, leave `integrity_md5` unchanged, and run the exact returned `apply` command." )
  | "REPORT_BLOCK_UNCITED" ->
    Some
      ( "A non-heading report block contains no current typed citation token."
      , "Use the block preview from the failing command. Blank lines delimit blocks; add `[cite:step-key/finding-key]` to that exact prose block." )
  | "EXPORT_ADAPTER_FAILED" ->
    Some
      ( "The selected export adapter exited unsuccessfully, timed out, or returned invalid JSON."
      , "Verify the adapter, Pandoc, and a supported Pandoc PDF engine are on PATH, then retry the export." )
  | "EXPORT_INPUT_STALE" ->
    Some
      ( "The final Markdown report or bibliography no longer matches the hashes recorded at finalization."
      , "Do not edit finalized projections. Restore the exact finalized `report.md` and `sources.md` before exporting." )
  | "REPORT_CITATION_INVALID" ->
    Some
      ( "The report contains a missing, stale, malformed, or unreviewed citation target."
      , "Use current `[cite:step-key/finding-key]` tokens from the writer pack." )
  | "REPORT_REVIEW_INCOMPLETE" ->
    Some
      ( "The report review does not contain exactly one verdict for every current report block."
      , "Review every block from the current report revision and resubmit the review." )
  | "FINALIZE_GATE_FAILED" ->
    Some
      ( "The current report, block reviews, finding reviews, or provenance no longer satisfies the final gate."
      , "Regenerate the relevant review or report revision before finalizing." )
  | "GC_ACTIVE_CLAIMS" ->
    Some
      ( "Raw artifact garbage collection is blocked while research claims are active."
      , "Checkpoint and complete the active work before generating a GC plan." )
  | "GC_PLAN_STALE" ->
    Some
      ( "The raw-artifact set changed after the garbage-collection plan was generated."
      , "Generate a new GC plan and apply that exact plan." )
  | _ -> None
;;

let explain_command =
  Async.Command.async
    ~summary:"Explain a stable Sandwalk error code and its repair."
    (let%map_open.Command code = anon ("CODE" %: string) in
     fun () ->
       match explanation code with
       | None ->
         print_failure_and_exit
           ~code:"UNKNOWN_ERROR_CODE"
           ~message:"No explanation is available for that error code."
       | Some (detail, repair) ->
         Sandwalk_protocol.Envelope.success
           ~result:
             (`Assoc
                [ "code", `String code
                ; "explanation", `String detail
                ; "repair", `String repair
                ])
           ()
         |> Sandwalk_protocol.Envelope.render
         |> print_endline;
         Deferred.unit)
;;

let init_command =
  Async.Command.async
    ~summary:"Create a new Sandwalk workspace."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let started_at = Time_float_unix.now () in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind invocation_id =
           In_thread.run (fun () ->
             Sandwalk_runtime.invocation_id ~now:started_at)
         in
         let%bind layout =
           Sandwalk_runtime.Workspace.create_layout ~directory_prefix ~slug
         in
         (match layout with
          | Error _ ->
            print_failure_and_exit
              ~code:"WORKSPACE_IO_ERROR"
              ~message:"Could not create workspace layout."
          | Ok workspace ->
            let%bind started =
              Sandwalk_runtime.Audit.append
                ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                (Sandwalk_protocol.Audit_event.create
                   ~invocation_id
                   ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                   ~kind:`Started
                   ~command:"init"
                   ~arguments
                   ~phase:None
                   ~raw_argv:(Sys.get_argv () |> Array.to_list)
                   ~state_changes:[]
                   ())
            in
            (match started with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () ->
               let%bind initialized =
                 In_thread.run (fun () ->
                   Sandwalk_store.initialize
                     ~database_path:
                       (Sandwalk_runtime.Workspace.database_path workspace)
                     ~slug
                     ~now:(Sandwalk_runtime.timestamp_utc started_at)
                     ())
               in
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let outcome, error_code =
                 match initialized with
                 | Ok () -> "success", None
                 | Error Sandwalk_store.Error.Already_initialized ->
                   "failure", Some "WORKSPACE_EXISTS"
                 | Error _ ->
                   "failure", Some "DATABASE_ERROR"
               in
               let%bind finished =
                 Sandwalk_runtime.Audit.append
                   ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                   (Sandwalk_protocol.Audit_event.create
                      ~invocation_id
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~kind:
                        (if String.equal outcome "success"
                         then `Finished
                         else `Failed)
                      ~command:"init"
                      ~arguments
                      ~phase:(Some "initialized")
                      ~raw_argv:(Sys.get_argv () |> Array.to_list)
                      ~state_changes:
                        (if String.equal outcome "success"
                         then
                           [ `Assoc
                               [ "entity", `String "workspace"
                               ; "from", `Null
                               ; "to", `String "initialized"
                               ]
                           ]
                         else [])
                      ~duration_ms
                      ~outcome
                      ?error_code
                      ())
               in
               (match finished with
                | Error _ ->
                  print_failure_and_exit
                    ~code:"AUDIT_LOG_ERROR"
                    ~message:"Could not append workspace audit log."
                | Ok () ->
                  (match initialized with
                   | Ok () ->
                     let result =
                       `Assoc
                         [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                         ; "phase", `String "initialized"
                         ; ( "schema_version"
                           , `Int Sandwalk_store.current_schema_version )
                         ]
                     in
                     Sandwalk_protocol.Envelope.success ~result ()
                     |> Sandwalk_protocol.Envelope.render
                     |> print_endline;
                     Deferred.unit
                   | Error Sandwalk_store.Error.Already_initialized ->
                     print_failure_and_exit
                       ~code:"WORKSPACE_EXISTS"
                       ~message:"Workspace already exists."
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"DATABASE_ERROR"
                       ~message:"Could not initialize workspace database.")))))
;;

let status_error = function
  | Sandwalk_store.Error.Not_initialized ->
    "WORKSPACE_NOT_INITIALIZED", "Workspace database is not initialized."
  | Unsupported_schema_version _ ->
    "SCHEMA_VERSION_UNSUPPORTED", "Workspace schema version is not supported."
  | Invalid_persisted_phase _ | Workspace_slug_mismatch _ ->
    "WORKSPACE_INVALID", "Workspace state is invalid."
  | Database_error _ ->
    "DATABASE_ERROR", "Could not read workspace database."
  | Already_initialized
  | Duplicate_plan_step _
  | Plan_mutation_wrong_phase _
  | Empty_plan
  | Plan_validation_wrong_phase _
  | Plan_not_validated
  | Plan_validation_stale _
  | Plan_seal_wrong_phase _
  | Plan_step_not_found _
  | Step_claim_wrong_phase _
  | Step_already_claimed
  | Step_completed _
  | Step_dependencies_incomplete _
  | Claim_id_collision
  | Invalid_step_state _
  | Claim_not_found
  | Claim_not_active
  | Candidate_not_found _
  | Candidate_not_owned_by_claim _
  | Search_wrong_phase _
  | Search_requires_claim
  | Hit_id_collision
  | Hit_not_found _
  | Hit_not_owned_by_claim _
  | Fetch_wrong_phase _
  | Fetch_requires_claim
  | Snapshot_id_collision
  | Snapshot_not_found _
  | Snapshot_not_owned_by_claim _
  | Snapshot_promotion_wrong_phase _
  | Snapshot_promotion_conflict _
  | Excerpt_wrong_phase _
  | Excerpt_requires_claim
  | Excerpt_id_collision
  | Finding_wrong_phase _
  | Finding_step_mismatch
  | Finding_exists _
  | Finding_not_found _
  | Excerpt_not_found _
  | Finding_excerpt_step_mismatch
  | Excerpt_stale _
  | Finding_has_no_evidence _
  | Finding_not_sealed _
  | Finding_review_conflict _
  | Step_has_no_findings _
  | Step_has_unreviewed_findings _
  | Step_has_rejected_findings _
  | Finding_repair_wrong_phase _
  | Finding_repair_requires_completed_step _
  | Finding_repair_has_completed_dependents _
  | Draft_wrong_phase _
  | Draft_gate_failed
  | Report_wrong_phase _
  | Report_citation_invalid _
  | Report_conflict
  | Report_review_wrong_phase _
  | Report_revision_stale
  | Report_review_incomplete
  | Report_block_stale _
  | Finalize_wrong_phase _
  | Finalize_gate_failed
  | Export_wrong_phase _
  | Export_not_finalized
  | Plan_objective_wrong_phase _
  | Plan_dependency_wrong_phase _
  | Plan_dependency_self
  | Plan_dependency_exists
  | Plan_dependency_cycle
  | Plan_extension_wrong_phase _
  | Recon_start_wrong_phase _
  | Recon_not_active _
  | Gc_active_claims
  | Gc_no_plan
  | Gc_plan_stale ->
    "DATABASE_ERROR", "Could not read workspace database."
;;

let path_is_directory path =
  try
    match (Core_unix.stat path).st_kind with
    | S_DIR -> true
    | S_REG | S_CHR | S_BLK | S_LNK | S_FIFO | S_SOCK -> false
  with
  | _ -> false
;;

let workspace_list_entry ~directory_prefix name =
  match Sandwalk_core.Slug.of_string name with
  | Error _ -> None
  | Ok slug ->
    let workspace = Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug in
    if not (path_is_directory (Sandwalk_runtime.Workspace.root workspace))
    then None
    else (
      let database_path = Sandwalk_runtime.Workspace.database_path workspace in
      let fields fields = `Assoc (("slug", `String name) :: fields) in
      if not (Sys_unix.file_exists_exn database_path)
      then
        Some
          (fields
             [ "phase", `Null
             ; "schema_version", `Null
             ; "error_code", `String "WORKSPACE_NOT_FOUND"
             ; "message", `String "Workspace does not exist."
             ])
      else (
        match
          Sandwalk_store.read_status ~database_path ~expected_slug:slug ()
        with
        | Ok status ->
          Some
            (fields
               [ ( "phase"
                 , `String
                     (Sandwalk_store.Workspace_status.phase status
                      |> Sandwalk_core.Phase.to_string) )
               ; ( "schema_version"
                 , `Int
                     (Sandwalk_store.Workspace_status.schema_version status) )
               ])
        | Error error ->
          let code, message = status_error error in
          Some
            (fields
               [ "phase", `Null
               ; "schema_version", `Null
               ; "error_code", `String code
               ; "message", `String message
               ])))
;;

let list_workspace_entries ~directory_prefix =
  Deferred.Or_error.try_with (fun () ->
    In_thread.run (fun () ->
      if not (Sys_unix.file_exists_exn directory_prefix)
      then []
      else
        Sys_unix.ls_dir directory_prefix
        |> List.filter_map ~f:(workspace_list_entry ~directory_prefix)
        |> List.sort ~compare:(fun left right ->
          let slug = function
            | `Assoc fields ->
              List.Assoc.find fields "slug" ~equal:String.equal
              |> Option.value_map ~default:"" ~f:(function
                | `String slug -> slug
                | _ -> "")
            | _ -> ""
          in
          String.compare (slug left) (slug right))))
;;

let list_command =
  Async.Command.async
    ~summary:"List Sandwalk workspaces under the current directory prefix."
    (let%map_open.Command directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       let directory_prefix =
         Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
       in
       let%bind entries = list_workspace_entries ~directory_prefix in
       match entries with
       | Error _ ->
         print_failure_and_exit
           ~code:"WORKSPACE_IO_ERROR"
           ~message:"Could not read workspace directory prefix."
       | Ok workspaces ->
         let result =
           `Assoc
             [ "directory_prefix", `String directory_prefix
             ; "workspaces", `List workspaces
             ]
         in
         Sandwalk_protocol.Envelope.success ~result ()
         |> Sandwalk_protocol.Envelope.render
         |> print_endline;
         Deferred.unit)
;;

type recommendation =
  { action : string
  ; reason : string
  ; words : string list
  ; details : (string * Yojson.Safe.t) list
  ; alternatives_possible : bool
  }

let workspace_words ~slug ~directory_prefix command =
  "sandwalk"
  :: command
  @ [ "--slug"
    ; Sandwalk_core.Slug.to_string slug
    ; "--directory-prefix"
    ; directory_prefix
    ]
;;

let research_recommendation ~slug ~directory_prefix = function
  | Sandwalk_store.Research_guidance.Search { claim_id; step_key; query } ->
    { action = "search"
    ; reason =
        "The selected active step has no stored source candidate to inspect."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "search"
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ; "--query"
          ; query
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "query", `String query
        ]
    ; alternatives_possible = true
    }
  | Fetch { claim_id; step_key; hit_id; title; url; snippet } ->
    { action = "fetch"
    ; reason =
        "The selected active step has an unfetched search result and no snapshot."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "fetch"
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ; Sandwalk_core.Hit_id.to_string hit_id
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "hit", `String (Sandwalk_core.Hit_id.to_string hit_id)
        ; "hit_title", `String title
        ; "hit_url", `String url
        ; "hit_snippet", `String snippet
        ]
    ; alternatives_possible = true
    }
  | Create_excerpt
      { claim_id
      ; step_key
      ; snapshot_id
      ; document_path
      ; document_media_type
      } ->
    { action = "create-excerpt"
    ; reason =
        "Inspect the selected normalized snapshot, then create an exact excerpt from a semantically relevant range."
    ; words = [ "sed"; "-n"; "1,200p"; document_path ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "snapshot", `String (Sandwalk_core.Snapshot_id.to_string snapshot_id)
        ; "document_path", `String document_path
        ; "document_media_type", `String document_media_type
        ]
    ; alternatives_possible = true
    }
  | Create_finding
      { claim_id; step_key; excerpt_id; excerpt_path } ->
    { action = "create-finding"
    ; reason =
        "The selected active step has exact evidence but no finding. Author a bounded statement in finding.md."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "finding"
          ; "create"
          ; "--step"
          ; Sandwalk_core.Plan_step.Key.to_string step_key
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ; "--key"
          ; "finding"
          ; "--claim-file"
          ; "finding.md"
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "candidate_excerpt", `String (Sandwalk_core.Excerpt_id.to_string excerpt_id)
        ; "candidate_excerpt_path", `String excerpt_path
        ]
    ; alternatives_possible = true
    }
  | Attach_evidence
      { claim_id; step_key; finding_key; excerpt_id; excerpt_path } ->
    { action = "attach-evidence"
    ; reason =
        "Inspect the selected exact excerpt, then attach appropriate evidence with a relation chosen from its semantic role."
    ; words = [ "sed"; "-n"; "1,200p"; excerpt_path ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; ( "finding"
          , `String
              (Sandwalk_core.Plan_step.Key.to_string step_key
               ^ "/"
               ^ Sandwalk_core.Finding_key.to_string finding_key) )
        ; "candidate_excerpt", `String (Sandwalk_core.Excerpt_id.to_string excerpt_id)
        ; "candidate_excerpt_path", `String excerpt_path
        ]
    ; alternatives_possible = true
    }
  | Seal_finding { claim_id; step_key; finding_key } ->
    let finding =
      Sandwalk_core.Plan_step.Key.to_string step_key
      ^ "/"
      ^ Sandwalk_core.Finding_key.to_string finding_key
    in
    { action = "seal-finding"
    ; reason =
        "The selected draft finding has evidence and is ready for its immutable review boundary."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "finding"
          ; "seal"
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ; "--finding"
          ; finding
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "finding", `String finding
        ]
    ; alternatives_possible = true
    }
  | Review_finding { claim_id; step_key; finding_key } ->
    let finding =
      Sandwalk_core.Plan_step.Key.to_string step_key
      ^ "/"
      ^ Sandwalk_core.Finding_key.to_string finding_key
    in
    { action = "review-finding"
    ; reason =
        "The selected sealed finding needs a current semantic review. Author finding-review.json before running the command."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "finding"
          ; "review"
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ; "--finding"
          ; finding
          ; "--review-file"
          ; "finding-review.json"
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ; "finding", `String finding
        ]
    ; alternatives_possible = true
    }
  | Complete_step { claim_id; step_key } ->
    { action = "complete-step"
    ; reason =
        "Every current finding for the selected step has an accepted current review."
    ; words =
        workspace_words
          ~slug
          ~directory_prefix
          [ "step"
          ; "complete"
          ; "--claim"
          ; Sandwalk_core.Claim_id.to_string claim_id
          ]
    ; details =
        [ "step", `String (Sandwalk_core.Plan_step.Key.to_string step_key)
        ; "claim", `String (Sandwalk_core.Claim_id.to_string claim_id)
        ]
    ; alternatives_possible = true
    }
;;

let recommendation_for_phase
      ~database_path
      ~slug
      ~directory_prefix
      ~phase
  =
  let fixed ?(alternatives_possible = false) action reason command =
    Deferred.return
      (Ok
         { action
         ; reason
         ; words = workspace_words ~slug ~directory_prefix command
         ; details = []
         ; alternatives_possible
         })
  in
  match phase with
  | Sandwalk_core.Phase.Initialized | Scoping ->
    fixed
      ~alternatives_possible:true
      "start-reconnaissance"
      "Workspace scope and plan are not yet defined."
      [ "recon"; "start"; "--goal-file"; "goal.md" ]
  | Reconnaissance ->
    fixed
      ~alternatives_possible:true
      "finish-reconnaissance"
      "Record the reconnaissance summary before planning."
      [ "recon"; "finish"; "--summary-file"; "recon-summary.md" ]
  | Planning ->
    In_thread.run (fun () ->
      Sandwalk_store.read_plan_state
        ~database_path
        ~expected_slug:slug
        ())
    >>| Result.map ~f:(fun plan ->
      if List.is_empty (Sandwalk_store.Plan_state.steps plan)
      then
        { action = "add-plan-step"
        ; reason = "The research plan has no steps."
        ; words =
            workspace_words
              ~slug
              ~directory_prefix
              [ "plan"
              ; "add-step"
              ; "--key"
              ; "research-step"
              ; "--title"
              ; "Research step"
              ]
        ; details = []
        ; alternatives_possible = true
        }
      else if
        not
          (Option.value_map
             (Sandwalk_store.Plan_state.validated_revision plan)
             ~default:false
             ~f:
               (Int.equal (Sandwalk_store.Plan_state.revision plan)))
      then
        { action = "validate-plan"
        ; reason = "The current plan revision has not been validated."
        ; words =
            workspace_words ~slug ~directory_prefix [ "plan"; "validate" ]
        ; details = []
        ; alternatives_possible = true
        }
      else
        { action = "seal-plan"
        ; reason = "The current plan revision is validated but not sealed."
        ; words =
            workspace_words ~slug ~directory_prefix [ "plan"; "seal" ]
        ; details = []
        ; alternatives_possible = true
        })
  | Researching ->
    In_thread.run (fun () ->
      Sandwalk_store.read_research_guidance ~database_path ())
    >>= (function
     | Error _ as error -> Deferred.return error
     | Ok (Some guidance) ->
       Deferred.return
         (Ok (research_recommendation ~slug ~directory_prefix guidance))
     | Ok None ->
       In_thread.run (fun () ->
         Sandwalk_store.read_next_step ~database_path ())
       >>| Result.map ~f:(function
         | Some key ->
           { action = "claim-step"
           ; reason =
               "The selected dependency-ready plan step has no active claim."
           ; words =
               workspace_words
                 ~slug
                 ~directory_prefix
                 [ "step"
                 ; "claim"
                 ; "--step"
                 ; Sandwalk_core.Plan_step.Key.to_string key
                 ]
           ; details =
               [ "step", `String (Sandwalk_core.Plan_step.Key.to_string key) ]
           ; alternatives_possible = true
           }
         | None ->
           { action = "inspect-recovery-state"
           ; reason =
               "No active claim or dependency-ready incomplete step was found."
           ; words =
               workspace_words ~slug ~directory_prefix [ "resume" ]
           ; details = []
           ; alternatives_possible = false
           }))
  | Evidence_review ->
    fixed
      "prepare-draft"
      "Required research steps are complete; prepare the writer pack."
      [ "draft"; "prepare" ]
  | Drafting ->
    fixed
      "submit-draft"
      "Author a cited report in draft.md from the writer pack."
      [ "draft"; "submit"; "--report-file"; "draft.md" ]
  | Draft_review ->
    fixed
      "review-draft"
      "Author a complete report block review in report-review.json."
      [ "draft"; "review"; "--review-file"; "report-review.json" ]
  | Finalizing ->
    fixed
      "finalize"
      "The current report and reviews satisfy the transition into finalization."
      [ "finalize" ]
  | Completed ->
    fixed
      ~alternatives_possible:true
      "inspect-completed-workspace"
      "The workflow is complete."
      [ "status" ]
;;

let recommendation_result ~phase recommendation =
  `Assoc
    ([ "phase", `String (Sandwalk_core.Phase.to_string phase)
     ; "action", `String recommendation.action
     ; "reason", `String recommendation.reason
     ; "advisory", `Bool true
     ; "alternatives_possible", `Bool recommendation.alternatives_possible
     ]
     @ recommendation.details)
;;

let recommendation_summary recommendation =
  let variability =
    if recommendation.alternatives_possible
    then
      " This is one deterministic recommendation; other valid actions may exist."
    else ""
  in
  recommendation.reason ^ variability
;;

let recommendation_detail recommendation name =
  List.Assoc.find recommendation.details ~equal:String.equal name
;;

let recommendation_detail_string_exn recommendation name =
  match recommendation_detail recommendation name with
  | Some (`String value) -> value
  | _ -> failwithf "Recommendation is missing %s" name ()
;;

let rec canonical_json = function
  | `Assoc fields ->
    fields
    |> List.map ~f:(fun (name, value) -> name, canonical_json value)
    |> List.sort ~compare:(fun (left, _) (right, _) ->
      String.compare left right)
    |> fun fields -> `Assoc fields
  | `List values -> `List (List.map values ~f:canonical_json)
  | (`Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _) as value ->
    value
;;

let work_packet_integrity packet =
  match packet with
  | `Assoc fields ->
    fields
    |> List.filter ~f:(fun (name, _) ->
      not (String.equal name "editable" || String.equal name "integrity_md5"))
    |> fun fields -> canonical_json (`Assoc fields)
    |> Yojson.Safe.to_string
    |> Md5.digest_string
    |> Md5.to_hex
  | _ -> failwith "Work packet must be an object"
;;

let seal_work_packet = function
  | `Assoc fields as packet ->
    `Assoc (fields @ [ "integrity_md5", `String (work_packet_integrity packet) ])
  | _ -> failwith "Work packet must be an object"
;;

let packet_workspace ~slug ~directory_prefix =
  `Assoc
    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
    ; "directory_prefix", `String directory_prefix
    ]
;;

let packet_step_context = function
  | None -> `Null
  | Some context ->
    `Assoc
      [ ( "research_objective"
        , `String (Sandwalk_store.Step_context.objective context) )
      ; ( "step"
        , `String
            (Sandwalk_store.Step_context.step_key context
             |> Sandwalk_core.Plan_step.Key.to_string) )
      ; "step_title", `String (Sandwalk_store.Step_context.step_title context)
      ]
;;

let default_search_query context recommendation =
  let fallback =
    match recommendation_detail recommendation "query" with
    | Some (`String query) -> query
    | _ -> recommendation.reason
  in
  match context with
  | None -> fallback
  | Some context ->
    let query =
      String.strip (Sandwalk_store.Step_context.step_title context)
      ^ " — "
      ^ String.strip (Sandwalk_store.Step_context.objective context)
    in
    String.prefix query (Int.min 512 (String.length query))
;;

let generic_work_packet
      ~slug
      ~directory_prefix
      ~phase
      ~step_context
      recommendation
  =
  let arguments =
    match recommendation.words with
    | "sandwalk" :: arguments -> arguments
    | arguments -> arguments
  in
  `Assoc
    [ "protocol", `String "sandwalk.work.v1"
    ; "action", `String "run-command"
    ; "workflow_action", `String recommendation.action
    ; "workspace", packet_workspace ~slug ~directory_prefix
    ; "phase", `String (Sandwalk_core.Phase.to_string phase)
    ; "context", packet_step_context step_context
    ; "instructions", `String recommendation.reason
    ; "fixed", `Assoc [ "arguments", `List (List.map arguments ~f:(fun value -> `String value)) ]
    ; "editable", `Assoc []
    ]
;;

let work_packet
      ~workspace
      ~slug
      ~directory_prefix
      ~phase
      ~report_blocks
      ~finding_review_context
      ~step_context
      recommendation
  =
  let base action instructions fixed editable =
    `Assoc
      [ "protocol", `String "sandwalk.work.v1"
      ; "action", `String action
      ; "workflow_action", `String recommendation.action
      ; "workspace", packet_workspace ~slug ~directory_prefix
      ; "phase", `String (Sandwalk_core.Phase.to_string phase)
      ; "context", packet_step_context step_context
      ; "instructions", `String instructions
      ; "fixed", `Assoc fixed
      ; "editable", `Assoc editable
      ]
  in
  let candidate_decisions =
    `List
      [ `String "accept"; `String "reject"; `String "restart-search" ]
  in
  let replacement_query =
    default_search_query step_context recommendation
  in
  match recommendation.action with
  | "search" ->
    base
      "search"
      "Refine editable.query into a concise search query that preserves the research subject and current step goal. To search user-authorized local documents, set editable.source_root to their readable directory; otherwise leave it empty. Apply runs Sandwalk search."
      [ "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ]
      [ "query", `String (default_search_query step_context recommendation)
      ; "source_root", `String ""
      ]
  | "fetch" ->
    base
      "fetch"
      "Inspect the candidate title, URL, and snippet. Accept it, reject it and try the next candidate, or restart-search when the query itself is wrong. Rejections require a concise reason."
      [ "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ; "hit", `String (recommendation_detail_string_exn recommendation "hit")
      ; "title", `String (recommendation_detail_string_exn recommendation "hit_title")
      ; "url", `String (recommendation_detail_string_exn recommendation "hit_url")
      ; "snippet", `String (recommendation_detail_string_exn recommendation "hit_snippet")
      ; "allowed_decisions", candidate_decisions
      ]
      [ "decision", `String ""
      ; "rejection_reason", `String ""
      ; "replacement_query", `String replacement_query
      ]
  | "create-excerpt" ->
    base
      "create-excerpt"
      "Read fixed.document_path against context. Accept it, reject it and try another candidate, or restart-search when retrieval/query quality is wrong. For accept, choose one exact relevant inclusive line range."
      [ "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ; "snapshot", `String (recommendation_detail_string_exn recommendation "snapshot")
      ; "document_path", `String (recommendation_detail_string_exn recommendation "document_path")
      ; ( "document_media_type"
        , `String
            (recommendation_detail_string_exn
               recommendation
               "document_media_type") )
      ; "allowed_decisions", candidate_decisions
      ]
      [ "decision", `String ""
      ; "line_start", `Null
      ; "line_end", `Null
      ; "rejection_reason", `String ""
      ; "replacement_query", `String replacement_query
      ]
  | "create-finding" ->
    base
      "create-finding"
      "Read fixed.candidate_excerpt_path against context. Accept it, reject it and inspect another candidate, or restart-search when the source set is wrong. For accept, fill a narrow supported statement, key, and relation."
      [ "step", `String (recommendation_detail_string_exn recommendation "step")
      ; "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ; ( "candidate_excerpt"
        , `String
            (recommendation_detail_string_exn recommendation "candidate_excerpt") )
      ; ( "candidate_excerpt_path"
        , `String
            (recommendation_detail_string_exn
               recommendation
               "candidate_excerpt_path") )
      ; ( "allowed_relations"
        , `List
            (List.map
               [ "supports"; "contradicts"; "qualifies"; "context" ]
               ~f:(fun value -> `String value)) )
      ; "allowed_decisions", candidate_decisions
      ]
      [ "decision", `String ""
      ; "key", `String "finding"
      ; "statement", `String ""
      ; "relation", `String ""
      ; "rejection_reason", `String ""
      ; "replacement_query", `String replacement_query
      ]
  | "attach-evidence" ->
    base
      "attach-evidence"
      "Read fixed.candidate_excerpt_path against the finding and context. Accept it, reject it and inspect another candidate, or restart-search when the source set is wrong. For accept, choose a relation."
      [ "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ; "finding", `String (recommendation_detail_string_exn recommendation "finding")
      ; ( "candidate_excerpt"
        , `String
            (recommendation_detail_string_exn recommendation "candidate_excerpt") )
      ; ( "candidate_excerpt_path"
        , `String
            (recommendation_detail_string_exn
               recommendation
               "candidate_excerpt_path") )
      ; ( "allowed_relations"
        , `List
            (List.map
               [ "supports"; "contradicts"; "qualifies"; "context" ]
               ~f:(fun value -> `String value)) )
      ; "allowed_decisions", candidate_decisions
      ]
      [ "decision", `String ""
      ; "relation", `String ""
      ; "rejection_reason", `String ""
      ; "replacement_query", `String replacement_query
      ]
  | "review-finding" ->
    let finding_review_context =
      Option.value_exn finding_review_context
    in
    let evidence =
      Sandwalk_store.Finding_review_context.evidence finding_review_context
      |> List.map ~f:(fun (excerpt, path, relation) ->
        `Assoc
          [ "excerpt", `String excerpt
          ; "path", `String path
          ; "relation", `String relation
          ])
    in
    base
      "review-finding"
      "Review every material assertion in fixed.statement against fixed.evidence and the current research context. Do not infer missing dates, status, or provenance. Use partially-supported or unsupported when any material assertion lacks exact support. Fill every review field without wrappers."
      [ "claim", `String (recommendation_detail_string_exn recommendation "claim")
      ; "finding", `String (recommendation_detail_string_exn recommendation "finding")
      ; ( "statement"
        , `String
            (Sandwalk_store.Finding_review_context.statement
               finding_review_context) )
      ; "evidence", `List evidence
      ; ( "allowed_verdicts"
        , `List
            (List.map
               [ "supported"
               ; "partially-supported"
               ; "unsupported"
               ; "contradicted"
               ]
               ~f:(fun value -> `String value)) )
      ]
      [ ( "review"
        , `Assoc
            [ "protocol", `String "sandwalk.finding-review.v1"
            ; "verdict", `String ""
            ; "summary", `String ""
            ; "source_quality", `String ""
            ; "conflicts", `String ""
            ; "qualifications", `String ""
            ] )
      ]
  | "submit-draft" ->
    base
      "submit-report"
      "Read fixed.writer_pack_path. Fill editable.report_markdown using only current typed citation tokens from that writer pack. Blank lines delimit blocks; every non-heading block, including prose before a list, needs a citation."
      [ "writer_pack_path", `String (Sandwalk_runtime.Workspace.writer_pack_path workspace) ]
      [ "report_markdown", `String "" ]
  | "review-draft" ->
    let revision =
      List.hd report_blocks
      |> Option.map ~f:Sandwalk_store.Current_report_block.report_revision
      |> Option.value ~default:0
    in
    let contexts, reviews =
      List.map report_blocks ~f:(fun block ->
        let ordinal = Sandwalk_store.Current_report_block.ordinal block in
        let md5 = Sandwalk_store.Current_report_block.block_md5 block in
        ( `Assoc
            [ "ordinal", `Int ordinal
            ; "block_md5", `String md5
            ; ( "text"
              , `String (Sandwalk_store.Current_report_block.block_text block) )
            ]
        , `Assoc
            [ "ordinal", `Int ordinal
            ; "block_md5", `String md5
            ; "verdict", `String ""
            ; "summary", `String ""
            ] ))
      |> List.unzip
    in
    base
      "review-report"
      "Review every fixed context block. Fill verdict and summary for every editable review while preserving ordinals and hashes."
      [ "report_revision", `Int revision
      ; "context_blocks", `List contexts
      ; ( "allowed_verdicts"
        , `List
            (List.map
               [ "supported"
               ; "partially-supported"
               ; "unsupported"
               ; "contradicted"
               ]
               ~f:(fun value -> `String value)) )
      ]
      [ "reviews", `List reviews ]
  | _ ->
    generic_work_packet
      ~slug
      ~directory_prefix
      ~phase
      ~step_context
      recommendation
;;

let json_member_assoc name = function
  | `Assoc fields ->
    List.Assoc.find fields ~equal:String.equal name
    |> Option.value_exn
  | _ -> failwithf "Expected object containing %s" name ()
;;

let json_string_member name json =
  match json_member_assoc name json with
  | `String value -> value
  | _ -> failwithf "Expected string field %s" name ()
;;

let json_int_member name json =
  match json_member_assoc name json with
  | `Int value -> value
  | _ -> failwithf "Expected integer field %s" name ()
;;

let json_string_list_member name json =
  match json_member_assoc name json with
  | `List values ->
    List.map values ~f:(function
      | `String value -> value
      | _ -> failwithf "Expected string values in %s" name ())
  | _ -> failwithf "Expected list field %s" name ()
;;

type work_packet_validation_error =
  | Unsupported_protocol
  | Fixed_fields_modified

let validate_work_protocol packet =
  match
    json_member_assoc "protocol" packet,
    json_member_assoc "integrity_md5" packet
  with
  | `String "sandwalk.work.v1", `String expected ->
    let actual = work_packet_integrity packet in
    if String.equal expected actual
    then Ok ()
    else Error Fixed_fields_modified
  | _ -> Error Unsupported_protocol
;;

let work_packet_workspace packet =
  let workspace = json_member_assoc "workspace" packet in
  json_string_member "slug" workspace, json_string_member "directory_prefix" workspace
;;

type work_packet_parse_error =
  | Malformed_packet
  | Packet_validation_failed of work_packet_validation_error
  | Invalid_workspace_or_path

let parse_work_packet ~packet_path ~content =
  match Or_error.try_with (fun () -> Yojson.Safe.from_string content) with
  | Error _ -> Error Malformed_packet
  | Ok packet ->
    (match validate_work_protocol packet with
     | Error error -> Error (Packet_validation_failed error)
     | Ok () ->
       (match
          Or_error.try_with (fun () ->
            let slug_text, directory_prefix =
              work_packet_workspace packet
            in
            let slug =
              match Sandwalk_core.Slug.of_string slug_text with
              | Ok slug -> slug
              | Error _ -> failwith "Invalid work-packet workspace slug"
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
            in
            if
              not
                (String.equal
                   packet_path
                   (Sandwalk_runtime.Workspace.work_packet_path workspace))
            then failwith "Only the current workspace packet may be applied";
            packet, slug, directory_prefix, workspace)
        with
        | Error _ -> Error Invalid_workspace_or_path
        | Ok parsed -> Ok parsed))
;;

let work_packet_parse_error_message = function
  | Malformed_packet ->
    "Work packet is malformed. Run sandwalk continue again and apply the \
     regenerated current.json."
  | Packet_validation_failed Fixed_fields_modified ->
    "Work-packet fixed fields or integrity_md5 changed. Run sandwalk continue \
     again, edit only editable, and keep integrity_md5 unchanged."
  | Packet_validation_failed Unsupported_protocol ->
    "Work packet protocol is missing or unsupported. Run sandwalk continue \
     again and apply the regenerated current.json."
  | Invalid_workspace_or_path ->
    "Work packet workspace or path is invalid. Apply only the exact current.json \
     path returned by sandwalk continue."
;;

let run_self_command arguments =
  let search_path =
    Sys.getenv "PATH"
    |> Option.value ~default:""
    |> String.split ~on:':'
  in
  let%bind process =
    Process.create_exn
      ~prog_search_path:search_path
      ~prog:(Sys.get_argv ()).(0)
      ~args:arguments
      ()
  in
  Process.collect_output_and_wait process
;;

let status_command =
  Async.Command.async
    ~summary:"Print the current state of a Sandwalk workspace."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let%bind started =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                  ~kind:`Started
                  ~command:"status"
                  ~arguments
                  ~phase:None
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes:[]
                  ())
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind status =
               In_thread.run (fun () ->
                 Sandwalk_store.read_status
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ())
             in
             let phase =
               Result.ok status
               |> Option.map ~f:(fun status ->
                 Sandwalk_store.Workspace_status.phase status
                 |> Sandwalk_core.Phase.to_string)
             in
             let error =
               Result.error status |> Option.map ~f:status_error
             in
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind finished =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                    ~kind:(if Result.is_ok status then `Finished else `Failed)
                    ~command:"status"
                    ~arguments
                    ~phase
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes:[]
                    ~duration_ms
                    ~outcome:
                      (if Result.is_ok status then "success" else "failure")
                    ?error_code:(Option.map error ~f:fst)
                    ())
             in
             (match finished with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                (match status with
                 | Error error ->
                   let code, message = status_error error in
                   print_failure_and_exit ~code ~message
                 | Ok status ->
                   let result =
                     `Assoc
                       [ ( "slug"
                         , `String
                             (Sandwalk_store.Workspace_status.slug status
                              |> Sandwalk_core.Slug.to_string) )
                       ; ( "phase"
                         , `String
                             (Sandwalk_store.Workspace_status.phase status
                              |> Sandwalk_core.Phase.to_string) )
                       ; ( "schema_version"
                         , `Int
                             (Sandwalk_store.Workspace_status.schema_version
                                status) )
                       ]
                   in
                   Sandwalk_protocol.Envelope.success ~result ()
                   |> Sandwalk_protocol.Envelope.render
                   |> print_endline;
                   Deferred.unit))))
;;

let resume_command =
  Async.Command.async
    ~summary:"Regenerate a bounded recovery pack from durable workspace state."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ?(state_changes = [])
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"resume"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let migration_time = Sandwalk_runtime.timestamp_utc started_at in
             let%bind migrated_and_status =
               In_thread.run (fun () ->
                 let open Result.Let_syntax in
                 let database_path =
                   Sandwalk_runtime.Workspace.database_path workspace
                 in
                 let%bind previous_schema_version =
                   Sandwalk_store.migrate_workspace
                     ~database_path
                     ~expected_slug:slug
                     ~now:migration_time
                     ()
                 in
                 let%map status =
                   Sandwalk_store.read_status
                     ~database_path
                     ~expected_slug:slug
                     ()
                 in
                 previous_schema_version, status)
             in
             (match migrated_and_status with
              | Error error ->
                let code, message = status_error error in
                fail_with_audit ~phase:None ~code ~message
              | Ok (previous_schema_version, status) ->
                let phase =
                  Sandwalk_store.Workspace_status.phase status
                in
                let database_path =
                  Sandwalk_runtime.Workspace.database_path workspace
                in
                let%bind recommendation =
                  recommendation_for_phase
                    ~database_path
                    ~slug
                    ~directory_prefix
                    ~phase
                in
                (match recommendation with
                 | Error error ->
                   let code, message = status_error error in
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code
                     ~message
                 | Ok recommendation ->
                let%bind
                  ( ((plan_steps, active_claims), latest_checkpoint)
                  , (resume_entities, history) )
                  =
                  Deferred.both
                    (Deferred.both
                       (Deferred.both
                          (In_thread.run (fun () ->
                             Sandwalk_store.read_plan_steps
                               ~database_path:
                                 (Sandwalk_runtime.Workspace.database_path workspace)
                               ()))
                          (In_thread.run (fun () ->
                             Sandwalk_store.read_active_claims
                               ~database_path:
                                 (Sandwalk_runtime.Workspace.database_path workspace)
                               ())))
                       (In_thread.run (fun () ->
                          Sandwalk_store.read_latest_checkpoint
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path workspace)
                            ())))
                    (Deferred.both
                       (In_thread.run (fun () ->
                          Sandwalk_store.read_resume_entities
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path
                                 workspace)
                            ()))
                       (Sandwalk_runtime.Audit.read_history
                          ~path:
                            (Sandwalk_runtime.Workspace.events_path workspace)
                          ~exclude_invocation_id:invocation_id))
                in
                (match
                   ( plan_steps
                   , active_claims
                   , latest_checkpoint
                   , resume_entities
                   , history )
                 with
                 | Error _, _, _, _, _
                 | _, Error _, _, _, _
                 | _, _, Error _, _, _
                 | _, _, _, Error _, _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_STATE_ERROR"
                     ~message:"Could not read durable recovery state."
                 | _, _, _, _, Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"RECOVERY_LOG_ERROR"
                     ~message:"Could not read workspace audit history."
                 | ( Ok plan_steps
                   , Ok active_claims
                   , Ok latest_checkpoint
                   , Ok resume_entities
                   , Ok history ) ->
                   let checkpoint_timestamp =
                     Option.map latest_checkpoint ~f:(fun checkpoint ->
                       Sandwalk_store.Latest_checkpoint.created_at checkpoint)
                   in
                   let recent_commands =
                     Sandwalk_runtime.Audit.recent_commands history
                     |> List.filter ~f:(fun summary ->
                       Option.value_map
                         checkpoint_timestamp
                         ~default:true
                         ~f:(fun checkpoint ->
                           String.compare
                             (Sandwalk_runtime.Audit.summary_timestamp summary)
                             checkpoint
                           > 0))
                     |> (fun summaries ->
                       match summaries with
                       | summary :: rest
                         when String.equal
                                (Sandwalk_runtime.Audit.summary_command summary)
                                "step checkpoint"
                              && String.equal
                                   (Sandwalk_runtime.Audit.summary_outcome
                                      summary)
                                   "success" -> rest
                       | summaries -> summaries)
                     |> List.map ~f:(fun summary ->
                       ( Sandwalk_runtime.Audit.summary_command summary
                       , Sandwalk_runtime.Audit.summary_outcome summary
                       , Sandwalk_runtime.Audit.summary_error_code summary ))
                   in
                   let next_command =
                     Sandwalk_protocol.Shell_command.of_words
                       recommendation.words
                   in
                   let pack =
                     Sandwalk_core.Resume_pack.render
                       ~slug
                       ~phase
                       ~schema_version:
                         (Sandwalk_store.Workspace_status.schema_version status)
                       ~plan_steps:
                         (List.map plan_steps ~f:(fun stored ->
                            ( Sandwalk_store.Stored_plan_step.key stored
                            , Sandwalk_store.Stored_plan_step.title stored
                            , Sandwalk_store.Stored_plan_step.required stored
                            , Sandwalk_store.Stored_plan_step.position stored )))
                       ~durable_entities:
                         (List.map resume_entities ~f:(fun entity ->
                            ( Sandwalk_store.Resume_entity.kind entity
                            , Sandwalk_store.Resume_entity.reference entity
                            , Sandwalk_store.Resume_entity.step entity
                            , Sandwalk_store.Resume_entity.detail entity )))
                       ~active_claims:
                         (List.map active_claims ~f:(fun active ->
                            ( Sandwalk_store.Active_claim.step_key active
                            , Sandwalk_store.Active_claim.claim_id active
                            , Sandwalk_store.Active_claim.attempt active )))
                       ~latest_checkpoint:
                         (Option.map latest_checkpoint ~f:(fun checkpoint ->
                            ( Sandwalk_store.Latest_checkpoint.step_key checkpoint
                            , Sandwalk_store.Latest_checkpoint.summary checkpoint
                            , Sandwalk_store.Latest_checkpoint.next checkpoint
                            , Sandwalk_store.Latest_checkpoint.created_at
                                checkpoint )))
                       ~recent_commands
                       ~unmatched_commands:
                         (Sandwalk_runtime.Audit.unmatched_commands history)
                       ~events_path:
                         (Sandwalk_runtime.Workspace.events_path workspace)
                       ~next_action:(recommendation_summary recommendation)
                       ~next_command
                   in
                   (match pack with
                    | Error Sandwalk_core.Resume_pack.Error.Too_large ->
                      fail_with_audit
                        ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                        ~code:"RESUME_PACK_TOO_LARGE"
                        ~message:"Recovery data exceeds the resume pack limit."
                    | Ok pack ->
                      let resume_path =
                        Sandwalk_runtime.Workspace.resume_path workspace
                      in
                      let%bind written =
                        Sandwalk_runtime.Atomic_file.write
                          ~path:resume_path
                          ~temporary_suffix:invocation_id
                          pack
                      in
                      (match written with
                       | Error _ ->
                         fail_with_audit
                           ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                           ~code:"WORKSPACE_IO_ERROR"
                           ~message:"Could not write workspace resume pack."
                       | Ok () ->
                         let finished_at = Time_float_unix.now () in
                         let duration_ms =
                           Time_float.diff finished_at started_at
                           |> Time_float.Span.to_ms
                           |> Float.iround_nearest_exn
                         in
                         let%bind logged =
                           append_event
                             ~kind:`Finished
                             ~timestamp:
                               (Sandwalk_runtime.timestamp_utc finished_at)
                             ~phase:
                               (Some (Sandwalk_core.Phase.to_string phase))
                             ~state_changes:
                               (if
                                  previous_schema_version
                                  < Sandwalk_store.current_schema_version
                                then
                                  [ `Assoc
                                      [ "entity", `String "workspace.schema"
                                      ; "from", `Int previous_schema_version
                                      ; ( "to"
                                        , `Int
                                            Sandwalk_store
                                            .current_schema_version )
                                      ]
                                  ]
                                else [])
                             ~duration_ms
                             ~outcome:"success"
                             ()
                         in
                         (match logged with
                          | Error _ ->
                            print_failure_and_exit
                              ~code:"AUDIT_LOG_ERROR"
                              ~message:"Could not append workspace audit log."
                          | Ok () ->
                            let result =
                              match
                                recommendation_result ~phase recommendation
                              with
                              | `Assoc fields ->
                                `Assoc
                                  ([ ( "slug"
                                     , `String
                                         (Sandwalk_core.Slug.to_string slug) )
                                   ; "resume_path", `String resume_path
                                   ; ( "schema_version"
                                     , `Int
                                         Sandwalk_store.current_schema_version )
                                   ]
                                   @ fields)
                              | _ -> assert false
                            in
                            Sandwalk_protocol.Envelope.success
                              ~result
                              ~next:next_command
                              ()
                            |> Sandwalk_protocol.Envelope.render
                            |> print_endline;
                            Deferred.unit))))))))
;;

let plan_error = function
  | Sandwalk_store.Error.Duplicate_plan_step key ->
    "PLAN_STEP_EXISTS", sprintf "Plan step %S already exists." key
  | Plan_mutation_wrong_phase phase ->
    "PLAN_MUTATION_NOT_ALLOWED", phase_error_message "Plan mutation" phase
  | Empty_plan -> "PLAN_EMPTY", "Plan must contain at least one step."
  | Plan_validation_wrong_phase phase ->
    "PLAN_VALIDATION_NOT_ALLOWED", phase_error_message "Plan validation" phase
  | Plan_not_validated ->
    "PLAN_NOT_VALIDATED", "Plan must be validated before sealing."
  | Plan_validation_stale _ ->
    "PLAN_VALIDATION_STALE", "Plan changed after its last validation."
  | Plan_seal_wrong_phase phase ->
    "PLAN_SEAL_NOT_ALLOWED", phase_error_message "Plan sealing" phase
  | Plan_objective_wrong_phase phase ->
    "PLAN_OBJECTIVE_NOT_ALLOWED", phase_error_message "Plan objective mutation" phase
  | Plan_dependency_wrong_phase phase ->
    "PLAN_DEPENDENCY_NOT_ALLOWED", phase_error_message "Plan dependency mutation" phase
  | Plan_dependency_self ->
    "PLAN_DEPENDENCY_SELF", "A plan step cannot depend on itself."
  | Plan_dependency_exists ->
    "PLAN_DEPENDENCY_EXISTS", "Plan dependency already exists."
  | Plan_dependency_cycle ->
    "PLAN_DEPENDENCY_CYCLE", "Plan dependency would create a cycle."
  | Plan_step_not_found key ->
    "PLAN_STEP_NOT_FOUND", sprintf "Plan step %S does not exist." key
  | Plan_extension_wrong_phase phase ->
    "PLAN_EXTENSION_NOT_ALLOWED", phase_error_message "Plan extension" phase
  | error -> status_error error
;;

let render_plan_state state =
  let steps = Sandwalk_store.Plan_state.steps state in
  let revision = Sandwalk_store.Plan_state.revision state in
  let validated =
    Option.value_map
      (Sandwalk_store.Plan_state.validated_revision state)
      ~default:false
      ~f:(Int.equal revision)
  in
  let sealed =
    Option.value_map
      (Sandwalk_store.Plan_state.sealed_revision state)
      ~default:false
      ~f:(Int.equal revision)
  in
  Sandwalk_core.Plan_projection.render
    ?objective:(Sandwalk_store.Plan_state.objective state)
    ~dependencies:(Sandwalk_store.Plan_state.dependencies state)
    ~extensions:
      (List.map
         (Sandwalk_store.Plan_state.extensions state)
         ~f:(fun extension ->
           ( Sandwalk_store.Stored_plan_extension.revision extension
           , Sandwalk_store.Stored_plan_extension.step_key extension
           , Sandwalk_store.Stored_plan_extension.reason extension )))
    ~phase:(Sandwalk_store.Plan_state.phase state)
    ~revision
    ~validated
    ~sealed
    ~steps:
      (List.map steps ~f:(fun stored ->
         ( Sandwalk_store.Stored_plan_step.key stored
         , Sandwalk_store.Stored_plan_step.title stored
         , Sandwalk_store.Stored_plan_step.required stored
         , Sandwalk_store.Stored_plan_step.position stored )))
    ()
;;

let write_plan_state workspace ~invocation_id state =
  let revision = Sandwalk_store.Plan_state.revision state in
  let validated =
    Option.value_map
      (Sandwalk_store.Plan_state.validated_revision state)
      ~default:false
      ~f:(Int.equal revision)
  in
  let sealed =
    Option.value_map
      (Sandwalk_store.Plan_state.sealed_revision state)
      ~default:false
      ~f:(Int.equal revision)
  in
  Sandwalk_runtime.Atomic_file.write_versioned
    ~path:(Sandwalk_runtime.Workspace.research_plan_path workspace)
    ~lock_path:(Sandwalk_runtime.Workspace.research_plan_lock_path workspace)
    ~temporary_suffix:invocation_id
    ~version:
      (Sandwalk_core.Plan_projection.version ~revision ~validated ~sealed)
    (render_plan_state state)
;;

let plan_add_step_command =
  Async.Command.async
    ~summary:"Append a step to the workspace research plan."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and key_text =
       flag "--key" (required string) ~doc:"KEY Human-readable plan step key"
     and title =
       flag "--title" (required string) ~doc:"TITLE Plan step title"
     and optional =
       flag "--optional" no_arg ~doc:" Mark this plan step as optional"
     in
     fun () ->
       match
         ( Sandwalk_core.Slug.of_string slug_text
         , Sandwalk_core.Plan_step.Key.of_string key_text )
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok key ->
         (match Sandwalk_core.Plan_step.create ~key ~title ~required:(not optional) with
          | Error error ->
            print_failure_and_exit
              ~code:"INVALID_PLAN_STEP"
              ~message:(Sandwalk_core.Plan_step.Error.message error)
          | Ok step ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
            in
            let arguments =
              `Assoc
                [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                ; "directory_prefix", `String directory_prefix
                ; ( "key"
                  , `String
                      (Sandwalk_core.Plan_step.Key.to_string
                         (Sandwalk_core.Plan_step.key step)) )
                ; "title", `String (Sandwalk_core.Plan_step.title step)
                ; "required", `Bool (Sandwalk_core.Plan_step.required step)
                ]
            in
            let%bind database_exists =
              Async.Sys.file_exists_exn
                (Sandwalk_runtime.Workspace.database_path workspace)
            in
            if not database_exists
            then
              print_failure_and_exit
                ~code:"WORKSPACE_NOT_FOUND"
                ~message:"Workspace does not exist."
            else (
              let started_at = Time_float_unix.now () in
              let%bind invocation_id =
                In_thread.run (fun () ->
                  Sandwalk_runtime.invocation_id ~now:started_at)
              in
              let append_event
                    ~kind
                    ~timestamp
                    ~phase
                    ~state_changes
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ()
                =
                Sandwalk_runtime.Audit.append
                  ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                  (Sandwalk_protocol.Audit_event.create
                     ~invocation_id
                     ~timestamp
                     ~kind
                     ~command:"plan add-step"
                     ~arguments
                     ~phase
                     ~raw_argv:(Sys.get_argv () |> Array.to_list)
                     ~state_changes
                     ?duration_ms
                     ?outcome
                     ?error_code
                     ())
              in
              let fail_with_audit ~phase ~state_changes ~code ~message =
                let finished_at = Time_float_unix.now () in
                let duration_ms =
                  Time_float.diff finished_at started_at
                  |> Time_float.Span.to_ms
                  |> Float.iround_nearest_exn
                in
                let%bind logged =
                  append_event
                    ~kind:`Failed
                    ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                    ~phase
                    ~state_changes
                    ~duration_ms
                    ~outcome:"failure"
                    ~error_code:code
                    ()
                in
                match logged with
                | Error _ ->
                  print_failure_and_exit
                    ~code:"AUDIT_LOG_ERROR"
                    ~message:"Could not append workspace audit log."
                | Ok () -> print_failure_and_exit ~code ~message
              in
              let%bind started =
                append_event
                  ~kind:`Started
                  ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                  ~phase:None
                  ~state_changes:[]
                  ()
              in
              match started with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                let%bind added =
                  In_thread.run (fun () ->
                    Sandwalk_store.add_plan_step
                      ~database_path:
                        (Sandwalk_runtime.Workspace.database_path workspace)
                      ~expected_slug:slug
                      ~step
                      ~now:(Sandwalk_runtime.timestamp_utc started_at)
                      ())
                in
                (match added with
                 | Error error ->
                   let code, message = plan_error error in
                   let phase =
                     match error with
                     | Sandwalk_store.Error.Plan_mutation_wrong_phase phase ->
                       Some (Sandwalk_core.Phase.to_string phase)
                     | _ -> None
                   in
                   fail_with_audit ~phase ~state_changes:[] ~code ~message
                 | Ok added ->
                   let previous_phase =
                     Sandwalk_store.Add_plan_step_result.previous_phase added
                   in
                   let _, phase_changes =
                     Sandwalk_store.Add_plan_step_result.phase_path added
                     |> List.fold
                          ~init:(previous_phase, [])
                          ~f:(fun (from, changes) into ->
                            ( into
                            , changes
                              @ [ `Assoc
                                    [ "entity", `String "workspace.phase"
                                    ; ( "from"
                                      , `String
                                          (Sandwalk_core.Phase.to_string from) )
                                    ; ( "to"
                                      , `String
                                          (Sandwalk_core.Phase.to_string into) )
                                    ]
                                ] ))
                   in
                   let state_changes =
                     let previous_schema_version =
                       Sandwalk_store.Add_plan_step_result.previous_schema_version
                         added
                     in
                     (if previous_schema_version
                         < Sandwalk_store.current_schema_version
                      then
                        [ `Assoc
                            [ "entity", `String "workspace.schema"
                            ; "from", `Int previous_schema_version
                            ; ( "to"
                              , `Int Sandwalk_store.current_schema_version )
                            ]
                        ]
                      else [])
                     @ phase_changes
                     @ [ `Assoc
                           [ "entity", `String "plan.step"
                           ; "from", `Null
                           ; ( "to"
                             , `String
                                 (Sandwalk_core.Plan_step.Key.to_string
                                    (Sandwalk_core.Plan_step.key step)) )
                           ]
                       ]
                   in
                   let phase =
                     Sandwalk_store.Add_plan_step_result.phase added
                   in
                   let steps =
                     Sandwalk_store.Add_plan_step_result.steps added
                   in
                   let revision =
                     Sandwalk_store.Add_plan_step_result.revision added
                   in
                   let projection =
                     Sandwalk_core.Plan_projection.render
                       ?objective:
                         (Sandwalk_store.Add_plan_step_result.objective added)
                       ~dependencies:
                         (Sandwalk_store.Add_plan_step_result.dependencies added)
                       ~phase
                       ~revision
                       ~validated:false
                       ~sealed:false
                       ~steps:
                         (List.map steps ~f:(fun stored ->
                            ( Sandwalk_store.Stored_plan_step.key stored
                            , Sandwalk_store.Stored_plan_step.title stored
                            , Sandwalk_store.Stored_plan_step.required stored
                            , Sandwalk_store.Stored_plan_step.position stored )))
                       ()
                   in
                   let plan_path =
                     Sandwalk_runtime.Workspace.research_plan_path workspace
                   in
                   let%bind written =
                     Sandwalk_runtime.Atomic_file.write_versioned
                       ~path:plan_path
                       ~lock_path:
                         (Sandwalk_runtime.Workspace.research_plan_lock_path
                            workspace)
                       ~temporary_suffix:invocation_id
                       ~version:
                         (Sandwalk_core.Plan_projection.version
                            ~revision
                            ~validated:false
                            ~sealed:false)
                       projection
                   in
                   (match written with
                    | Error _ ->
                      fail_with_audit
                        ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                        ~state_changes
                        ~code:"WORKSPACE_IO_ERROR"
                        ~message:"Could not write research plan projection."
                    | Ok () ->
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                          ~state_changes
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let stored =
                           List.find_exn steps ~f:(fun stored ->
                             String.equal
                               (Sandwalk_store.Stored_plan_step.key stored
                                |> Sandwalk_core.Plan_step.Key.to_string)
                               (Sandwalk_core.Plan_step.key step
                                |> Sandwalk_core.Plan_step.Key.to_string))
                         in
                         let result =
                           `Assoc
                             [ ( "key"
                               , `String
                                   (Sandwalk_core.Plan_step.key step
                                    |> Sandwalk_core.Plan_step.Key.to_string) )
                             ; ( "title"
                               , `String
                                   (Sandwalk_core.Plan_step.title step) )
                             ; ( "required"
                               , `Bool
                                   (Sandwalk_core.Plan_step.required step) )
                             ; ( "position"
                               , `Int
                                   (Sandwalk_store.Stored_plan_step.position
                                      stored) )
                             ; ( "phase"
                               , `String
                                   (Sandwalk_core.Phase.to_string phase) )
                             ; "plan_path", `String plan_path
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let plan_extend_command =
  Async.Command.async
    ~summary:"Append one reasoned step to a sealed plan."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and key_text =
       flag "--key" (required string) ~doc:"KEY New plan step key"
     and title = flag "--title" (required string) ~doc:"TITLE Plan step title"
     and optional =
       flag "--optional" no_arg ~doc:" Mark this plan step as optional"
     and dependencies =
       flag "--on" (listed string) ~doc:"STEP Existing prerequisite step"
     and reason_path =
       flag "--reason-file" (required string) ~doc:"PATH Extension reason"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Plan_step.Key.of_string key_text,
         List.map dependencies ~f:Sandwalk_core.Plan_step.Key.of_string
         |> Result.all
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error, _ | _, _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok key, Ok dependencies ->
         (match
            Sandwalk_core.Plan_step.create
              ~key
              ~title
              ~required:(not optional)
          with
          | Error error ->
            print_failure_and_exit
              ~code:"INVALID_PLAN_STEP"
              ~message:(Sandwalk_core.Plan_step.Error.message error)
          | Ok step ->
            let%bind reason_input =
              Sandwalk_runtime.File_input.read
                ~path:reason_path
                ~maximum_bytes:
                  Sandwalk_core.Plan_extension_reason.maximum_bytes
            in
            (match reason_input with
             | Error _ ->
               print_failure_and_exit
                 ~code:"PLAN_EXTENSION_REASON_FILE_ERROR"
                 ~message:"Could not read bounded plan extension reason."
             | Ok reason_input ->
               (match
                  Sandwalk_core.Plan_extension_reason.create
                    (Sandwalk_runtime.File_input.content reason_input)
                with
                | Error Empty ->
                  print_failure_and_exit
                    ~code:"PLAN_EXTENSION_REASON_EMPTY"
                    ~message:"Plan extension reason must not be empty."
                | Error Too_large ->
                  print_failure_and_exit
                    ~code:"PLAN_EXTENSION_REASON_TOO_LARGE"
                    ~message:"Plan extension reason exceeds 65536 bytes."
                | Ok reason ->
                  let directory_prefix =
                    Sandwalk_runtime.resolve_directory_prefix
                      ~command_line:directory_prefix
                  in
                  let workspace =
                    Sandwalk_runtime.Workspace.resolve
                      ~directory_prefix
                      ~slug
                  in
                  let key_text =
                    Sandwalk_core.Plan_step.key step
                    |> Sandwalk_core.Plan_step.Key.to_string
                  in
                  let dependency_texts =
                    List.map
                      dependencies
                      ~f:Sandwalk_core.Plan_step.Key.to_string
                  in
                  let reason_argument =
                    `Assoc
                      [ ( "path"
                        , `String
                            (Sandwalk_runtime.File_input.path reason_input) )
                      ; ( "md5"
                        , `String
                            (Sandwalk_runtime.File_input.md5 reason_input) )
                      ; ( "size"
                        , `Int
                            (Sandwalk_runtime.File_input.size reason_input) )
                      ]
                  in
                  let arguments =
                    `Assoc
                      [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                      ; "directory_prefix", `String directory_prefix
                      ; "key", `String key_text
                      ; "title", `String (Sandwalk_core.Plan_step.title step)
                      ; ( "required"
                        , `Bool (Sandwalk_core.Plan_step.required step) )
                      ; ( "dependencies"
                        , `List
                            (List.map dependency_texts ~f:(fun dependency ->
                               `String dependency)) )
                      ; "reason_file", reason_argument
                      ]
                  in
                  let%bind database_exists =
                    Async.Sys.file_exists_exn
                      (Sandwalk_runtime.Workspace.database_path workspace)
                  in
                  if not database_exists
                  then
                    print_failure_and_exit
                      ~code:"WORKSPACE_NOT_FOUND"
                      ~message:"Workspace does not exist."
                  else (
                    let started_at = Time_float_unix.now () in
                    let%bind invocation_id =
                      In_thread.run (fun () ->
                        Sandwalk_runtime.invocation_id ~now:started_at)
                    in
                    let append_event
                          ~kind
                          ~timestamp
                          ~phase
                          ~state_changes
                          ?duration_ms
                          ?outcome
                          ?error_code
                          ()
                      =
                      let consumed_references, created_references =
                        match kind with
                        | `Finished -> dependency_texts, [ key_text ]
                        | `Started | `Failed -> [], []
                      in
                      Sandwalk_runtime.Audit.append
                        ~path:
                          (Sandwalk_runtime.Workspace.events_path workspace)
                        (Sandwalk_protocol.Audit_event.create
                           ~invocation_id
                           ~timestamp
                           ~kind
                           ~command:"plan extend"
                           ~arguments
                           ~phase
                           ~raw_argv:(Sys.get_argv () |> Array.to_list)
                           ~state_changes
                           ~consumed_references
                           ~created_references
                           ?duration_ms
                           ?outcome
                           ?error_code
                           ())
                    in
                    let fail_with_audit ~phase ~code ~message =
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Failed
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase
                          ~state_changes:[]
                          ~duration_ms
                          ~outcome:"failure"
                          ~error_code:code
                          ()
                      in
                      match logged with
                      | Error _ ->
                        print_failure_and_exit
                          ~code:"AUDIT_LOG_ERROR"
                          ~message:"Could not append workspace audit log."
                      | Ok () -> print_failure_and_exit ~code ~message
                    in
                    let%bind started =
                      append_event
                        ~kind:`Started
                        ~timestamp:
                          (Sandwalk_runtime.timestamp_utc started_at)
                        ~phase:None
                        ~state_changes:[]
                        ()
                    in
                    match started with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let%bind extended =
                        In_thread.run (fun () ->
                          Sandwalk_store.extend_plan
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path
                                 workspace)
                            ~expected_slug:slug
                            ~step
                            ~dependencies
                            ~reason
                            ~reason_path:
                              (Sandwalk_runtime.File_input.path reason_input)
                            ~reason_md5:
                              (Sandwalk_runtime.File_input.md5 reason_input)
                            ~reason_size:
                              (Sandwalk_runtime.File_input.size reason_input)
                            ~now:
                              (Sandwalk_runtime.timestamp_utc started_at)
                            ())
                      in
                      (match extended with
                       | Error error ->
                         let code, message = plan_error error in
                         let phase =
                           match error with
                           | Sandwalk_store.Error.Plan_extension_wrong_phase
                               phase ->
                             Some (Sandwalk_core.Phase.to_string phase)
                           | _ -> None
                         in
                         fail_with_audit ~phase ~code ~message
                       | Ok extended ->
                         let state =
                           Sandwalk_store.Extend_plan_result.state extended
                         in
                         let revision =
                           Sandwalk_store.Plan_state.revision state
                         in
                         let phase = Sandwalk_store.Plan_state.phase state in
                         let state_changes =
                           let previous_schema_version =
                             Sandwalk_store.Extend_plan_result
                             .previous_schema_version
                               extended
                           in
                           (if
                              previous_schema_version
                              < Sandwalk_store.current_schema_version
                            then
                              [ `Assoc
                                  [ "entity", `String "workspace.schema"
                                  ; "from", `Int previous_schema_version
                                  ; ( "to"
                                    , `Int
                                        Sandwalk_store.current_schema_version )
                                  ]
                              ]
                            else [])
                           @ [ `Assoc
                                 [ "entity", `String "plan.step"
                                 ; "from", `Null
                                 ; "to", `String key_text
                                 ]
                             ; `Assoc
                                 [ "entity", `String "plan.revision"
                                 ; "from", `Int (revision - 1)
                                 ; "to", `Int revision
                                 ]
                             ]
                         in
                         let%bind written =
                           write_plan_state workspace ~invocation_id state
                         in
                         (match written with
                          | Error _ ->
                            fail_with_audit
                              ~phase:
                                (Some
                                   (Sandwalk_core.Phase.to_string phase))
                              ~code:"WORKSPACE_IO_ERROR"
                              ~message:
                                "Could not write research plan projection."
                          | Ok () ->
                            let finished_at = Time_float_unix.now () in
                            let duration_ms =
                              Time_float.diff finished_at started_at
                              |> Time_float.Span.to_ms
                              |> Float.iround_nearest_exn
                            in
                            let%bind logged =
                              append_event
                                ~kind:`Finished
                                ~timestamp:
                                  (Sandwalk_runtime.timestamp_utc finished_at)
                                ~phase:
                                  (Some
                                     (Sandwalk_core.Phase.to_string phase))
                                ~state_changes
                                ~duration_ms
                                ~outcome:"success"
                                ()
                            in
                            (match logged with
                             | Error _ ->
                               print_failure_and_exit
                                 ~code:"AUDIT_LOG_ERROR"
                                 ~message:
                                   "Could not append workspace audit log."
                             | Ok () ->
                               let result =
                                 `Assoc
                                   [ "key", `String key_text
                                   ; ( "title"
                                     , `String
                                         (Sandwalk_core.Plan_step.title step) )
                                   ; ( "required"
                                     , `Bool
                                         (Sandwalk_core.Plan_step.required
                                            step) )
                                   ; ( "position"
                                     , `Int
                                         (Sandwalk_store.Extend_plan_result
                                          .position
                                            extended) )
                                   ; "revision", `Int revision
                                   ; ( "dependencies"
                                     , `List
                                         (List.map
                                            dependency_texts
                                            ~f:(fun dependency ->
                                              `String dependency)) )
                                   ; ( "phase"
                                     , `String
                                         (Sandwalk_core.Phase.to_string phase)
                                     )
                                   ; ( "plan_path"
                                     , `String
                                         (Sandwalk_runtime.Workspace
                                          .research_plan_path
                                            workspace) )
                                   ]
                               in
                               Sandwalk_protocol.Envelope.success ~result ()
                               |> Sandwalk_protocol.Envelope.render
                               |> print_endline;
                               Deferred.unit))))))))
;;

let plan_validate_command =
  Async.Command.async
    ~summary:"Validate and record the current plan revision."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan validate"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~state_changes:[]
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ~state_changes:[]
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind validated =
               In_thread.run (fun () ->
                 Sandwalk_store.validate_plan
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ~now:(Sandwalk_runtime.timestamp_utc started_at)
                   ())
             in
             (match validated with
              | Error error ->
                let code, message = plan_error error in
                let phase =
                  match error with
                  | Sandwalk_store.Error.Plan_validation_wrong_phase phase ->
                    Some (Sandwalk_core.Phase.to_string phase)
                  | _ -> None
                in
                fail_with_audit ~phase ~code ~message
              | Ok validated ->
                let phase =
                  Sandwalk_store.Validate_plan_result.phase validated
                in
                let revision =
                  Sandwalk_store.Validate_plan_result.revision validated
                in
                let already_validated =
                  Sandwalk_store.Validate_plan_result.already_validated validated
                in
                let previous_schema_version =
                  Sandwalk_store.Validate_plan_result.previous_schema_version
                    validated
                in
                let state_changes =
                  (if previous_schema_version
                      < Sandwalk_store.current_schema_version
                   then
                     [ `Assoc
                         [ "entity", `String "workspace.schema"
                         ; "from", `Int previous_schema_version
                         ; "to", `Int Sandwalk_store.current_schema_version
                         ]
                     ]
                   else [])
                  @ if already_validated
                    then []
                    else
                      [ `Assoc
                          [ "entity", `String "plan.validation"
                          ; "from", `Null
                          ; "to", `Int revision
                          ]
                      ]
                in
                let steps =
                  Sandwalk_store.Validate_plan_result.steps validated
                in
                let projection =
                  Sandwalk_core.Plan_projection.render
                    ?objective:
                      (Sandwalk_store.Validate_plan_result.objective validated)
                    ~dependencies:
                      (Sandwalk_store.Validate_plan_result.dependencies
                         validated)
                    ~phase
                    ~revision
                    ~validated:true
                    ~sealed:false
                    ~steps:
                      (List.map steps ~f:(fun stored ->
                         ( Sandwalk_store.Stored_plan_step.key stored
                         , Sandwalk_store.Stored_plan_step.title stored
                         , Sandwalk_store.Stored_plan_step.required stored
                         , Sandwalk_store.Stored_plan_step.position stored )))
                    ()
                in
                let plan_path =
                  Sandwalk_runtime.Workspace.research_plan_path workspace
                in
                let%bind written =
                  Sandwalk_runtime.Atomic_file.write_versioned
                    ~path:plan_path
                    ~lock_path:
                      (Sandwalk_runtime.Workspace.research_plan_lock_path workspace)
                    ~temporary_suffix:invocation_id
                    ~version:
                      (Sandwalk_core.Plan_projection.version
                         ~revision
                         ~validated:true
                         ~sealed:false)
                    projection
                in
                (match written with
                 | Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~code:"WORKSPACE_IO_ERROR"
                     ~message:"Could not write research plan projection."
                 | Ok () ->
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                       ~state_changes
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let result =
                        `Assoc
                          [ "revision", `Int revision
                          ; "validated", `Bool true
                          ; "already_validated", `Bool already_validated
                          ; "phase", `String (Sandwalk_core.Phase.to_string phase)
                          ; "plan_path", `String plan_path
                          ]
                      in
                      Sandwalk_protocol.Envelope.success ~result ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let plan_seal_command =
  Async.Command.async
    ~summary:"Seal the validated plan and begin research."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan seal"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~state_changes ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~state_changes
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ~state_changes:[]
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind sealed =
               In_thread.run (fun () ->
                 Sandwalk_store.seal_plan
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ~now:(Sandwalk_runtime.timestamp_utc started_at)
                   ())
             in
             (match sealed with
              | Error error ->
                let code, message = plan_error error in
                let phase =
                  match error with
                  | Sandwalk_store.Error.Plan_seal_wrong_phase phase ->
                    Some (Sandwalk_core.Phase.to_string phase)
                  | _ -> None
                in
                fail_with_audit ~phase ~state_changes:[] ~code ~message
              | Ok sealed ->
                let previous_schema_version =
                  Sandwalk_store.Seal_plan_result.previous_schema_version sealed
                in
                let previous_phase =
                  Sandwalk_store.Seal_plan_result.previous_phase sealed
                in
                let phase = Sandwalk_store.Seal_plan_result.phase sealed in
                let revision =
                  Sandwalk_store.Seal_plan_result.revision sealed
                in
                let already_sealed =
                  Sandwalk_store.Seal_plan_result.already_sealed sealed
                in
                let state_changes =
                  (if previous_schema_version
                      < Sandwalk_store.current_schema_version
                   then
                     [ `Assoc
                         [ "entity", `String "workspace.schema"
                         ; "from", `Int previous_schema_version
                         ; "to", `Int Sandwalk_store.current_schema_version
                         ]
                     ]
                   else [])
                  @ if already_sealed
                    then []
                    else
                      [ `Assoc
                          [ "entity", `String "plan.sealed"
                          ; "from", `Null
                          ; "to", `Int revision
                          ]
                      ; `Assoc
                          [ "entity", `String "workspace.phase"
                          ; ( "from"
                            , `String
                                (Sandwalk_core.Phase.to_string previous_phase) )
                          ; "to", `String (Sandwalk_core.Phase.to_string phase)
                          ]
                      ]
                in
                let steps = Sandwalk_store.Seal_plan_result.steps sealed in
                let projection =
                  Sandwalk_core.Plan_projection.render
                    ?objective:
                      (Sandwalk_store.Seal_plan_result.objective sealed)
                    ~dependencies:
                      (Sandwalk_store.Seal_plan_result.dependencies sealed)
                    ~phase
                    ~revision
                    ~validated:true
                    ~sealed:true
                    ~steps:
                      (List.map steps ~f:(fun stored ->
                         ( Sandwalk_store.Stored_plan_step.key stored
                         , Sandwalk_store.Stored_plan_step.title stored
                         , Sandwalk_store.Stored_plan_step.required stored
                         , Sandwalk_store.Stored_plan_step.position stored )))
                    ()
                in
                let plan_path =
                  Sandwalk_runtime.Workspace.research_plan_path workspace
                in
                let projection_version =
                  Sandwalk_core.Plan_projection.version
                    ~revision
                    ~validated:true
                    ~sealed:true
                in
                let%bind written =
                  Sandwalk_runtime.Atomic_file.write_versioned
                    ~path:plan_path
                    ~lock_path:
                      (Sandwalk_runtime.Workspace.research_plan_lock_path workspace)
                    ~temporary_suffix:invocation_id
                    ~version:projection_version
                    projection
                in
                (match written with
                 | Error _ ->
                   fail_with_audit
                     ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                     ~state_changes
                     ~code:"WORKSPACE_IO_ERROR"
                     ~message:"Could not write research plan projection."
                 | Ok () ->
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:(Some (Sandwalk_core.Phase.to_string phase))
                       ~state_changes
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let result =
                        `Assoc
                          [ "revision", `Int revision
                          ; "sealed", `Bool true
                          ; "already_sealed", `Bool already_sealed
                          ; "phase", `String (Sandwalk_core.Phase.to_string phase)
                          ; "plan_path", `String plan_path
                          ]
                      in
                      Sandwalk_protocol.Envelope.success ~result ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let plan_set_objective_command =
  Async.Command.async
    ~summary:"Set the bounded canonical research objective."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and objective_path =
       flag "--file" (required string) ~doc:"PATH Objective text"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind input =
           Sandwalk_runtime.File_input.read
             ~path:objective_path
             ~maximum_bytes:Sandwalk_core.Plan_objective.maximum_bytes
         in
         (match input with
          | Error _ ->
            print_failure_and_exit
              ~code:"PLAN_OBJECTIVE_FILE_ERROR"
              ~message:"Could not read bounded plan objective."
          | Ok input ->
            (match
               Sandwalk_core.Plan_objective.create
                 (Sandwalk_runtime.File_input.content input)
             with
             | Error Empty ->
               print_failure_and_exit
                 ~code:"PLAN_OBJECTIVE_EMPTY"
                 ~message:"Plan objective must not be empty."
             | Error Too_large ->
               print_failure_and_exit
                 ~code:"PLAN_OBJECTIVE_TOO_LARGE"
                 ~message:"Plan objective exceeds 65,536 bytes."
             | Ok objective ->
               let%bind database_exists =
                 Async.Sys.file_exists_exn
                   (Sandwalk_runtime.Workspace.database_path workspace)
               in
               if not database_exists
               then
                 print_failure_and_exit
                   ~code:"WORKSPACE_NOT_FOUND"
                   ~message:"Workspace does not exist."
               else (
                 let started_at = Time_float_unix.now () in
                 let%bind invocation_id =
                   In_thread.run (fun () ->
                     Sandwalk_runtime.invocation_id ~now:started_at)
                 in
                 let arguments =
                   `Assoc
                     [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                     ; "directory_prefix", `String directory_prefix
                     ; ( "file"
                       , `Assoc
                           [ "path", `String objective_path
                           ; "size", `Int (Sandwalk_runtime.File_input.size input)
                           ; ( "hash"
                             , `Assoc
                                 [ "algorithm", `String "md5"
                                 ; ( "value"
                                   , `String
                                       (Sandwalk_runtime.File_input.md5 input) )
                                 ] )
                           ] )
                     ]
                 in
                 let append_event
                       ~kind
                       ~timestamp
                       ~phase
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ()
                   =
                   Sandwalk_runtime.Audit.append
                     ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                     (Sandwalk_protocol.Audit_event.create
                        ~invocation_id
                        ~timestamp
                        ~kind
                        ~command:"plan set-objective"
                        ~arguments
                        ~phase
                        ~raw_argv:(Sys.get_argv () |> Array.to_list)
                        ~state_changes
                        ?duration_ms
                        ?outcome
                        ?error_code
                        ())
                 in
                 let fail_with_audit ~code ~message =
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Failed
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:None
                       ~state_changes:[]
                       ~duration_ms
                       ~outcome:"failure"
                       ~error_code:code
                       ()
                   in
                   match logged with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () -> print_failure_and_exit ~code ~message
                 in
                 let%bind started =
                   append_event
                     ~kind:`Started
                     ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                     ~phase:None
                     ~state_changes:[]
                     ()
                 in
                 (match started with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let%bind mutated =
                      In_thread.run (fun () ->
                        Sandwalk_store.set_plan_objective
                          ~database_path:
                            (Sandwalk_runtime.Workspace.database_path workspace)
                          ~expected_slug:slug
                          ~objective:
                            (Sandwalk_core.Plan_objective.text objective)
                          ~objective_path
                          ~objective_md5:
                            (Sandwalk_runtime.File_input.md5 input)
                          ~objective_size:
                            (Sandwalk_runtime.File_input.size input)
                          ~now:
                            (Sandwalk_runtime.timestamp_utc started_at)
                          ())
                    in
                    (match mutated with
                     | Error error ->
                       let code, message = plan_error error in
                       fail_with_audit ~code ~message
                     | Ok mutated ->
                       let state =
                         Sandwalk_store.Mutate_plan_result.state mutated
                       in
                       let%bind written =
                         write_plan_state workspace ~invocation_id state
                       in
                       (match written with
                        | Error _ ->
                          fail_with_audit
                            ~code:"PLAN_PROJECTION_ERROR"
                            ~message:"Could not write research plan projection."
                        | Ok () ->
                          let finished_at = Time_float_unix.now () in
                          let duration_ms =
                            Time_float.diff finished_at started_at
                            |> Time_float.Span.to_ms
                            |> Float.iround_nearest_exn
                          in
                          let phase =
                            Sandwalk_store.Plan_state.phase state
                            |> Sandwalk_core.Phase.to_string
                          in
                          let%bind logged =
                            append_event
                              ~kind:`Finished
                              ~timestamp:
                                (Sandwalk_runtime.timestamp_utc finished_at)
                              ~phase:(Some phase)
                              ~state_changes:
                                [ `Assoc
                                    [ "entity", `String "plan.objective"
                                    ; "from", `Null
                                    ; "to", `String "updated"
                                    ]
                                ]
                              ~duration_ms
                              ~outcome:"success"
                              ()
                          in
                          (match logged with
                           | Error _ ->
                             print_failure_and_exit
                               ~code:"AUDIT_LOG_ERROR"
                               ~message:"Could not append workspace audit log."
                           | Ok () ->
                             let result =
                               `Assoc
                                 [ ( "revision"
                                   , `Int
                                       (Sandwalk_store.Plan_state.revision
                                          state) )
                                 ; "phase", `String phase
                                 ; ( "plan_path"
                                   , `String
                                       (Sandwalk_runtime.Workspace
                                        .research_plan_path
                                          workspace) )
                                 ]
                             in
                             Sandwalk_protocol.Envelope.success ~result ()
                             |> Sandwalk_protocol.Envelope.render
                             |> print_endline;
                             Deferred.unit))))))))
;;

let plan_add_dependency_command =
  Async.Command.async
    ~summary:"Add one acyclic dependency edge to the plan."
    (let%map_open.Command step_text = anon ("STEP" %: string)
     and slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and dependency_text =
       flag "--on" (required string) ~doc:"STEP Dependency step"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Plan_step.Key.of_string step_text,
         Sandwalk_core.Plan_step.Key.of_string dependency_text
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error, _ | _, _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok step_key, Ok dependency_key ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; "step", `String step_text
               ; "on", `String dependency_text
               ]
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan add-dependency"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase:None
                 ~state_changes:[]
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:(Some "planning")
               ~state_changes:[]
               ()
           in
           (match started with
            | Error _ ->
              print_failure_and_exit
                ~code:"AUDIT_LOG_ERROR"
                ~message:"Could not append workspace audit log."
            | Ok () ->
              let%bind mutated =
                In_thread.run (fun () ->
                  Sandwalk_store.add_plan_dependency
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~step_key
                    ~dependency_key
                    ~now:(Sandwalk_runtime.timestamp_utc started_at)
                    ())
              in
              (match mutated with
               | Error error ->
                 let code, message = plan_error error in
                 fail_with_audit ~code ~message
               | Ok mutated ->
                 let state =
                   Sandwalk_store.Mutate_plan_result.state mutated
                 in
                 let%bind written =
                   write_plan_state workspace ~invocation_id state
                 in
                 (match written with
                  | Error _ ->
                    fail_with_audit
                      ~code:"PLAN_PROJECTION_ERROR"
                      ~message:"Could not write research plan projection."
                  | Ok () ->
                    let finished_at = Time_float_unix.now () in
                    let duration_ms =
                      Time_float.diff finished_at started_at
                      |> Time_float.Span.to_ms
                      |> Float.iround_nearest_exn
                    in
                    let%bind logged =
                      append_event
                        ~kind:`Finished
                        ~timestamp:
                          (Sandwalk_runtime.timestamp_utc finished_at)
                        ~phase:(Some "planning")
                        ~state_changes:
                          [ `Assoc
                              [ "entity", `String "plan.dependency"
                              ; "from", `Null
                              ; ( "to"
                                , `String
                                    (step_text ^ "->" ^ dependency_text) )
                              ]
                          ]
                        ~duration_ms
                        ~outcome:"success"
                        ()
                    in
                    (match logged with
                     | Error _ ->
                       print_failure_and_exit
                         ~code:"AUDIT_LOG_ERROR"
                         ~message:"Could not append workspace audit log."
                     | Ok () ->
                       let result =
                         `Assoc
                           [ ( "revision"
                             , `Int
                                 (Sandwalk_store.Plan_state.revision state) )
                           ; "step", `String step_text
                           ; "depends_on", `String dependency_text
                           ; ( "plan_path"
                             , `String
                                 (Sandwalk_runtime.Workspace.research_plan_path
                                    workspace) )
                           ]
                       in
                       Sandwalk_protocol.Envelope.success ~result ()
                       |> Sandwalk_protocol.Envelope.render
                       |> print_endline;
                       Deferred.unit))))))
;;

let plan_list_command =
  Async.Command.async
    ~summary:"List the canonical objective, steps, and dependencies."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ]
           in
           let append_event ~kind ~timestamp ?duration_ms ?outcome ?error_code () =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"plan list"
                  ~arguments
                  ~phase:None
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes:[]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ()
           in
           (match started with
            | Error _ ->
              print_failure_and_exit
                ~code:"AUDIT_LOG_ERROR"
                ~message:"Could not append workspace audit log."
            | Ok () ->
              let%bind state =
                In_thread.run (fun () ->
                  Sandwalk_store.read_plan_state
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ())
              in
              (match state with
               | Error error ->
                 let code, message = plan_error error in
                 let%bind _ =
                   append_event
                     ~kind:`Failed
                     ~timestamp:
                       (Sandwalk_runtime.timestamp_utc (Time_float_unix.now ()))
                     ~outcome:"failure"
                     ~error_code:code
                     ()
                 in
                 print_failure_and_exit ~code ~message
               | Ok state ->
                 let finished_at = Time_float_unix.now () in
                 let duration_ms =
                   Time_float.diff finished_at started_at
                   |> Time_float.Span.to_ms
                   |> Float.iround_nearest_exn
                 in
                 let%bind logged =
                   append_event
                     ~kind:`Finished
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~duration_ms
                     ~outcome:"success"
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let steps =
                      Sandwalk_store.Plan_state.steps state
                      |> List.map ~f:(fun step ->
                        `Assoc
                          [ ( "key"
                            , `String
                                (Sandwalk_store.Stored_plan_step.key step
                                 |> Sandwalk_core.Plan_step.Key.to_string) )
                          ; ( "title"
                            , `String
                                (Sandwalk_store.Stored_plan_step.title step) )
                          ; ( "required"
                            , `Bool
                                (Sandwalk_store.Stored_plan_step.required
                                   step) )
                          ; ( "position"
                            , `Int
                                (Sandwalk_store.Stored_plan_step.position
                                   step) )
                          ])
                    in
                    let dependencies =
                      Sandwalk_store.Plan_state.dependencies state
                      |> List.map ~f:(fun (step, dependency) ->
                        `Assoc
                          [ "step", `String step
                          ; "depends_on", `String dependency
                          ])
                    in
                    let extensions =
                      Sandwalk_store.Plan_state.extensions state
                      |> List.map ~f:(fun extension ->
                        `Assoc
                          [ ( "revision"
                            , `Int
                                (Sandwalk_store.Stored_plan_extension.revision
                                   extension) )
                          ; ( "step"
                            , `String
                                (Sandwalk_store.Stored_plan_extension.step_key
                                   extension
                                 |> Sandwalk_core.Plan_step.Key.to_string) )
                          ; ( "reason"
                            , `String
                                (Sandwalk_store.Stored_plan_extension.reason
                                   extension) )
                          ])
                    in
                    let result =
                      `Assoc
                        [ ( "phase"
                          , `String
                              (Sandwalk_store.Plan_state.phase state
                               |> Sandwalk_core.Phase.to_string) )
                        ; ( "revision"
                          , `Int (Sandwalk_store.Plan_state.revision state) )
                        ; ( "objective"
                          , Option.value_map
                              (Sandwalk_store.Plan_state.objective state)
                              ~default:`Null
                              ~f:(fun value -> `String value) )
                        ; "steps", `List steps
                        ; "dependencies", `List dependencies
                        ; "extensions", `List extensions
                        ]
                    in
                    Sandwalk_protocol.Envelope.success ~result ()
                    |> Sandwalk_protocol.Envelope.render
                    |> print_endline;
                    Deferred.unit)))))
;;

let plan_command =
  Async.Command.group
    ~summary:"Manage the canonical research plan."
    [ "add-step", plan_add_step_command
    ; "add-dependency", plan_add_dependency_command
    ; "extend", plan_extend_command
    ; "list", plan_list_command
    ; "seal", plan_seal_command
    ; "set-objective", plan_set_objective_command
    ; "validate", plan_validate_command
    ]
;;

let recon_error = function
  | Sandwalk_store.Error.Recon_start_wrong_phase phase ->
    "RECON_START_NOT_ALLOWED", phase_error_message "Reconnaissance start" phase
  | Recon_not_active phase ->
    "RECON_NOT_ACTIVE", phase_error_message "Reconnaissance mutation" phase
  | error -> status_error error
;;

let recon_file_command kind =
  let summary, file_flag, file_doc, command_name =
    match kind with
    | `Start ->
      ( "Start bounded reconnaissance."
      , "--goal-file"
      , "PATH Reconnaissance goal"
      , "recon start" )
    | `Observation ->
      ( "Add a bounded reconnaissance observation."
      , "--text-file"
      , "PATH Observation text"
      , "recon add-observation" )
    | `Finish ->
      ( "Finish reconnaissance with a bounded summary."
      , "--summary-file"
      , "PATH Reconnaissance summary"
      , "recon finish" )
  in
  Async.Command.async
    ~summary
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and file_path = flag file_flag (required string) ~doc:file_doc in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:file_path
               ~maximum_bytes:Sandwalk_core.Recon_document.maximum_bytes
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"RECON_FILE_ERROR"
               ~message:"Could not read bounded reconnaissance text."
           | Ok input ->
             (match
                Sandwalk_core.Recon_document.create
                  (Sandwalk_runtime.File_input.content input)
              with
              | Error Empty ->
                print_failure_and_exit
                  ~code:"RECON_TEXT_EMPTY"
                  ~message:"Reconnaissance text must not be empty."
              | Error Too_large ->
                print_failure_and_exit
                  ~code:"RECON_TEXT_TOO_LARGE"
                  ~message:"Reconnaissance text exceeds 65,536 bytes."
              | Ok document ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; ( "file"
                      , `Assoc
                          [ "path", `String file_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind:event_kind
                      ~timestamp
                      ~phase
                      ~state_changes
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind:event_kind
                       ~command:command_name
                       ~arguments
                       ~phase
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit ~code ~message =
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Failed
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:None
                      ~state_changes:[]
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~phase:None
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let text = Sandwalk_core.Recon_document.text document in
                   let md5 = Sandwalk_runtime.File_input.md5 input in
                   let size = Sandwalk_runtime.File_input.size input in
                   let now = Sandwalk_runtime.timestamp_utc started_at in
                   let%bind result =
                     In_thread.run (fun () ->
                       match kind with
                       | `Start ->
                         Sandwalk_store.start_reconnaissance
                           ~database_path:
                             (Sandwalk_runtime.Workspace.database_path workspace)
                           ~expected_slug:slug
                           ~goal_text:text
                           ~goal_path:file_path
                           ~goal_md5:md5
                           ~goal_size:size
                           ~now
                           ()
                       | `Observation ->
                         Sandwalk_store.add_reconnaissance_observation
                           ~database_path:
                             (Sandwalk_runtime.Workspace.database_path workspace)
                           ~expected_slug:slug
                           ~observation_text:text
                           ~observation_path:file_path
                           ~observation_md5:md5
                           ~observation_size:size
                           ~now
                           ()
                       | `Finish ->
                         Sandwalk_store.finish_reconnaissance
                           ~database_path:
                             (Sandwalk_runtime.Workspace.database_path workspace)
                           ~expected_slug:slug
                           ~summary_text:text
                           ~summary_path:file_path
                           ~summary_md5:md5
                           ~summary_size:size
                           ~now
                           ())
                   in
                   (match result with
                    | Error error ->
                      let code, message = recon_error error in
                      fail_with_audit ~code ~message
                    | Ok result ->
                      let phase =
                        Sandwalk_store.Recon_result.phase result
                        |> Sandwalk_core.Phase.to_string
                      in
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let state_changes =
                        match kind with
                        | `Start ->
                          let previous_phase =
                            Sandwalk_store.Recon_result.previous_phase result
                            |> Sandwalk_core.Phase.to_string
                          in
                          [ `Assoc
                              [ "entity", `String "workspace.phase"
                              ; "from", `String previous_phase
                              ; "to", `String phase
                              ]
                          ]
                        | `Observation ->
                          [ `Assoc
                              [ "entity", `String "recon.observation"
                              ; "from", `Null
                              ; ( "to"
                                , `Int
                                    (Sandwalk_store.Recon_result
                                     .observation_count
                                       result) )
                              ]
                          ]
                        | `Finish ->
                          [ `Assoc
                              [ "entity", `String "workspace.phase"
                              ; "from", `String "reconnaissance"
                              ; "to", `String phase
                              ]
                          ]
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase:(Some phase)
                          ~state_changes
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let result_json =
                           `Assoc
                             [ "phase", `String phase
                             ; ( "observations"
                               , `Int
                                   (Sandwalk_store.Recon_result
                                    .observation_count
                                      result) )
                             ]
                         in
                         Sandwalk_protocol.Envelope.success
                           ~result:result_json
                           ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let recon_command =
  Async.Command.group
    ~summary:"Manage bounded pre-plan reconnaissance."
    [ "add-observation", recon_file_command `Observation
    ; "finish", recon_file_command `Finish
    ; "start", recon_file_command `Start
    ]
;;

let claim_error = function
  | Sandwalk_store.Error.Plan_step_not_found key ->
    "PLAN_STEP_NOT_FOUND", sprintf "Plan step %S does not exist." key
  | Step_claim_wrong_phase phase ->
    "STEP_CLAIM_NOT_ALLOWED", phase_error_message "Step claim" phase
  | Step_already_claimed ->
    "STEP_ALREADY_CLAIMED", "Plan step already has an active claim."
  | Step_completed key ->
    "STEP_COMPLETED", sprintf "Plan step %S is already completed." key
  | Step_dependencies_incomplete key ->
    "STEP_DEPENDENCIES_INCOMPLETE",
    sprintf "Plan step %S has incomplete dependencies." key
  | Claim_id_collision ->
    "CLAIM_ID_COLLISION", "Could not allocate a unique claim identifier."
  | Claim_not_found -> "CLAIM_NOT_FOUND", "Claim does not exist."
  | Claim_not_active -> "CLAIM_NOT_ACTIVE", "Claim is no longer active."
  | error -> status_error error
;;

let step_claim_command =
  Async.Command.async
    ~summary:"Acquire an exclusive capability for one plan step."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and step_text =
       flag "--step" (required string) ~doc:"KEY Plan step key"
     in
     fun () ->
       match
         ( Sandwalk_core.Slug.of_string slug_text
         , Sandwalk_core.Plan_step.Key.of_string step_text )
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error error ->
         print_failure_and_exit
           ~code:"INVALID_PLAN_STEP_KEY"
           ~message:(Sandwalk_core.Plan_step.Key.Error.message error)
       | Ok slug, Ok step_key ->
           let directory_prefix =
             Sandwalk_runtime.resolve_directory_prefix
               ~command_line:directory_prefix
           in
           let workspace =
             Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; ( "step"
                 , `String
                     (Sandwalk_core.Plan_step.Key.to_string step_key) )
               ]
           in
           let%bind database_exists =
             Async.Sys.file_exists_exn
               (Sandwalk_runtime.Workspace.database_path workspace)
           in
           if not database_exists
           then
             print_failure_and_exit
               ~code:"WORKSPACE_NOT_FOUND"
               ~message:"Workspace does not exist."
           else (
             let started_at = Time_float_unix.now () in
             let%bind invocation_id =
               In_thread.run (fun () ->
                 Sandwalk_runtime.invocation_id ~now:started_at)
             in
             let append_event
                   ~kind
                   ~timestamp
                   ~phase
                   ~state_changes
                   ?claim
                   ?created_references
                   ?duration_ms
                   ?outcome
                   ?error_code
                   ()
               =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp
                    ~kind
                    ~command:"step claim"
                    ~arguments
                    ~phase
                    ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes
                    ?claim
                    ?created_references
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ())
             in
             let fail_with_audit ~phase ~code ~message =
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let%bind logged =
                 append_event
                   ~kind:`Failed
                   ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                   ~phase
                   ~state_changes:[]
                   ~duration_ms
                   ~outcome:"failure"
                   ~error_code:code
                   ()
               in
               match logged with
               | Error _ ->
                 print_failure_and_exit
                   ~code:"AUDIT_LOG_ERROR"
                   ~message:"Could not append workspace audit log."
               | Ok () -> print_failure_and_exit ~code ~message
             in
             let%bind started =
               append_event
                 ~kind:`Started
                 ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                 ~phase:None
                 ~state_changes:[]
                 ()
             in
             match started with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () ->
               let rec allocate retries =
                 let%bind claim_id =
                   In_thread.run Sandwalk_runtime.claim_id
                 in
                 let%bind result =
                   In_thread.run (fun () ->
                     Sandwalk_store.claim_step
                       ~database_path:
                         (Sandwalk_runtime.Workspace.database_path workspace)
                       ~expected_slug:slug
                       ~step_key
                       ~claim_id
                       ~now:(Sandwalk_runtime.timestamp_utc started_at)
                       ())
                 in
                 match result with
                 | Error Sandwalk_store.Error.Claim_id_collision
                   when retries > 0 -> allocate (retries - 1)
                 | result -> Deferred.return result
               in
               let%bind claimed = allocate 2 in
               (match claimed with
                | Error error ->
                  let code, message = claim_error error in
                  let phase =
                    match error with
                    | Sandwalk_store.Error.Step_claim_wrong_phase phase ->
                      Some (Sandwalk_core.Phase.to_string phase)
                    | _ -> Some "researching"
                  in
                  fail_with_audit ~phase ~code ~message
                | Ok claimed ->
                  let claim_id =
                    Sandwalk_store.Claim_step_result.claim_id claimed
                    |> Sandwalk_core.Claim_id.to_string
                  in
                  let previous_state =
                    Sandwalk_store.Claim_step_result.previous_state claimed
                  in
                  let previous_schema_version =
                    Sandwalk_store.Claim_step_result.previous_schema_version
                      claimed
                  in
                  let state_changes =
                    (if previous_schema_version
                        < Sandwalk_store.current_schema_version
                     then
                       [ `Assoc
                           [ "entity", `String "workspace.schema"
                           ; "from", `Int previous_schema_version
                           ; "to", `Int Sandwalk_store.current_schema_version
                           ]
                       ]
                     else [])
                    @ [ `Assoc
                          [ ( "entity"
                            , `String
                                ("step."
                                 ^ Sandwalk_core.Plan_step.Key.to_string step_key
                                 ^ ".state") )
                          ; ( "from"
                            , `String
                                (Sandwalk_core.Step_state.to_string previous_state)
                            )
                          ; "to", `String "claimed"
                          ]
                      ]
                  in
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Finished
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "researching")
                      ~state_changes
                      ~claim:claim_id
                      ~created_references:[ claim_id ]
                      ~duration_ms
                      ~outcome:"success"
                      ()
                  in
                  (match logged with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () ->
                     let result =
                       `Assoc
                         [ "claim", `String claim_id
                         ; ( "step"
                           , `String
                               (Sandwalk_core.Plan_step.Key.to_string step_key) )
                         ; ( "attempt"
                           , `Int
                               (Sandwalk_store.Claim_step_result.attempt
                                  claimed) )
                         ]
                     in
                     Sandwalk_protocol.Envelope.success ~result ()
                     |> Sandwalk_protocol.Envelope.render
                     |> print_endline;
                     Deferred.unit))))
;;

let step_checkpoint_command =
  Async.Command.async
    ~summary:"Record a semantic checkpoint for an active claim."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active claim capability"
     and summary_path =
       flag "--summary-file" (required string) ~doc:"PATH Checkpoint summary file"
     and next_path =
       flag "--next-file" (required string) ~doc:"PATH Next-action file"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text, Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let maximum_bytes = Sandwalk_core.Checkpoint.maximum_file_bytes in
           let%bind summary_input, next_input =
             Deferred.both
               (Sandwalk_runtime.File_input.read
                  ~path:summary_path
                  ~maximum_bytes)
               (Sandwalk_runtime.File_input.read ~path:next_path ~maximum_bytes)
           in
           match summary_input, next_input with
           | Error _, _ | _, Error _ ->
             print_failure_and_exit
               ~code:"CHECKPOINT_FILE_ERROR"
               ~message:"Could not read bounded checkpoint files."
           | Ok summary_input, Ok next_input ->
             (match
                Sandwalk_core.Checkpoint.create
                  ~summary:(Sandwalk_runtime.File_input.content summary_input)
                  ~next:(Sandwalk_runtime.File_input.content next_input)
              with
              | Error error ->
                print_failure_and_exit
                  ~code:"INVALID_CHECKPOINT"
                  ~message:(Sandwalk_core.Checkpoint.Error.message error)
              | Ok checkpoint ->
                let file_argument input =
                  `Assoc
                    [ "path", `String (Sandwalk_runtime.File_input.path input)
                    ; "size", `Int (Sandwalk_runtime.File_input.size input)
                    ; ( "hash"
                      , `Assoc
                          [ "algorithm", `String "md5"
                          ; ( "value"
                            , `String (Sandwalk_runtime.File_input.md5 input) )
                          ] )
                    ]
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; "claim", `String claim_text
                    ; "summary_file", file_argument summary_input
                    ; "next_file", file_argument next_input
                    ]
                in
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~phase
                      ~state_changes
                      ?step
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"step checkpoint"
                       ~arguments
                       ~phase
                       ~claim:claim_text
                       ?step
                       ~consumed_references:[ claim_text ]
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit
                      ?step
                      ?(state_changes = [])
                      ~code
                      ~message
                      ()
                  =
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Failed
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "researching")
                      ~state_changes
                      ?step
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~phase:(Some "researching")
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind saved =
                     In_thread.run (fun () ->
                       Sandwalk_store.save_checkpoint
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~claim_id
                         ~checkpoint
                         ~summary_path:
                           (Sandwalk_runtime.File_input.path summary_input)
                         ~summary_md5:
                           (Sandwalk_runtime.File_input.md5 summary_input)
                         ~summary_size:
                           (Sandwalk_runtime.File_input.size summary_input)
                         ~next_path:(Sandwalk_runtime.File_input.path next_input)
                         ~next_md5:(Sandwalk_runtime.File_input.md5 next_input)
                         ~next_size:(Sandwalk_runtime.File_input.size next_input)
                         ~now:(Sandwalk_runtime.timestamp_utc started_at)
                         ())
                   in
                   (match saved with
                    | Error error ->
                      let code, message = claim_error error in
                      fail_with_audit ~code ~message ()
                    | Ok saved ->
                      let step_key =
                        Sandwalk_store.Save_checkpoint_result.step_key saved
                      in
                      let checkpoint_number =
                        Sandwalk_store.Save_checkpoint_result.checkpoint_number
                          saved
                      in
                      let state_changes =
                        [ `Assoc
                            [ ( "entity"
                              , `String
                                  ("step."
                                   ^ Sandwalk_core.Plan_step.Key.to_string step_key
                                   ^ ".checkpoint") )
                            ; "from", `Null
                            ; "to", `Int checkpoint_number
                            ]
                        ]
                      in
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase:(Some "researching")
                          ~step:
                            (Sandwalk_core.Plan_step.Key.to_string step_key)
                          ~state_changes
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let result =
                           `Assoc
                             [ ( "step"
                               , `String
                                   (Sandwalk_core.Plan_step.Key.to_string
                                      step_key) )
                             ; "checkpoint", `Int checkpoint_number
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let search_error = function
  | Sandwalk_store.Error.Search_wrong_phase phase ->
    "SEARCH_NOT_ALLOWED", phase_error_message "Search" phase
  | Search_requires_claim ->
    "SEARCH_REQUIRES_CLAIM", "Research search requires an active claim."
  | Hit_id_collision ->
    "HIT_ID_COLLISION", "Could not allocate unique search-hit references."
  | error -> claim_error error
;;

let fetch_error = function
  | Sandwalk_store.Error.Hit_not_found reference ->
    "HIT_NOT_FOUND", sprintf "Search hit %S does not exist." reference
  | Hit_not_owned_by_claim reference ->
    "HIT_NOT_OWNED_BY_CLAIM",
    sprintf "Search hit %S belongs to another research step." reference
  | Fetch_wrong_phase phase ->
    "FETCH_NOT_ALLOWED", phase_error_message "Fetch" phase
  | Fetch_requires_claim ->
    "FETCH_REQUIRES_CLAIM", "Research fetch requires an active claim."
  | Snapshot_id_collision ->
    "SNAPSHOT_ID_COLLISION", "Could not allocate a unique snapshot reference."
  | error -> claim_error error
;;

let excerpt_store_error = function
  | Sandwalk_store.Error.Snapshot_not_found reference ->
    "SNAPSHOT_NOT_FOUND", sprintf "Snapshot %S does not exist." reference
  | Snapshot_not_owned_by_claim reference ->
    "SNAPSHOT_NOT_OWNED_BY_CLAIM",
    sprintf "Snapshot %S belongs to another research step." reference
  | Excerpt_wrong_phase phase ->
    "EXCERPT_NOT_ALLOWED", phase_error_message "Excerpt creation" phase
  | Excerpt_requires_claim ->
    "EXCERPT_REQUIRES_CLAIM", "Research excerpt creation requires an active claim."
  | Excerpt_id_collision ->
    "EXCERPT_ID_COLLISION", "Could not allocate a unique excerpt reference."
  | error -> fetch_error error
;;

let snapshot_promotion_error = function
  | Sandwalk_store.Error.Snapshot_not_found reference ->
    "SNAPSHOT_NOT_FOUND", sprintf "Snapshot %S does not exist." reference
  | Snapshot_promotion_wrong_phase phase ->
    "SNAPSHOT_PROMOTION_NOT_ALLOWED",
    phase_error_message "Snapshot promotion" phase
  | Snapshot_promotion_conflict reference ->
    "SNAPSHOT_PROMOTION_CONFLICT",
    sprintf "Snapshot %S already belongs to another plan step." reference
  | error -> claim_error error
;;

let excerpt_selection_error = function
  | Sandwalk_core.Excerpt.Empty_document ->
    "EMPTY_SNAPSHOT", "Snapshot document is empty."
  | Empty_excerpt -> "EMPTY_EXCERPT", "Excerpt text must not be empty."
  | Invalid_line_range ->
    "INVALID_LINE_RANGE", "Line range must identify existing inclusive lines."
  | Text_not_found ->
    "EXCERPT_TEXT_NOT_FOUND", "Excerpt text does not occur in the snapshot."
  | Ambiguous_text count ->
    ( "AMBIGUOUS_EXCERPT_TEXT"
    , sprintf "Excerpt text occurs %d times; specify --occurrence." count )
  | Invalid_occurrence occurrence ->
    "INVALID_OCCURRENCE", sprintf "Occurrence %d does not exist." occurrence
  | Too_large size ->
    ( "EXCERPT_TOO_LARGE"
    , sprintf
        "Excerpt is %d bytes; maximum size is %d bytes."
        size
        Sandwalk_core.Excerpt.maximum_bytes )
;;

let is_youtube_url url =
  List.exists
    [ "https://www.youtube.com/"
    ; "http://www.youtube.com/"
    ; "https://youtube.com/"
    ; "http://youtube.com/"
    ; "https://m.youtube.com/"
    ; "http://m.youtube.com/"
    ; "https://youtu.be/"
    ; "http://youtu.be/"
    ]
    ~f:(fun prefix -> String.is_prefix url ~prefix)
;;

let fetch_command =
  Async.Command.async
    ~summary:"Fetch one owned search hit into an immutable snapshot."
    (let%map_open.Command hit_text = anon ("HIT" %: string)
     and slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and adapter =
       flag
         "--adapter"
         (optional string)
         ~doc:"PATH Fetch adapter executable"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text, Sandwalk_core.Hit_id.of_string hit_text
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_HIT"
           ~message:"Search-hit reference is invalid."
       | Ok slug, Some hit_id ->
         let claim_id =
           match claim_text with
           | None -> Ok None
           | Some value ->
             Sandwalk_core.Claim_id.of_string value
             |> Result.of_option ~error:"Claim identifier is invalid."
             |> Result.map ~f:Option.some
         in
         (match claim_id with
          | Error message ->
            print_failure_and_exit ~code:"INVALID_CLAIM" ~message
          | Ok claim_id ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
            in
            let%bind database_exists =
              Async.Sys.file_exists_exn
                (Sandwalk_runtime.Workspace.database_path workspace)
            in
            if not database_exists
            then
              print_failure_and_exit
                ~code:"WORKSPACE_NOT_FOUND"
                ~message:"Workspace does not exist."
            else (
              let%bind hit =
                In_thread.run (fun () ->
                  Sandwalk_store.hit_for_fetch
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~hit_id
                    ())
              in
              match hit with
              | Error error ->
                let code, message = fetch_error error in
                print_failure_and_exit ~code ~message
              | Ok hit ->
                let url = Sandwalk_store.Hit_for_fetch.url hit in
                let adapter =
                  Option.value
                    adapter
                    ~default:
                      (if String.is_prefix url ~prefix:"file://"
                       then "sandwalk-fetch-file"
                       else if is_youtube_url url
                       then "sandwalk-fetch-youtube"
                       else "sandwalk-fetch-curl-pandoc")
                in
                let%bind status =
                  In_thread.run (fun () ->
                    Sandwalk_store.read_status
                      ~database_path:
                        (Sandwalk_runtime.Workspace.database_path workspace)
                      ~expected_slug:slug
                      ())
                in
                (match status with
                 | Error error ->
                   let code, message = status_error error in
                   print_failure_and_exit ~code ~message
                 | Ok status
                   when Sandwalk_core.Phase.equal
                          (Sandwalk_store.Workspace_status.phase status)
                          Sandwalk_core.Phase.Researching
                        && Option.is_none claim_id ->
                   print_failure_and_exit
                     ~code:"FETCH_REQUIRES_CLAIM"
                     ~message:"Research fetch requires an active claim."
                 | Ok _ ->
                   let started_at = Time_float_unix.now () in
                   let%bind invocation_id, snapshot_id =
                     Deferred.both
                       (In_thread.run (fun () ->
                          Sandwalk_runtime.invocation_id ~now:started_at))
                       (In_thread.run Sandwalk_runtime.snapshot_id)
                   in
                   let temporary_path =
                     Sandwalk_runtime.Workspace.temporary_fetch_path
                       workspace
                       ~invocation_id
                   in
                   let snapshot_path =
                     Sandwalk_runtime.Workspace.snapshot_path workspace snapshot_id
                   in
                   let arguments =
                     `Assoc
                       [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                       ; "directory_prefix", `String directory_prefix
                       ; "hit", `String hit_text
                       ; "adapter", `String adapter
                       ; ( "claim"
                         , Option.value_map
                             claim_text
                             ~default:`Null
                             ~f:(fun value -> `String value) )
                       ]
                   in
                   let append_event
                         ~kind
                         ~timestamp
                         ~phase
                         ~state_changes
                         ?created_references
                         ?duration_ms
                         ?outcome
                         ?error_code
                         ()
                     =
                     Sandwalk_runtime.Audit.append
                       ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                       (Sandwalk_protocol.Audit_event.create
                          ~invocation_id
                          ~timestamp
                          ~kind
                          ~command:"fetch"
                          ~arguments
                          ~phase
                          ?claim:claim_text
                          ~raw_argv:(Sys.get_argv () |> Array.to_list)
                          ~state_changes
                          ~consumed_references:
                            (hit_text :: Option.to_list claim_text)
                          ?created_references
                          ?duration_ms
                          ?outcome
                          ?error_code
                          ())
                   in
                   let fail_with_audit ~code ~message =
                     let finished_at = Time_float_unix.now () in
                     let duration_ms =
                       Time_float.diff finished_at started_at
                       |> Time_float.Span.to_ms
                       |> Float.iround_nearest_exn
                     in
                     let%bind logged =
                       append_event
                         ~kind:`Failed
                         ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                         ~phase:None
                         ~state_changes:[]
                         ~duration_ms
                         ~outcome:"failure"
                         ~error_code:code
                         ()
                     in
                     match logged with
                     | Error _ ->
                       print_failure_and_exit
                         ~code:"AUDIT_LOG_ERROR"
                         ~message:"Could not append workspace audit log."
                     | Ok () -> print_failure_and_exit ~code ~message
                   in
                   let%bind started =
                     append_event
                       ~kind:`Started
                       ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                       ~phase:None
                       ~state_changes:[]
                       ()
                   in
                   (match started with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let%bind () =
                        Unix.mkdir ~p:() (Filename.dirname snapshot_path)
                      in
                      let%bind () = Unix.mkdir ~p:() temporary_path in
                      let request =
                        Sandwalk_protocol.Fetch_adapter.request
                          ?source_root:
                            (Sandwalk_store.Hit_for_fetch.source_root hit)
                          ~url
                          ~output_directory:temporary_path
                          ()
                      in
                      let%bind adapter_output =
                        Sandwalk_runtime.Adapter.run_json
                          ~executable:adapter
                          ~request
                          ~timeout:
                            (Time_float.Span.of_sec
                               (if String.is_prefix url ~prefix:"file://"
                                   || is_youtube_url url
                                   || List.mem
                                        [ "sandwalk-fetch-curl-pandoc"
                                        ; "curl-pandoc-fetch"
                                        ]
                                        (Filename.basename adapter)
                                        ~equal:String.equal
                                then 900.
                                else 120.))
                          ~maximum_output_bytes:65_536
                      in
                      (match adapter_output with
                       | Error _ ->
                         fail_with_audit
                           ~code:"FETCH_ADAPTER_FAILED"
                           ~message:"Fetch adapter failed."
                       | Ok _ ->
                         let manifest_path =
                           Filename.concat temporary_path "manifest.json"
                         in
                         let%bind manifest_input =
                           Sandwalk_runtime.File_input.read
                             ~path:manifest_path
                             ~maximum_bytes:262_144
                         in
                         (match manifest_input with
                          | Error _ ->
                            fail_with_audit
                              ~code:"FETCH_ARTIFACT_ERROR"
                              ~message:"Fetch adapter omitted its manifest."
                          | Ok manifest_input ->
                            let manifest_json =
                              Sandwalk_runtime.File_input.content manifest_input
                            in
                            let decoded =
                              try
                                manifest_json
                                |> Yojson.Safe.from_string
                                |> Sandwalk_protocol.Fetch_adapter.manifest
                              with
                              | _ ->
                                Error
                                  Sandwalk_protocol.Fetch_adapter.Invalid_manifest
                            in
                            (match decoded with
                             | Error _ ->
                               fail_with_audit
                                 ~code:"FETCH_PROTOCOL_ERROR"
                                 ~message:"Fetch manifest is invalid."
                             | Ok manifest ->
                              let document_artifact =
                                Sandwalk_protocol.Fetch_adapter.document_artifact
                                  manifest
                              in
                              let document_path =
                                Filename.concat
                                  temporary_path
                                  document_artifact
                              in
                              let%bind document_input =
                                Sandwalk_runtime.File_input.read
                                  ~path:document_path
                                  ~maximum_bytes:52_428_800
                              in
                              (match document_input with
                               | Error _ ->
                                fail_with_audit
                                  ~code:"FETCH_ARTIFACT_ERROR"
                                  ~message:
                                    "Fetch adapter omitted its declared primary \
                                     document."
                               | Ok document_input ->
                                if
                                  Sandwalk_runtime.File_input.size document_input
                                  = 0
                                then
                                  fail_with_audit
                                    ~code:"FETCH_ARTIFACT_ERROR"
                                    ~message:"Fetched primary document is empty."
                                else (
                                let%bind structure_valid =
                                  match
                                    Sandwalk_protocol.Fetch_adapter
                                    .structure_artifact
                                      manifest
                                  with
                                  | None -> return true
                                  | Some artifact ->
                                    let%map input =
                                      Sandwalk_runtime.File_input.read
                                        ~path:
                                          (Filename.concat
                                             temporary_path
                                             artifact)
                                        ~maximum_bytes:104_857_600
                                    in
                                    (match input with
                                     | Error _ -> false
                                     | Ok input ->
                                       (try
                                          ignore
                                            (Sandwalk_runtime.File_input.content
                                               input
                                             |> Yojson.Safe.from_string
                                             : Yojson.Safe.t);
                                          Sandwalk_runtime.File_input.size input
                                          > 0
                                        with
                                        | _ -> false))
                                in
                                if not structure_valid
                                then
                                  fail_with_audit
                                    ~code:"FETCH_ARTIFACT_ERROR"
                                    ~message:
                                      "Fetch adapter returned an invalid \
                                       structured document artifact."
                                else (
                                  let%bind published =
                                    Deferred.Or_error.try_with (fun () ->
                                      Unix.rename
                                        ~src:temporary_path
                                        ~dst:snapshot_path)
                                  in
                                  match published with
                                  | Error _ ->
                                   fail_with_audit
                                     ~code:"WORKSPACE_IO_ERROR"
                                     ~message:
                                       "Could not publish immutable snapshot."
                                  | Ok () ->
                                   let persisted_at = Time_float_unix.now () in
                                   let%bind persisted =
                                     In_thread.run (fun () ->
                                       Sandwalk_store.record_snapshot
                                         ~database_path:
                                           (Sandwalk_runtime.Workspace.database_path
                                              workspace)
                                         ~expected_slug:slug
                                         ~claim_id
                                         ~hit_id
                                         ~snapshot_id
                                         ~artifact_path:snapshot_path
                                         ~document_artifact
                                         ~document_media_type:
                                           (Sandwalk_protocol.Fetch_adapter
                                            .document_media_type
                                              manifest)
                                         ~final_url:
                                           (Sandwalk_protocol.Fetch_adapter.final_url
                                              manifest)
                                         ~input_sha256:
                                           (Sandwalk_protocol.Fetch_adapter
                                            .input_sha256
                                              manifest)
                                         ~document_sha256:
                                           (Sandwalk_protocol.Fetch_adapter
                                            .document_sha256
                                              manifest)
                                         ~manifest_json
                                         ~now:
                                           (Sandwalk_runtime.timestamp_utc
                                              persisted_at)
                                         ())
                                   in
                                   (match persisted with
                                    | Error error ->
                                      let code, message = fetch_error error in
                                      fail_with_audit ~code ~message
                                    | Ok persisted ->
                                      let reference =
                                        Sandwalk_core.Snapshot_id.to_string
                                          snapshot_id
                                      in
                                      let phase =
                                        Option.value_map
                                          (Sandwalk_store.Record_snapshot_result
                                           .step_key
                                             persisted)
                                          ~default:"reconnaissance"
                                          ~f:(Fn.const "researching")
                                      in
                                      let finished_at = Time_float_unix.now () in
                                      let duration_ms =
                                        Time_float.diff finished_at started_at
                                        |> Time_float.Span.to_ms
                                        |> Float.iround_nearest_exn
                                      in
                                      let%bind logged =
                                        append_event
                                          ~kind:`Finished
                                          ~timestamp:
                                            (Sandwalk_runtime.timestamp_utc
                                               finished_at)
                                          ~phase:(Some phase)
                                          ~state_changes:
                                            [ `Assoc
                                                [ ( "entity"
                                                  , `String "snapshot" )
                                                ; "from", `Null
                                                ; "to", `String reference
                                                ]
                                            ]
                                          ~created_references:[ reference ]
                                          ~duration_ms
                                          ~outcome:"success"
                                          ()
                                      in
                                      (match logged with
                                       | Error _ ->
                                         print_failure_and_exit
                                           ~code:"AUDIT_LOG_ERROR"
                                           ~message:
                                             "Could not append workspace audit log."
                                       | Ok () ->
                                         let result =
                                           `Assoc
                                             [ "snapshot", `String reference
                                             ; ( "document_path"
                                               , `String
                                                   (Filename.concat
                                                      snapshot_path
                                                      document_artifact) )
                                             ; ( "document_media_type"
                                               , `String
                                                   (Sandwalk_protocol
                                                    .Fetch_adapter
                                                    .document_media_type
                                                      manifest) )
                                             ]
                                         in
                                         Sandwalk_protocol.Envelope.success
                                           ~result
                                           ()
                                         |> Sandwalk_protocol.Envelope.render
                                         |> print_endline;
                                         Deferred.unit)))))))))))))
;;

let snapshot_promote_command =
  Async.Command.async
    ~summary:"Associate an immutable reconnaissance snapshot with a claimed step."
    (let%map_open.Command snapshot_text = anon ("SNAPSHOT" %: string)
     and slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Snapshot_id.of_string snapshot_text,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_SNAPSHOT"
           ~message:"Snapshot reference is invalid."
       | _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some snapshot_id, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let arguments =
           `Assoc
             [ "slug", `String (Sandwalk_core.Slug.to_string slug)
             ; "directory_prefix", `String directory_prefix
             ; "snapshot", `String snapshot_text
             ; "claim", `String claim_text
             ]
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?step
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"snapshot promote"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ~claim:claim_text
                  ?step
                  ~consumed_references:[ snapshot_text ]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ?step ~code ~message () =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind logged =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase:(Some "researching")
                 ~state_changes:[]
                 ?step
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             match logged with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () -> print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ~state_changes:[]
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind promoted =
               In_thread.run (fun () ->
                 Sandwalk_store.promote_snapshot
                   ~database_path:
                     (Sandwalk_runtime.Workspace.database_path workspace)
                   ~expected_slug:slug
                   ~claim_id
                   ~snapshot_id
                   ~now:(Sandwalk_runtime.timestamp_utc started_at)
                   ())
             in
             (match promoted with
              | Error error ->
                let code, message = snapshot_promotion_error error in
                fail_with_audit ~code ~message ()
              | Ok promoted ->
                let step_key =
                  Sandwalk_store.Promote_snapshot_result.step_key promoted
                in
                let step = Sandwalk_core.Plan_step.Key.to_string step_key in
                let did_promote =
                  Sandwalk_store.Promote_snapshot_result.promoted promoted
                in
                let state_changes =
                  (if did_promote
                   then
                     [ `Assoc
                         [ "entity", `String "snapshot.promotion"
                         ; "from", `Null
                         ; "to", `String step
                         ]
                     ]
                   else [])
                in
                let finished_at = Time_float_unix.now () in
                let duration_ms =
                  Time_float.diff finished_at started_at
                  |> Time_float.Span.to_ms
                  |> Float.iround_nearest_exn
                in
                let%bind logged =
                  append_event
                    ~kind:`Finished
                    ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                    ~phase:(Some "researching")
                    ~step
                    ~state_changes
                    ~duration_ms
                    ~outcome:"success"
                    ()
                in
                (match logged with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let result =
                     `Assoc
                       [ "snapshot", `String snapshot_text
                       ; "step", `String step
                       ; "promoted", `Bool did_promote
                       ]
                   in
                   Sandwalk_protocol.Envelope.success ~result ()
                   |> Sandwalk_protocol.Envelope.render
                   |> print_endline;
                   Deferred.unit))))
;;

let snapshot_command =
  Async.Command.group
    ~summary:"Manage immutable snapshot ownership."
    [ "promote", snapshot_promote_command ]
;;

let excerpt_create_command =
  Async.Command.async
    ~summary:"Create an exact excerpt from an immutable snapshot."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and snapshot_text =
       flag "--snapshot" (required string) ~doc:"SNAPSHOT Immutable snapshot"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and lines_text =
       flag "--lines" (optional string) ~doc:"FIRST:LAST Inclusive line range"
     and text_path =
       flag "--text-file" (optional string) ~doc:"PATH Exact excerpt text"
     and occurrence =
       flag "--occurrence" (optional int) ~doc:"N One-based text occurrence"
     in
     fun () ->
       let selection =
         match lines_text, text_path, occurrence with
         | Some range, None, None ->
           (match String.lsplit2 range ~on:':' with
            | Some (first, last) ->
              (match Int.of_string_opt first, Int.of_string_opt last with
               | Some first, Some last -> Ok (`Lines (first, last))
               | _ -> Error ())
            | None -> Error ())
         | None, Some path, occurrence -> Ok (`Text (path, occurrence))
         | _ -> Error ()
       in
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Snapshot_id.of_string snapshot_text,
         selection
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_SNAPSHOT"
           ~message:"Snapshot reference is invalid."
       | _, _, Error () ->
         print_failure_and_exit
           ~code:"INVALID_EXCERPT_SELECTOR"
           ~message:
             "Specify exactly one of --lines or --text-file; occurrence applies to text."
       | Ok slug, Some snapshot_id, Ok selection ->
         let claim_id =
           match claim_text with
           | None -> Ok None
           | Some value ->
             Sandwalk_core.Claim_id.of_string value
             |> Result.of_option ~error:"Claim identifier is invalid."
             |> Result.map ~f:Option.some
         in
         (match claim_id with
          | Error message ->
            print_failure_and_exit ~code:"INVALID_CLAIM" ~message
          | Ok claim_id ->
            let directory_prefix =
              Sandwalk_runtime.resolve_directory_prefix
                ~command_line:directory_prefix
            in
            let workspace =
              Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
            in
            let%bind database_exists =
              Async.Sys.file_exists_exn
                (Sandwalk_runtime.Workspace.database_path workspace)
            in
            if not database_exists
            then
              print_failure_and_exit
                ~code:"WORKSPACE_NOT_FOUND"
                ~message:"Workspace does not exist."
            else (
              let%bind snapshot =
                In_thread.run (fun () ->
                  Sandwalk_store.snapshot_for_excerpt
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~snapshot_id
                    ())
              in
              match snapshot with
              | Error error ->
                let code, message = excerpt_store_error error in
                print_failure_and_exit ~code ~message
              | Ok snapshot ->
                let document_path =
                  Filename.concat
                    (Sandwalk_store.Snapshot_for_excerpt.artifact_path snapshot)
                    (Sandwalk_store.Snapshot_for_excerpt.document_artifact
                       snapshot)
                in
                let%bind document_input =
                  Sandwalk_runtime.File_input.read
                    ~path:document_path
                    ~maximum_bytes:52_428_800
                in
                (match document_input with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"SNAPSHOT_ARTIFACT_ERROR"
                     ~message:"Could not read bounded snapshot document."
                 | Ok document_input ->
                   let%bind text_input =
                     match selection with
                     | `Lines _ -> Deferred.return (Ok None)
                     | `Text (path, _) ->
                       let%map input =
                         Sandwalk_runtime.File_input.read
                           ~path
                           ~maximum_bytes:Sandwalk_core.Excerpt.maximum_bytes
                       in
                       Result.map input ~f:Option.some
                   in
                   (match text_input with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"EXCERPT_FILE_ERROR"
                        ~message:"Could not read bounded excerpt text."
                    | Ok text_input ->
                      let selected =
                        match selection, text_input with
                        | `Lines (first, last), _ ->
                          Sandwalk_core.Excerpt.by_lines
                            (Sandwalk_runtime.File_input.content document_input)
                            ~first
                            ~last
                        | `Text (_, occurrence), Some input ->
                          Sandwalk_core.Excerpt.by_text
                            (Sandwalk_runtime.File_input.content document_input)
                            ~excerpt:
                              (Sandwalk_runtime.File_input.content input)
                            ~occurrence
                        | `Text _, None -> assert false
                      in
                      (match selected with
                       | Error error ->
                         let code, message = excerpt_selection_error error in
                         print_failure_and_exit ~code ~message
                       | Ok excerpt ->
                         let started_at = Time_float_unix.now () in
                         let%bind invocation_id, excerpt_id =
                           Deferred.both
                             (In_thread.run (fun () ->
                                Sandwalk_runtime.invocation_id ~now:started_at))
                             (In_thread.run Sandwalk_runtime.excerpt_id)
                         in
                         let artifact_path =
                           Sandwalk_runtime.Workspace.excerpt_path
                             workspace
                             excerpt_id
                         in
                         let file_argument input =
                           `Assoc
                             [ ( "path"
                               , `String
                                   (Sandwalk_runtime.File_input.path input) )
                             ; ( "size"
                               , `Int
                                   (Sandwalk_runtime.File_input.size input) )
                             ; ( "hash"
                               , `Assoc
                                   [ "algorithm", `String "md5"
                                   ; ( "value"
                                     , `String
                                         (Sandwalk_runtime.File_input.md5
                                            input) )
                                   ] )
                             ]
                         in
                         let selector_argument =
                           match selection, text_input with
                           | `Lines (first, last), _ ->
                             `Assoc
                               [ "lines", `String (sprintf "%d:%d" first last)
                               ]
                           | `Text (_, occurrence), Some input ->
                             `Assoc
                               [ "text_file", file_argument input
                               ; ( "occurrence"
                                 , Option.value_map
                                     occurrence
                                     ~default:`Null
                                     ~f:(fun value -> `Int value) )
                               ]
                           | `Text _, None -> assert false
                         in
                         let arguments =
                           `Assoc
                             [ ( "slug"
                               , `String (Sandwalk_core.Slug.to_string slug) )
                             ; "directory_prefix", `String directory_prefix
                             ; "snapshot", `String snapshot_text
                             ; ( "claim"
                               , Option.value_map
                                   claim_text
                                   ~default:`Null
                                   ~f:(fun value -> `String value) )
                             ; "selector", selector_argument
                             ]
                         in
                         let append_event
                               ~kind
                               ~timestamp
                               ~phase
                               ~state_changes
                               ?created_references
                               ?duration_ms
                               ?outcome
                               ?error_code
                               ()
                           =
                           Sandwalk_runtime.Audit.append
                             ~path:
                               (Sandwalk_runtime.Workspace.events_path
                                  workspace)
                             (Sandwalk_protocol.Audit_event.create
                                ~invocation_id
                                ~timestamp
                                ~kind
                                ~command:"excerpt create"
                                ~arguments
                                ~phase
                                ?claim:claim_text
                                ~raw_argv:(Sys.get_argv () |> Array.to_list)
                                ~state_changes
                                ~consumed_references:
                                  (snapshot_text :: Option.to_list claim_text)
                                ?created_references
                                ?duration_ms
                                ?outcome
                                ?error_code
                                ())
                         in
                         let fail_with_audit ~code ~message =
                           let finished_at = Time_float_unix.now () in
                           let duration_ms =
                             Time_float.diff finished_at started_at
                             |> Time_float.Span.to_ms
                             |> Float.iround_nearest_exn
                           in
                           let%bind logged =
                             append_event
                               ~kind:`Failed
                               ~timestamp:
                                 (Sandwalk_runtime.timestamp_utc finished_at)
                               ~phase:None
                               ~state_changes:[]
                               ~duration_ms
                               ~outcome:"failure"
                               ~error_code:code
                               ()
                           in
                           match logged with
                           | Error _ ->
                             print_failure_and_exit
                               ~code:"AUDIT_LOG_ERROR"
                               ~message:
                                 "Could not append workspace audit log."
                           | Ok () -> print_failure_and_exit ~code ~message
                         in
                         let remove_candidate () =
                           let%map _ =
                             Monitor.try_with (fun () ->
                               Unix.unlink artifact_path)
                           in
                           ()
                         in
                         let%bind started =
                           append_event
                             ~kind:`Started
                             ~timestamp:
                               (Sandwalk_runtime.timestamp_utc started_at)
                             ~phase:None
                             ~state_changes:[]
                             ()
                         in
                         (match started with
                          | Error _ ->
                            print_failure_and_exit
                              ~code:"AUDIT_LOG_ERROR"
                              ~message:"Could not append workspace audit log."
                          | Ok () ->
                            let%bind () =
                              Unix.mkdir
                                ~p:()
                                (Filename.dirname artifact_path)
                            in
                            let%bind written =
                              Sandwalk_runtime.Atomic_file.write_exclusive
                                ~path:artifact_path
                                (Sandwalk_core.Excerpt.text excerpt)
                            in
                            (match written with
                             | Error _ ->
                               fail_with_audit
                                 ~code:"WORKSPACE_IO_ERROR"
                                 ~message:"Could not publish excerpt artifact."
                             | Ok () ->
                               let persisted_at = Time_float_unix.now () in
                               let%bind persisted =
                                 In_thread.run (fun () ->
                                   Sandwalk_store.record_excerpt
                                     ~database_path:
                                       (Sandwalk_runtime.Workspace.database_path
                                          workspace)
                                     ~expected_slug:slug
                                     ~claim_id
                                     ~snapshot_id
                                     ~excerpt_id
                                     ~artifact_path
                                     ~markdown_sha256:
                                       (Sandwalk_store.Snapshot_for_excerpt
                                        .document_sha256
                                          snapshot)
                                     ~line_start:
                                       (Sandwalk_core.Excerpt.line_start excerpt)
                                     ~line_end:
                                       (Sandwalk_core.Excerpt.line_end excerpt)
                                     ~byte_start:
                                       (Sandwalk_core.Excerpt.byte_start excerpt)
                                     ~byte_end:
                                       (Sandwalk_core.Excerpt.byte_end excerpt)
                                     ~excerpt_md5:
                                       (Md5.digest_string
                                          (Sandwalk_core.Excerpt.text excerpt)
                                        |> Md5.to_hex)
                                     ~excerpt_size:
                                       (String.length
                                          (Sandwalk_core.Excerpt.text excerpt))
                                     ~now:
                                       (Sandwalk_runtime.timestamp_utc
                                          persisted_at)
                                     ())
                               in
                               (match persisted with
                                | Error error ->
                                  let%bind () = remove_candidate () in
                                  let code, message =
                                    excerpt_store_error error
                                  in
                                  fail_with_audit ~code ~message
                                | Ok persisted ->
                                  let stored_id =
                                    Sandwalk_store.Record_excerpt_result
                                    .excerpt_id
                                      persisted
                                  in
                                  let created =
                                    Sandwalk_store.Record_excerpt_result.created
                                      persisted
                                  in
                                  let%bind () =
                                    if created
                                    then Deferred.unit
                                    else remove_candidate ()
                                  in
                                  let reference =
                                    Sandwalk_core.Excerpt_id.to_string stored_id
                                  in
                                  let phase =
                                    Option.value_map
                                      (Sandwalk_store.Record_excerpt_result
                                       .step_key
                                         persisted)
                                      ~default:"reconnaissance"
                                      ~f:(Fn.const "researching")
                                  in
                                  let finished_at =
                                    Time_float_unix.now ()
                                  in
                                  let duration_ms =
                                    Time_float.diff finished_at started_at
                                    |> Time_float.Span.to_ms
                                    |> Float.iround_nearest_exn
                                  in
                                  let%bind logged =
                                    append_event
                                      ~kind:`Finished
                                      ~timestamp:
                                        (Sandwalk_runtime.timestamp_utc
                                           finished_at)
                                      ~phase:(Some phase)
                                      ~state_changes:
                                        (if created
                                         then
                                           [ `Assoc
                                               [ ( "entity"
                                                 , `String "excerpt" )
                                               ; "from", `Null
                                               ; "to", `String reference
                                               ]
                                           ]
                                         else [])
                                      ~created_references:
                                        (if created then [ reference ] else [])
                                      ~duration_ms
                                      ~outcome:"success"
                                      ()
                                  in
                                  (match logged with
                                   | Error _ ->
                                     print_failure_and_exit
                                       ~code:"AUDIT_LOG_ERROR"
                                       ~message:
                                         "Could not append workspace audit log."
                                   | Ok () ->
                                     let result =
                                       `Assoc
                                         [ "excerpt", `String reference
                                         ; "created", `Bool created
                                         ; ( "lines"
                                           , `String
                                               (sprintf
                                                  "%d:%d"
                                                  (Sandwalk_core.Excerpt
                                                   .line_start
                                                     excerpt)
                                                  (Sandwalk_core.Excerpt
                                                   .line_end
                                                     excerpt)) )
                                         ; ( "bytes"
                                           , `String
                                               (sprintf
                                                  "%d:%d"
                                                  (Sandwalk_core.Excerpt
                                                   .byte_start
                                                     excerpt)
                                                  (Sandwalk_core.Excerpt
                                                   .byte_end
                                                     excerpt)) )
                                         ]
                                     in
                                     Sandwalk_protocol.Envelope.success
                                       ~result
                                       ()
                                     |> Sandwalk_protocol.Envelope.render
                                     |> print_endline;
                                     Deferred.unit))))))))))
;;

let excerpt_command =
  Async.Command.group
    ~summary:"Create and manage exact snapshot excerpts."
    [ "create", excerpt_create_command ]
;;

let search_command =
  Async.Command.async
    ~summary:"Run a bounded search adapter and persist provenance-owned hits."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag
         "--directory-prefix"
         (optional string)
         ~doc:"PATH Parent directory for Sandwalk workspaces"
     and query =
       flag "--query" (required string) ~doc:"QUERY Search query"
     and source_root =
       flag
         "--source-root"
         (optional string)
         ~doc:"PATH Restrict local-document search to this directory"
     and claim_text =
       flag "--claim" (optional string) ~doc:"CLAIM Active research claim"
     and limit =
       flag
         "--limit"
         (optional_with_default 10 int)
         ~doc:"N Maximum results from 1 to 25"
     and adapter =
       flag
         "--adapter"
         (optional string)
         ~doc:"PATH Search adapter executable"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         if String.is_empty query || String.length query > 2_048
         then
           print_failure_and_exit
             ~code:"INVALID_QUERY"
             ~message:"Search query must contain between 1 and 2048 bytes."
         else if limit < 1 || limit > 25
         then
           print_failure_and_exit
             ~code:"INVALID_SEARCH_LIMIT"
             ~message:"Search limit must be between 1 and 25."
         else if
           Option.exists source_root ~f:(fun root ->
             String.is_empty root || String.length root > 4_096)
         then
           print_failure_and_exit
             ~code:"INVALID_SOURCE_ROOT"
             ~message:"Source root must contain between 1 and 4096 bytes."
         else (
           let source_root =
             Option.map source_root ~f:(fun root ->
               if Filename.is_absolute root
               then root
               else Filename.concat (Sys_unix.getcwd ()) root)
           in
           let adapter =
             Option.value
               adapter
               ~default:
                 (if Option.is_some source_root
                  then "sandwalk-search-ugrep"
                  else "sandwalk-search-ddgr")
           in
           let claim_id =
             match claim_text with
             | None -> Ok None
             | Some value ->
               Sandwalk_core.Claim_id.of_string value
               |> Result.of_option ~error:"Claim identifier is invalid."
               |> Result.map ~f:Option.some
           in
           match claim_id with
           | Error message ->
             print_failure_and_exit ~code:"INVALID_CLAIM" ~message
           | Ok claim_id ->
             let directory_prefix =
               Sandwalk_runtime.resolve_directory_prefix
                 ~command_line:directory_prefix
             in
             let workspace =
               Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
             in
             let%bind database_exists =
               Async.Sys.file_exists_exn
                 (Sandwalk_runtime.Workspace.database_path workspace)
             in
             if not database_exists
             then
               print_failure_and_exit
                 ~code:"WORKSPACE_NOT_FOUND"
                 ~message:"Workspace does not exist."
             else (
               let%bind status =
                 In_thread.run (fun () ->
                   Sandwalk_store.read_status
                     ~database_path:
                       (Sandwalk_runtime.Workspace.database_path workspace)
                     ~expected_slug:slug
                     ())
               in
               match status with
               | Error error ->
                 let code, message = status_error error in
                 print_failure_and_exit ~code ~message
               | Ok status
                 when Sandwalk_core.Phase.equal
                        (Sandwalk_store.Workspace_status.phase status)
                        Sandwalk_core.Phase.Researching
                      && Option.is_none claim_id ->
                 print_failure_and_exit
                   ~code:"SEARCH_REQUIRES_CLAIM"
                   ~message:"Research search requires an active claim."
               | Ok _ ->
                 let arguments =
                   `Assoc
                     [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                     ; "directory_prefix", `String directory_prefix
                     ; "query", `String query
                     ; "limit", `Int limit
                     ; "adapter", `String adapter
                     ; ( "source_root"
                       , Option.value_map
                           source_root
                           ~default:`Null
                           ~f:(fun value -> `String value) )
                     ; ( "claim"
                       , Option.value_map
                           claim_text
                           ~default:`Null
                           ~f:(fun value -> `String value) )
                     ]
                 in
                 let started_at = Time_float_unix.now () in
                 let%bind invocation_id =
                   In_thread.run (fun () ->
                     Sandwalk_runtime.invocation_id ~now:started_at)
                 in
                 let append_event
                       ~kind
                       ~timestamp
                       ~phase
                       ~state_changes
                       ?created_references
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ()
                   =
                   Sandwalk_runtime.Audit.append
                     ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                     (Sandwalk_protocol.Audit_event.create
                        ~invocation_id
                        ~timestamp
                        ~kind
                        ~command:"search"
                        ~arguments
                        ~phase
                        ?claim:claim_text
                        ~raw_argv:(Sys.get_argv () |> Array.to_list)
                        ~state_changes
                        ~consumed_references:
                          (Option.to_list claim_text)
                        ?created_references
                        ?duration_ms
                        ?outcome
                        ?error_code
                        ())
                 in
                 let fail_with_audit ~code ~message =
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Failed
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:None
                       ~state_changes:[]
                       ~duration_ms
                       ~outcome:"failure"
                       ~error_code:code
                       ()
                   in
                   match logged with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () -> print_failure_and_exit ~code ~message
                 in
                 let%bind started =
                   append_event
                     ~kind:`Started
                     ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                     ~phase:None
                     ~state_changes:[]
                     ()
                 in
                 (match started with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let request =
                      Sandwalk_protocol.Search_adapter.request
                        ?source_root
                        ~query
                        ~limit
                        ()
                    in
                    let%bind adapter_output =
                      Sandwalk_runtime.Adapter.run_json
                        ~executable:adapter
                        ~request
                        ~timeout:(Time_float.Span.of_sec 30.)
                        ~maximum_output_bytes:262_144
                    in
                    (match adapter_output with
                     | Error _ ->
                       fail_with_audit
                         ~code:"SEARCH_ADAPTER_FAILED"
                         ~message:"Search adapter failed."
                     | Ok adapter_output ->
                       (match
                          Sandwalk_protocol.Search_adapter.results adapter_output
                        with
                        | Error _ ->
                          fail_with_audit
                            ~code:"SEARCH_PROTOCOL_ERROR"
                            ~message:"Search adapter returned an invalid response."
                        | Ok results ->
                          let%bind hit_ids =
                            In_thread.run (fun () ->
                              List.map results ~f:(fun _ ->
                                Sandwalk_runtime.hit_id ()))
                          in
                          let hits =
                            List.map2_exn hit_ids results ~f:(fun hit_id result ->
                              ( hit_id
                              , Sandwalk_protocol.Search_adapter.url result
                              , Sandwalk_protocol.Search_adapter.title result
                              , Sandwalk_protocol.Search_adapter.snippet result ))
                          in
                          let persisted_at = Time_float_unix.now () in
                          let%bind persisted =
                            In_thread.run (fun () ->
                              Sandwalk_store.record_search
                                ~database_path:
                                  (Sandwalk_runtime.Workspace.database_path
                                     workspace)
                                ~expected_slug:slug
                                ~claim_id
                                ~query
                                ~adapter
                                ~source_root
                                ~hits
                                ~now:
                                  (Sandwalk_runtime.timestamp_utc persisted_at)
                                ())
                          in
                          (match persisted with
                           | Error error ->
                             let code, message = search_error error in
                             fail_with_audit ~code ~message
                           | Ok persisted ->
                             let stored_hits =
                               Sandwalk_store.Record_search_result.hits persisted
                             in
                             let references =
                               List.map stored_hits ~f:(fun hit ->
                                 Sandwalk_store.Stored_hit.hit_id hit
                                 |> Sandwalk_core.Hit_id.to_string)
                             in
                             let phase =
                               Option.value_map
                                 (Sandwalk_store.Record_search_result.step_key
                                    persisted)
                                 ~default:"reconnaissance"
                                 ~f:(Fn.const "researching")
                             in
                             let state_changes =
                               [ `Assoc
                                   [ "entity", `String "search.hits"
                                   ; "from", `Int 0
                                   ; "to", `Int (List.length references)
                                   ]
                               ]
                             in
                             let finished_at = Time_float_unix.now () in
                             let duration_ms =
                               Time_float.diff finished_at started_at
                               |> Time_float.Span.to_ms
                               |> Float.iround_nearest_exn
                             in
                             let%bind logged =
                               append_event
                                 ~kind:`Finished
                                 ~timestamp:
                                   (Sandwalk_runtime.timestamp_utc finished_at)
                                 ~phase:(Some phase)
                                 ~state_changes
                                 ~created_references:references
                                 ~duration_ms
                                 ~outcome:"success"
                                 ()
                             in
                             (match logged with
                              | Error _ ->
                                print_failure_and_exit
                                  ~code:"AUDIT_LOG_ERROR"
                                  ~message:
                                    "Could not append workspace audit log."
                              | Ok () ->
                                let result =
                                  `Assoc
                                    [ "count", `Int (List.length references)
                                    ; ( "hits"
                                      , `List
                                          (List.map stored_hits ~f:(fun hit ->
                                             `Assoc
                                               [ ( "hit"
                                                 , `String
                                                     (Sandwalk_store.Stored_hit
                                                      .hit_id
                                                        hit
                                                      |> Sandwalk_core.Hit_id
                                                         .to_string) )
                                               ; ( "url"
                                                 , `String
                                                     (Sandwalk_store.Stored_hit
                                                      .url
                                                        hit) )
                                               ; ( "title"
                                                 , `String
                                                     (Sandwalk_store.Stored_hit
                                                      .title
                                                        hit) )
                                               ; ( "snippet"
                                                 , `String
                                                     (Sandwalk_store.Stored_hit
                                                      .snippet
                                                        hit) )
                                               ])) )
                                    ]
                                in
                                Sandwalk_protocol.Envelope.success ~result ()
                                |> Sandwalk_protocol.Envelope.render
                                |> print_endline;
                                Deferred.unit))))))))
;;

let finding_error = function
  | Sandwalk_store.Error.Finding_wrong_phase phase ->
    "FINDING_NOT_ALLOWED", phase_error_message "Finding mutation" phase
  | Finding_step_mismatch ->
    "FINDING_STEP_MISMATCH", "Active claim belongs to another plan step."
  | Finding_exists reference ->
    "FINDING_EXISTS", sprintf "Finding %S already exists." reference
  | Finding_not_found reference ->
    "FINDING_NOT_FOUND", sprintf "Finding %S does not exist." reference
  | Excerpt_not_found reference ->
    "EXCERPT_NOT_FOUND", sprintf "Excerpt %S does not exist." reference
  | Finding_excerpt_step_mismatch ->
    "EVIDENCE_STEP_MISMATCH", "Excerpt belongs to another plan step."
  | Excerpt_stale reference ->
    "EXCERPT_STALE", sprintf "Excerpt %S no longer matches its snapshot." reference
  | Finding_has_no_evidence reference ->
    "FINDING_HAS_NO_EVIDENCE",
    sprintf
      "Finding %S must have non-context evidence before sealing."
      reference
  | Finding_not_sealed reference ->
    "FINDING_NOT_SEALED", sprintf "Finding %S must be sealed before review." reference
  | Finding_review_conflict reference ->
    "FINDING_REVIEW_EXISTS",
    sprintf "Finding %S already has a different current review." reference
  | error -> claim_error error
;;

let complete_step_error = function
  | Sandwalk_store.Error.Step_has_no_findings step ->
    "STEP_HAS_NO_FINDINGS", sprintf "Step %S has no findings." step
  | Step_has_unreviewed_findings step ->
    "STEP_HAS_UNREVIEWED_FINDINGS",
    sprintf "Step %S has draft, sealed, or stale findings." step
  | Step_has_rejected_findings step ->
    "STEP_HAS_REJECTED_FINDINGS",
    sprintf "Step %S has unsupported or contradicted findings." step
  | error -> claim_error error
;;

let candidate_error = function
  | Sandwalk_store.Error.Candidate_not_found reference ->
    "CANDIDATE_NOT_FOUND", sprintf "Candidate %S does not exist." reference
  | Candidate_not_owned_by_claim reference ->
    "CANDIDATE_STEP_MISMATCH",
    sprintf "Candidate %S belongs to another plan step." reference
  | error -> claim_error error
;;

let repair_finding_error = function
  | Sandwalk_store.Error.Finding_repair_wrong_phase phase ->
    "FINDING_REPAIR_NOT_ALLOWED",
    phase_error_message "Finding repair" phase
  | Finding_repair_requires_completed_step step ->
    "FINDING_REPAIR_STEP_ACTIVE",
    sprintf "Step %S must be completed before repair." step
  | Finding_repair_has_completed_dependents reference ->
    "FINDING_REPAIR_DEPENDENT_COMPLETE",
    sprintf
      "Finding %S cannot be repaired after a dependent step completed."
      reference
  | error -> finding_error error
;;

let draft_error = function
  | Sandwalk_store.Error.Draft_wrong_phase phase ->
    "DRAFT_NOT_ALLOWED", phase_error_message "Writer-pack preparation" phase
  | Draft_gate_failed ->
    "DRAFT_GATE_FAILED", "Current reviewed findings do not pass the draft gate."
  | error -> status_error error
;;

let report_error = function
  | Sandwalk_store.Error.Report_wrong_phase phase ->
    "REPORT_NOT_ALLOWED", phase_error_message "Report submission" phase
  | Report_citation_invalid reference ->
    "REPORT_CITATION_INVALID",
    sprintf "Citation target %S is unknown, stale, or rejected." reference
  | Report_conflict ->
    "REPORT_CONFLICT", "A conflicting report revision already exists."
  | Report_review_wrong_phase phase ->
    "REPORT_REVIEW_NOT_ALLOWED", phase_error_message "Report review" phase
  | Report_revision_stale ->
    "REPORT_REVISION_STALE", "Report review does not target the current revision."
  | Report_review_incomplete ->
    "REPORT_REVIEW_INCOMPLETE", "Report review must cover every current block."
  | Report_block_stale ordinal ->
    "REPORT_BLOCK_STALE", sprintf "Report block %d hash is stale." ordinal
  | error -> status_error error
;;

let finalize_error = function
  | Sandwalk_store.Error.Finalize_wrong_phase phase ->
    "FINALIZE_NOT_ALLOWED", phase_error_message "Finalization" phase
  | Finalize_gate_failed ->
    "FINALIZE_GATE_FAILED", "Current report or block reviews are stale or rejected."
  | error -> status_error error
;;

let export_error = function
  | Sandwalk_store.Error.Export_wrong_phase phase ->
    "EXPORT_NOT_ALLOWED", phase_error_message "Export" phase
  | Export_not_finalized ->
    "EXPORT_NOT_FINALIZED", "Completed workspace has no finalization record."
  | error -> status_error error
;;

let gc_error = function
  | Sandwalk_store.Error.Gc_active_claims ->
    "GC_ACTIVE_CLAIMS", "Raw cleanup is blocked while claims are active."
  | Gc_no_plan -> "GC_NO_PLAN", "No unapplied raw cleanup plan exists."
  | Gc_plan_stale -> "GC_PLAN_STALE", "Raw cleanup plan is stale or modified."
  | error -> status_error error
;;

let report_block_preview text =
  let compact =
    text
    |> String.split_lines
    |> List.map ~f:String.strip
    |> String.concat ~sep:" "
    |> String.strip
  in
  if String.length compact <= 160
  then compact
  else String.prefix compact 157 ^ "..."
;;

let report_validation_error = function
  | Sandwalk_core.Report.Empty -> "EMPTY_REPORT", "Report must not be empty."
  | Too_large -> "REPORT_TOO_LARGE", "Report exceeds the 1 MiB bound."
  | Too_many_blocks count ->
    "REPORT_TOO_MANY_BLOCKS",
    sprintf "Report has %d blocks; maximum is 256." count
  | Block_too_large ordinal ->
    "REPORT_BLOCK_TOO_LARGE",
    sprintf "Report block %d exceeds the 16 KiB bound." ordinal
  | No_citations ->
    "REPORT_HAS_NO_CITATIONS", "Report must cite at least one reviewed finding."
  | Missing_citation (ordinal, text) ->
    ( "REPORT_BLOCK_UNCITED"
    , sprintf
        "Report block %d has no citation. Block preview: %S Blank lines separate \
         blocks; add a current [cite:step-key/finding-key] token to this prose \
         block."
        ordinal
        (report_block_preview text) )
  | Invalid_citation reference ->
    "REPORT_CITATION_SYNTAX", sprintf "Invalid citation token near %S." reference
;;

let finding_create_command =
  Async.Command.async
    ~summary:"Create a draft finding for one claimed plan step."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and step_text =
       flag "--step" (required string) ~doc:"STEP Plan-step key"
     and key_text =
       flag "--key" (required string) ~doc:"KEY Finding key"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     and claim_path =
       flag "--claim-file" (required string) ~doc:"PATH Finding statement"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Plan_step.Key.of_string step_text,
         Sandwalk_core.Finding_key.of_string key_text,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, Error _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_STEP"
           ~message:"Plan-step key is invalid."
       | _, _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_FINDING_KEY"
           ~message:"Finding key is invalid."
       | _, _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Ok step_key, Some finding_key, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:claim_path
               ~maximum_bytes:Sandwalk_core.Finding_claim.maximum_bytes
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"FINDING_FILE_ERROR"
               ~message:"Could not read bounded finding statement."
           | Ok input ->
             (match
                Sandwalk_core.Finding_claim.create
                  (Sandwalk_runtime.File_input.content input)
              with
              | Error Empty ->
                print_failure_and_exit
                  ~code:"EMPTY_FINDING"
                  ~message:"Finding statement must not be empty."
              | Error (Too_large _) ->
                print_failure_and_exit
                  ~code:"FINDING_TOO_LARGE"
                  ~message:"Finding statement exceeds 65,536 bytes."
              | Ok finding_claim ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let reference = step_text ^ "/" ^ key_text in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; "step", `String step_text
                    ; "key", `String key_text
                    ; "claim", `String claim_text
                    ; ( "claim_file"
                      , `Assoc
                          [ "path", `String claim_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~state_changes
                      ?created_references
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"finding create"
                       ~arguments
                       ~phase:(Some "researching")
                       ~step:step_text
                       ~claim:claim_text
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ~consumed_references:[ claim_text ]
                       ?created_references
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind created =
                     In_thread.run (fun () ->
                       Sandwalk_store.create_finding
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~claim_id
                         ~step_key
                         ~finding_key
                         ~claim_text:
                           (Sandwalk_core.Finding_claim.text finding_claim)
                         ~claim_md5:(Sandwalk_runtime.File_input.md5 input)
                         ~claim_size:(Sandwalk_runtime.File_input.size input)
                         ~now:(Sandwalk_runtime.timestamp_utc started_at)
                         ())
                   in
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   (match created with
                    | Error error ->
                      let code, message = finding_error error in
                      let%bind logged =
                        append_event
                          ~kind:`Failed
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:[]
                          ~duration_ms
                          ~outcome:"failure"
                          ~error_code:code
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () -> print_failure_and_exit ~code ~message)
                    | Ok created ->
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:
                            [ `Assoc
                                [ "entity", `String "finding"
                                ; "from", `Null
                                ; "to", `String reference
                                ]
                            ]
                          ~created_references:[ reference ]
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let result =
                           `Assoc
                             [ "finding", `String reference
                             ; ( "revision"
                               , `Int
                                   (Sandwalk_store.Create_finding_result.revision
                                      created) )
                             ; "state", `String "draft"
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let finding_attach_command =
  Async.Command.async
    ~summary:"Attach a typed exact excerpt to a finding."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and finding_text =
       flag "--finding" (required string) ~doc:"STEP/KEY Finding reference"
     and excerpt_text =
       flag "--excerpt" (required string) ~doc:"EXCERPT Exact excerpt"
     and relation_text =
       flag "--relation" (required string) ~doc:"RELATION Evidence relation"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     in
     fun () ->
       let finding =
         match String.lsplit2 finding_text ~on:'/' with
         | Some (step, key) ->
           (match
              Sandwalk_core.Plan_step.Key.of_string step,
              Sandwalk_core.Finding_key.of_string key
            with
            | Ok step, Some key -> Some (step, key)
            | _ -> None)
         | None -> None
       in
       match
         Sandwalk_core.Slug.of_string slug_text,
         finding,
         Sandwalk_core.Excerpt_id.of_string excerpt_text,
         Sandwalk_core.Finding_relation.of_string relation_text,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_FINDING"
           ~message:"Finding reference must be STEP/KEY."
       | _, _, None, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_EXCERPT"
           ~message:"Excerpt reference is invalid."
       | _, _, _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_RELATION"
           ~message:
             "Relation must be supports, contradicts, qualifies, or context."
       | _, _, _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | ( Ok slug
         , Some (step_key, finding_key)
         , Some excerpt_id
         , Some relation
         , Some claim_id ) ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; "finding", `String finding_text
               ; "excerpt", `String excerpt_text
               ; "relation", `String relation_text
               ; "claim", `String claim_text
               ]
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"finding attach"
                  ~arguments
                  ~phase:(Some "researching")
                  ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                  ~claim:claim_text
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ~consumed_references:
                    [ claim_text; finding_text; excerpt_text ]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~state_changes:[]
               ()
           in
           (match started with
            | Error _ ->
              print_failure_and_exit
                ~code:"AUDIT_LOG_ERROR"
                ~message:"Could not append workspace audit log."
            | Ok () ->
              let%bind attached =
                In_thread.run (fun () ->
                  Sandwalk_store.attach_evidence
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~claim_id
                    ~step_key
                    ~finding_key
                    ~excerpt_id
                    ~relation
                    ~now:(Sandwalk_runtime.timestamp_utc started_at)
                    ())
              in
              let finished_at = Time_float_unix.now () in
              let duration_ms =
                Time_float.diff finished_at started_at
                |> Time_float.Span.to_ms
                |> Float.iround_nearest_exn
              in
              (match attached with
               | Error error ->
                 let code, message = finding_error error in
                 let%bind logged =
                   append_event
                     ~kind:`Failed
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~state_changes:[]
                     ~duration_ms
                     ~outcome:"failure"
                     ~error_code:code
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message)
               | Ok attached ->
                 let attached_now =
                   Sandwalk_store.Attach_evidence_result.attached attached
                 in
                 let revision =
                   Sandwalk_store.Attach_evidence_result.revision attached
                 in
                 let%bind logged =
                   append_event
                     ~kind:`Finished
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~state_changes:
                       (if attached_now
                        then
                          [ `Assoc
                              [ "entity", `String "finding.evidence"
                              ; "from", `Null
                              ; "to", `String excerpt_text
                              ]
                          ]
                        else [])
                     ~duration_ms
                     ~outcome:"success"
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let result =
                      `Assoc
                        [ "finding", `String finding_text
                        ; "revision", `Int revision
                        ; "attached", `Bool attached_now
                        ; ( "revised"
                          , `Bool
                              (Sandwalk_store.Attach_evidence_result.revised
                                 attached) )
                        ]
                    in
                    Sandwalk_protocol.Envelope.success ~result ()
                    |> Sandwalk_protocol.Envelope.render
                    |> print_endline;
                    Deferred.unit)))))
;;

let finding_seal_command =
  Async.Command.async
    ~summary:"Seal an evidence-bearing finding revision."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and finding_text =
       flag "--finding" (required string) ~doc:"STEP/KEY Finding reference"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     in
     fun () ->
       let finding =
         match String.lsplit2 finding_text ~on:'/' with
         | Some (step, key) ->
           (match
              Sandwalk_core.Plan_step.Key.of_string step,
              Sandwalk_core.Finding_key.of_string key
            with
            | Ok step, Some key -> Some (step, key)
            | _ -> None)
         | None -> None
       in
       match
         Sandwalk_core.Slug.of_string slug_text,
         finding,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_FINDING"
           ~message:"Finding reference must be STEP/KEY."
       | _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some (step_key, finding_key), Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; "finding", `String finding_text
               ; "claim", `String claim_text
               ]
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~state_changes
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"finding seal"
                  ~arguments
                  ~phase:(Some "researching")
                  ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                  ~claim:claim_text
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ~consumed_references:[ claim_text; finding_text ]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~state_changes:[]
               ()
           in
           (match started with
            | Error _ ->
              print_failure_and_exit
                ~code:"AUDIT_LOG_ERROR"
                ~message:"Could not append workspace audit log."
            | Ok () ->
              let%bind sealed =
                In_thread.run (fun () ->
                  Sandwalk_store.seal_finding
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~claim_id
                    ~step_key
                    ~finding_key
                    ~now:(Sandwalk_runtime.timestamp_utc started_at)
                    ())
              in
              let finished_at = Time_float_unix.now () in
              let duration_ms =
                Time_float.diff finished_at started_at
                |> Time_float.Span.to_ms
                |> Float.iround_nearest_exn
              in
              (match sealed with
               | Error error ->
                 let code, message = finding_error error in
                 let%bind logged =
                   append_event
                     ~kind:`Failed
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~state_changes:[]
                     ~duration_ms
                     ~outcome:"failure"
                     ~error_code:code
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message)
               | Ok sealed ->
                 let already_sealed =
                   Sandwalk_store.Seal_finding_result.already_sealed sealed
                 in
                 let%bind logged =
                   append_event
                     ~kind:`Finished
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~state_changes:
                       (if already_sealed
                        then []
                        else
                          [ `Assoc
                              [ ( "entity"
                                , `String ("finding." ^ finding_text ^ ".state")
                                )
                              ; "from", `String "draft"
                              ; "to", `String "sealed"
                              ]
                          ])
                     ~duration_ms
                     ~outcome:"success"
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let result =
                      `Assoc
                        [ "finding", `String finding_text
                        ; ( "revision"
                          , `Int
                              (Sandwalk_store.Seal_finding_result.revision
                                 sealed) )
                        ; ( "state"
                          , `String
                              (Sandwalk_store.Seal_finding_result.state
                                 sealed) )
                        ; "already_sealed", `Bool already_sealed
                        ]
                    in
                    Sandwalk_protocol.Envelope.success ~result ()
                    |> Sandwalk_protocol.Envelope.render
                    |> print_endline;
                    Deferred.unit)))))
;;

let finding_review_command =
  Async.Command.async
    ~summary:"Record a versioned semantic review for a sealed finding."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and finding_text =
       flag "--finding" (required string) ~doc:"STEP/KEY Finding reference"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     and review_path =
       flag "--review-file" (required string) ~doc:"PATH Versioned review JSON"
     in
     fun () ->
       let finding =
         match String.lsplit2 finding_text ~on:'/' with
         | Some (step, key) ->
           (match
              Sandwalk_core.Plan_step.Key.of_string step,
              Sandwalk_core.Finding_key.of_string key
            with
            | Ok step, Some key -> Some (step, key)
            | _ -> None)
         | None -> None
       in
       match
         Sandwalk_core.Slug.of_string slug_text,
         finding,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None, _ ->
         print_failure_and_exit
           ~code:"INVALID_FINDING"
           ~message:"Finding reference must be STEP/KEY."
       | _, _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some (step_key, finding_key), Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:review_path
               ~maximum_bytes:65_536
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"FINDING_REVIEW_FILE_ERROR"
               ~message:"Could not read bounded finding review."
           | Ok input ->
             let decoded =
               try
                 Sandwalk_runtime.File_input.content input
                 |> Yojson.Safe.from_string
                 |> Sandwalk_protocol.Finding_review.decode
               with
               | _ -> Error Sandwalk_protocol.Finding_review.Invalid_review
             in
             (match decoded with
              | Error _ ->
                print_failure_and_exit
                  ~code:"INVALID_FINDING_REVIEW"
                  ~message:"Finding review JSON is invalid or unsupported."
              | Ok review ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; "finding", `String finding_text
                    ; "claim", `String claim_text
                    ; ( "review_file"
                      , `Assoc
                          [ "path", `String review_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~state_changes
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"finding review"
                       ~arguments
                       ~phase:(Some "researching")
                       ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                       ~claim:claim_text
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ~consumed_references:[ claim_text; finding_text ]
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let verdict =
                     Sandwalk_protocol.Finding_review.verdict review
                     |> Sandwalk_protocol.Finding_review.verdict_to_string
                   in
                   let%bind recorded =
                     In_thread.run (fun () ->
                       Sandwalk_store.review_finding
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~claim_id
                         ~step_key
                         ~finding_key
                         ~verdict
                         ~summary:
                           (Sandwalk_protocol.Finding_review.summary review)
                         ~source_quality:
                           (Sandwalk_protocol.Finding_review.source_quality
                              review)
                         ~conflicts:
                           (Sandwalk_protocol.Finding_review.conflicts review)
                         ~qualifications:
                           (Sandwalk_protocol.Finding_review.qualifications
                              review)
                         ~review_json:
                           (Sandwalk_runtime.File_input.content input)
                         ~review_md5:(Sandwalk_runtime.File_input.md5 input)
                         ~now:(Sandwalk_runtime.timestamp_utc started_at)
                         ())
                   in
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   (match recorded with
                    | Error error ->
                      let code, message = finding_error error in
                      let%bind logged =
                        append_event
                          ~kind:`Failed
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:[]
                          ~duration_ms
                          ~outcome:"failure"
                          ~error_code:code
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () -> print_failure_and_exit ~code ~message)
                    | Ok recorded ->
                      let reviewed =
                        Sandwalk_store.Review_finding_result.reviewed recorded
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~state_changes:
                            (if reviewed
                             then
                               [ `Assoc
                                   [ ( "entity"
                                     , `String
                                         ("finding."
                                          ^ finding_text
                                          ^ ".state") )
                                   ; "from", `String "sealed"
                                   ; "to", `String "reviewed"
                                   ]
                               ]
                             else [])
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let result =
                           `Assoc
                             [ "finding", `String finding_text
                             ; ( "revision"
                               , `Int
                                   (Sandwalk_store.Review_finding_result
                                    .revision
                                      recorded) )
                             ; "verdict", `String verdict
                             ; "reviewed", `Bool reviewed
                             ; "state", `String "reviewed"
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let finding_repair_command =
  Async.Command.async
    ~summary:"Reopen a completed finding for evidence repair."
    (let%map_open.Command finding_text =
       flag "--finding" (required string) ~doc:"STEP/KEY Finding reference"
     and reason_path =
       flag "--reason-file" (required string) ~doc:"PATH Bounded repair reason"
     and slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       let finding =
         match String.lsplit2 finding_text ~on:'/' with
         | Some (step, key) ->
           (match
              Sandwalk_core.Plan_step.Key.of_string step,
              Sandwalk_core.Finding_key.of_string key
            with
            | Ok step, Some key -> Some (step, key)
            | _ -> None)
         | None -> None
       in
       match Sandwalk_core.Slug.of_string slug_text, finding with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_FINDING"
           ~message:"Finding reference must be STEP/KEY."
       | Ok slug, Some (step_key, finding_key) ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind input =
           Sandwalk_runtime.File_input.read
             ~path:reason_path
             ~maximum_bytes:65_536
         in
         (match input with
          | Error _ ->
            print_failure_and_exit
              ~code:"FINDING_REPAIR_FILE_ERROR"
              ~message:"Could not read bounded non-empty repair reason."
          | Ok input
            when String.is_empty
                   (String.strip (Sandwalk_runtime.File_input.content input)) ->
            print_failure_and_exit
              ~code:"FINDING_REPAIR_FILE_ERROR"
              ~message:"Could not read bounded non-empty repair reason."
          | Ok input ->
            let started_at = Time_float_unix.now () in
            let%bind invocation_id =
              In_thread.run (fun () ->
                Sandwalk_runtime.invocation_id ~now:started_at)
            in
            let arguments =
              `Assoc
                [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                ; "directory_prefix", `String directory_prefix
                ; "finding", `String finding_text
                ; ( "reason_file"
                  , `Assoc
                      [ "path", `String reason_path
                      ; "size", `Int (Sandwalk_runtime.File_input.size input)
                      ; ( "md5"
                        , `String (Sandwalk_runtime.File_input.md5 input) )
                      ] )
                ]
            in
            let append_event
                  ~kind
                  ~timestamp
                  ?(state_changes = [])
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ()
              =
              Sandwalk_runtime.Audit.append
                ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                (Sandwalk_protocol.Audit_event.create
                   ~invocation_id
                   ~timestamp
                   ~kind
                   ~command:"finding repair"
                   ~arguments
                   ~phase:None
                   ~step:(Sandwalk_core.Plan_step.Key.to_string step_key)
                   ~raw_argv:(Sys.get_argv () |> Array.to_list)
                   ~state_changes
                   ~consumed_references:[ finding_text ]
                   ?duration_ms
                   ?outcome
                   ?error_code
                   ())
            in
            let%bind started =
              append_event
                ~kind:`Started
                ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                ()
            in
            (match started with
             | Error _ ->
               print_failure_and_exit
                 ~code:"AUDIT_LOG_ERROR"
                 ~message:"Could not append workspace audit log."
             | Ok () ->
               let%bind repaired =
                 In_thread.run (fun () ->
                   Sandwalk_store.repair_finding
                     ~database_path:
                       (Sandwalk_runtime.Workspace.database_path workspace)
                     ~expected_slug:slug
                     ~step_key
                     ~finding_key
                     ~reason_text:(Sandwalk_runtime.File_input.content input)
                     ~reason_path
                     ~reason_md5:(Sandwalk_runtime.File_input.md5 input)
                     ~reason_size:(Sandwalk_runtime.File_input.size input)
                     ~now:(Sandwalk_runtime.timestamp_utc started_at)
                     ())
               in
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               (match repaired with
                | Error error ->
                  let code, message = repair_finding_error error in
                  let%bind _ =
                    append_event
                      ~kind:`Failed
                      ~timestamp:
                        (Sandwalk_runtime.timestamp_utc finished_at)
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  print_failure_and_exit ~code ~message
                | Ok repaired ->
                  let revision =
                    Sandwalk_store.Repair_finding_result.revision repaired
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Finished
                      ~timestamp:
                        (Sandwalk_runtime.timestamp_utc finished_at)
                      ~state_changes:
                        [ `Assoc
                            [ "entity", `String ("finding." ^ finding_text)
                            ; "from", `String "reviewed"
                            ; "to", `String "draft"
                            ]
                        ; `Assoc
                            [ ( "entity"
                              , `String
                                  ("step."
                                   ^ Sandwalk_core.Plan_step.Key.to_string
                                       step_key) )
                            ; "from", `String "completed"
                            ; "to", `String "suspended"
                            ]
                        ]
                      ~duration_ms
                      ~outcome:"success"
                      ()
                  in
                  (match logged with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () ->
                     let result =
                       `Assoc
                         [ "finding", `String finding_text
                         ; "revision", `Int revision
                         ; ( "suspended_claims"
                           , `Int
                               (Sandwalk_store.Repair_finding_result
                                .suspended_claims
                                  repaired) )
                         ; ( "rejected_excerpts"
                           , `Int
                               (Sandwalk_store.Repair_finding_result
                                .rejected_excerpts
                                  repaired) )
                         ]
                     in
                     let next =
                       Sandwalk_protocol.Shell_command.of_words
                         [ "sandwalk"
                         ; "continue"
                         ; "--slug"
                         ; Sandwalk_core.Slug.to_string slug
                         ; "--directory-prefix"
                         ; directory_prefix
                         ]
                     in
                     Sandwalk_protocol.Envelope.success
                       ~result
                       ~next
                       ()
                     |> Sandwalk_protocol.Envelope.render
                     |> print_endline;
                     Deferred.unit)))))
;;

let finding_command =
  Async.Command.group
    ~summary:"Create and manage evidence-backed findings."
    [ "attach", finding_attach_command
    ; "create", finding_create_command
    ; "repair", finding_repair_command
    ; "review", finding_review_command
    ; "seal", finding_seal_command
    ]
;;

let step_complete_command =
  Async.Command.async
    ~summary:"Complete a step whose current findings passed review."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and claim_text =
       flag "--claim" (required string) ~doc:"CLAIM Active execution claim"
     in
     fun () ->
       match
         Sandwalk_core.Slug.of_string slug_text,
         Sandwalk_core.Claim_id.of_string claim_text
       with
       | Error error, _ ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | _, None ->
         print_failure_and_exit
           ~code:"INVALID_CLAIM"
           ~message:"Claim identifier is invalid."
       | Ok slug, Some claim_id ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let arguments =
             `Assoc
               [ "slug", `String (Sandwalk_core.Slug.to_string slug)
               ; "directory_prefix", `String directory_prefix
               ; "claim", `String claim_text
               ]
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ~state_changes
                 ?step
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"step complete"
                  ~arguments
                  ~phase
                  ?step
                  ~claim:claim_text
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ~consumed_references:[ claim_text ]
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:(Some "researching")
               ~state_changes:[]
               ()
           in
           (match started with
            | Error _ ->
              print_failure_and_exit
                ~code:"AUDIT_LOG_ERROR"
                ~message:"Could not append workspace audit log."
            | Ok () ->
              let%bind completed =
                In_thread.run (fun () ->
                  Sandwalk_store.complete_step
                    ~database_path:
                      (Sandwalk_runtime.Workspace.database_path workspace)
                    ~expected_slug:slug
                    ~claim_id
                    ~now:(Sandwalk_runtime.timestamp_utc started_at)
                    ())
              in
              let finished_at = Time_float_unix.now () in
              let duration_ms =
                Time_float.diff finished_at started_at
                |> Time_float.Span.to_ms
                |> Float.iround_nearest_exn
              in
              (match completed with
               | Error error ->
                 let code, message = complete_step_error error in
                 let%bind logged =
                   append_event
                     ~kind:`Failed
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~phase:(Some "researching")
                     ~state_changes:[]
                     ~duration_ms
                     ~outcome:"failure"
                     ~error_code:code
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message)
               | Ok completed ->
                 let step =
                   Sandwalk_store.Complete_step_result.step_key completed
                   |> Sandwalk_core.Plan_step.Key.to_string
                 in
                 let phase =
                   Sandwalk_store.Complete_step_result.phase completed
                 in
                 let phase_text = Sandwalk_core.Phase.to_string phase in
                 let state_changes =
                   [ `Assoc
                       [ "entity", `String ("step." ^ step ^ ".state")
                       ; "from", `String "claimed"
                       ; "to", `String "completed"
                       ]
                   ]
                   @
                   if Sandwalk_core.Phase.equal phase Sandwalk_core.Phase.Researching
                   then []
                   else
                     [ `Assoc
                         [ "entity", `String "workspace.phase"
                         ; "from", `String "researching"
                         ; "to", `String phase_text
                         ]
                     ]
                 in
                 let%bind logged =
                   append_event
                     ~kind:`Finished
                     ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                     ~phase:(Some phase_text)
                     ~step
                     ~state_changes
                     ~duration_ms
                     ~outcome:"success"
                     ()
                 in
                 (match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () ->
                    let result =
                      `Assoc
                        [ "step", `String step
                        ; "state", `String "completed"
                        ; "phase", `String phase_text
                        ]
                    in
                    Sandwalk_protocol.Envelope.success ~result ()
                    |> Sandwalk_protocol.Envelope.render
                    |> print_endline;
                    Deferred.unit)))))
;;

let draft_prepare_command =
  Async.Command.async
    ~summary:"Generate the deterministic writer pack and enter drafting."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind evidence =
             In_thread.run (fun () ->
               Sandwalk_store.read_writer_evidence
                 ~database_path:
                   (Sandwalk_runtime.Workspace.database_path workspace)
                 ~expected_slug:slug
                 ())
           in
           match evidence with
           | Error error ->
             let code, message = draft_error error in
             print_failure_and_exit ~code ~message
           | Ok evidence ->
             let%bind loaded =
               Deferred.List.map evidence ~how:`Sequential ~f:(fun row ->
                 let%map input =
                   Sandwalk_runtime.File_input.read
                     ~path:(Sandwalk_store.Writer_evidence.excerpt_path row)
                     ~maximum_bytes:Sandwalk_core.Excerpt.maximum_bytes
                 in
                 Result.bind input ~f:(fun input ->
                   if
                     String.equal
                       (Sandwalk_runtime.File_input.md5 input)
                       (Sandwalk_store.Writer_evidence.excerpt_md5 row)
                   then Ok (row, input)
                   else
                     Or_error.error_string
                       "Excerpt artifact hash does not match durable state."))
             in
             (match Result.all loaded with
              | Error _ ->
                print_failure_and_exit
                  ~code:"WRITER_PACK_ARTIFACT_ERROR"
                  ~message:"Could not validate bounded excerpt artifacts."
              | Ok loaded ->
                let items =
                  List.map loaded ~f:(fun (row, input) ->
                    Sandwalk_core.Writer_pack.item
                      ~step:(Sandwalk_store.Writer_evidence.step row)
                      ~finding:(Sandwalk_store.Writer_evidence.finding row)
                      ~verdict:(Sandwalk_store.Writer_evidence.verdict row)
                      ~claim:(Sandwalk_store.Writer_evidence.claim row)
                      ~relation:(Sandwalk_store.Writer_evidence.relation row)
                      ~excerpt:(Sandwalk_store.Writer_evidence.excerpt row)
                      ~snapshot:(Sandwalk_store.Writer_evidence.snapshot row)
                      ~source_url:(Sandwalk_store.Writer_evidence.source_url row)
                      ~line_start:
                        (Sandwalk_store.Writer_evidence.line_start row)
                      ~line_end:(Sandwalk_store.Writer_evidence.line_end row)
                      ~text:(Sandwalk_runtime.File_input.content input))
                in
                let writer_pack =
                  Sandwalk_core.Writer_pack.render
                    ~slug:(Sandwalk_core.Slug.to_string slug)
                    items
                in
                if String.length writer_pack > 1_048_576
                then
                  print_failure_and_exit
                    ~code:"WRITER_PACK_TOO_LARGE"
                    ~message:"Writer pack exceeds the 1 MiB bound."
                else (
                  let started_at = Time_float_unix.now () in
                  let%bind invocation_id =
                    In_thread.run (fun () ->
                      Sandwalk_runtime.invocation_id ~now:started_at)
                  in
                  let output_path =
                    Sandwalk_runtime.Workspace.writer_pack_path workspace
                  in
                  let arguments =
                    `Assoc
                      [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                      ; "directory_prefix", `String directory_prefix
                      ]
                  in
                  let append_event
                        ~kind
                        ~timestamp
                        ~phase
                        ~state_changes
                        ?duration_ms
                        ?outcome
                        ?error_code
                        ()
                    =
                    Sandwalk_runtime.Audit.append
                      ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                      (Sandwalk_protocol.Audit_event.create
                         ~invocation_id
                         ~timestamp
                         ~kind
                         ~command:"draft prepare"
                         ~arguments
                         ~phase
                         ~raw_argv:(Sys.get_argv () |> Array.to_list)
                         ~state_changes
                         ~consumed_references:
                           (List.map evidence ~f:(fun row ->
                              Sandwalk_store.Writer_evidence.excerpt row))
                         ?duration_ms
                         ?outcome
                         ?error_code
                         ())
                  in
                  let fail_with_audit ~code ~message =
                    let finished_at = Time_float_unix.now () in
                    let duration_ms =
                      Time_float.diff finished_at started_at
                      |> Time_float.Span.to_ms
                      |> Float.iround_nearest_exn
                    in
                    let%bind logged =
                      append_event
                        ~kind:`Failed
                        ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                        ~phase:(Some "evidence-review")
                        ~state_changes:[]
                        ~duration_ms
                        ~outcome:"failure"
                        ~error_code:code
                        ()
                    in
                    match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () -> print_failure_and_exit ~code ~message
                  in
                  let%bind started =
                    append_event
                      ~kind:`Started
                      ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                      ~phase:(Some "evidence-review")
                      ~state_changes:[]
                      ()
                  in
                  (match started with
                   | Error _ ->
                     print_failure_and_exit
                       ~code:"AUDIT_LOG_ERROR"
                       ~message:"Could not append workspace audit log."
                   | Ok () ->
                     let%bind written =
                       Sandwalk_runtime.Atomic_file.write
                         ~path:output_path
                         ~temporary_suffix:invocation_id
                         writer_pack
                     in
                     (match written with
                      | Error _ ->
                        fail_with_audit
                          ~code:"WORKSPACE_IO_ERROR"
                          ~message:"Could not write deterministic writer pack."
                      | Ok () ->
                        let%bind transitioned =
                          In_thread.run (fun () ->
                            Sandwalk_store.begin_drafting
                              ~database_path:
                                (Sandwalk_runtime.Workspace.database_path
                                   workspace)
                              ~expected_slug:slug
                              ~now:
                                (Sandwalk_runtime.timestamp_utc
                                   (Time_float_unix.now ()))
                              ())
                        in
                        (match transitioned with
                         | Error error ->
                           let code, message = draft_error error in
                           fail_with_audit ~code ~message
                         | Ok phase ->
                           let finished_at = Time_float_unix.now () in
                           let duration_ms =
                             Time_float.diff finished_at started_at
                             |> Time_float.Span.to_ms
                             |> Float.iround_nearest_exn
                           in
                           let%bind logged =
                             append_event
                               ~kind:`Finished
                               ~timestamp:
                                 (Sandwalk_runtime.timestamp_utc finished_at)
                               ~phase:(Some "drafting")
                               ~state_changes:
                                 [ `Assoc
                                     [ "entity", `String "workspace.phase"
                                     ; "from", `String "evidence-review"
                                     ; ( "to"
                                       , `String
                                           (Sandwalk_core.Phase.to_string
                                              phase) )
                                     ]
                                 ]
                               ~duration_ms
                               ~outcome:"success"
                               ()
                           in
                           (match logged with
                            | Error _ ->
                              print_failure_and_exit
                                ~code:"AUDIT_LOG_ERROR"
                                ~message:
                                  "Could not append workspace audit log."
                            | Ok () ->
                              let result =
                                `Assoc
                                  [ "phase", `String "drafting"
                                  ; "writer_pack", `String output_path
                                  ; "evidence_count", `Int (List.length items)
                                  ]
                              in
                              Sandwalk_protocol.Envelope.success ~result ()
                              |> Sandwalk_protocol.Envelope.render
                              |> print_endline;
                              Deferred.unit))))))))
;;

let draft_submit_command =
  Async.Command.async
    ~summary:"Submit bounded cited Markdown for block review."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and report_input_path =
       flag "--report-file" (required string) ~doc:"PATH Draft report Markdown"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:report_input_path
               ~maximum_bytes:Sandwalk_core.Report.maximum_bytes
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"REPORT_FILE_ERROR"
               ~message:"Could not read bounded report Markdown."
           | Ok input ->
             (match
                Sandwalk_core.Report.create
                  (Sandwalk_runtime.File_input.content input)
              with
              | Error error ->
                let code, message = report_validation_error error in
                print_failure_and_exit ~code ~message
              | Ok report ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let output_path =
                  Sandwalk_runtime.Workspace.report_path workspace
                in
                let blocks =
                  Sandwalk_core.Report.blocks report
                  |> List.map ~f:(fun block ->
                    let text = Sandwalk_core.Report.block_text block in
                    let md5 = Md5.digest_string text |> Md5.to_hex in
                    let citations =
                      Sandwalk_core.Report.block_citations block
                      |> List.map ~f:(fun citation ->
                        Sandwalk_core.Report.citation_step citation
                        ^ "/"
                        ^ Sandwalk_core.Report.citation_finding citation)
                    in
                    text, md5, citations)
                in
                let citations =
                  List.concat_map blocks ~f:(fun (_, _, references) ->
                    references)
                  |> List.dedup_and_sort ~compare:String.compare
                in
                let%bind validated =
                  In_thread.run (fun () ->
                    Sandwalk_store.validate_report_citations
                      ~database_path:
                        (Sandwalk_runtime.Workspace.database_path workspace)
                      ~expected_slug:slug
                      ~citations
                      ())
                in
                let%bind () =
                  match validated with
                  | Ok () -> Deferred.unit
                  | Error error ->
                    let code, message = report_error error in
                    print_failure_and_exit ~code ~message
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; ( "report_file"
                      , `Assoc
                          [ "path", `String report_input_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~phase
                      ~state_changes
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"draft submit"
                       ~arguments
                       ~phase
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ~consumed_references:citations
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit ~code ~message =
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Failed
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "drafting")
                      ~state_changes:[]
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~phase:(Some "drafting")
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind written =
                     Sandwalk_runtime.Atomic_file.write
                       ~path:output_path
                       ~temporary_suffix:invocation_id
                       (Sandwalk_core.Report.markdown report)
                   in
                   (match written with
                    | Error _ ->
                      fail_with_audit
                        ~code:"WORKSPACE_IO_ERROR"
                        ~message:"Could not publish report Markdown."
                    | Ok () ->
                      let%bind submitted =
                        In_thread.run (fun () ->
                          Sandwalk_store.submit_report
                            ~database_path:
                              (Sandwalk_runtime.Workspace.database_path
                                 workspace)
                            ~expected_slug:slug
                            ~report_path:output_path
                            ~report_text:
                              (Sandwalk_core.Report.markdown report)
                            ~report_md5:
                              (Sandwalk_runtime.File_input.md5 input)
                            ~report_size:
                              (Sandwalk_runtime.File_input.size input)
                            ~blocks
                            ~now:
                              (Sandwalk_runtime.timestamp_utc
                                 (Time_float_unix.now ()))
                            ())
                      in
                      (match submitted with
                       | Error error ->
                         let code, message = report_error error in
                         fail_with_audit ~code ~message
                       | Ok submitted ->
                         let finished_at = Time_float_unix.now () in
                         let duration_ms =
                           Time_float.diff finished_at started_at
                           |> Time_float.Span.to_ms
                           |> Float.iround_nearest_exn
                         in
                         let%bind logged =
                           append_event
                             ~kind:`Finished
                             ~timestamp:
                               (Sandwalk_runtime.timestamp_utc finished_at)
                             ~phase:(Some "draft-review")
                             ~state_changes:
                               [ `Assoc
                                   [ "entity", `String "workspace.phase"
                                   ; "from", `String "drafting"
                                   ; "to", `String "draft-review"
                                   ]
                               ]
                             ~duration_ms
                             ~outcome:"success"
                             ()
                         in
                         (match logged with
                          | Error _ ->
                            print_failure_and_exit
                              ~code:"AUDIT_LOG_ERROR"
                              ~message:"Could not append workspace audit log."
                          | Ok () ->
                            let result =
                              `Assoc
                                [ ( "revision"
                                  , `Int
                                      (Sandwalk_store.Submit_report_result
                                       .revision
                                         submitted) )
                                ; ( "blocks"
                                  , `Int
                                      (Sandwalk_store.Submit_report_result
                                       .block_count
                                         submitted) )
                                ; ( "review_blocks"
                                  , `List
                                      (List.mapi blocks ~f:(fun index (_, md5, _) ->
                                         `Assoc
                                           [ "ordinal", `Int (index + 1)
                                           ; "block_md5", `String md5
                                           ])) )
                                ; "phase", `String "draft-review"
                                ; "report", `String output_path
                                ]
                            in
                            Sandwalk_protocol.Envelope.success ~result ()
                            |> Sandwalk_protocol.Envelope.render
                            |> print_endline;
                            Deferred.unit)))))))
;;

let draft_review_command =
  Async.Command.async
    ~summary:"Record hash-bound semantic verdicts for every report block."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and review_path =
       flag "--review-file" (required string) ~doc:"PATH Versioned block review"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind input =
             Sandwalk_runtime.File_input.read
               ~path:review_path
               ~maximum_bytes:1_048_576
           in
           match input with
           | Error _ ->
             print_failure_and_exit
               ~code:"REPORT_REVIEW_FILE_ERROR"
               ~message:"Could not read bounded report review."
           | Ok input ->
             let decoded =
               try
                 Sandwalk_runtime.File_input.content input
                 |> Yojson.Safe.from_string
                 |> Sandwalk_protocol.Report_review.decode
               with
               | _ -> Error Sandwalk_protocol.Report_review.Invalid_review
             in
             (match decoded with
              | Error _ ->
                print_failure_and_exit
                  ~code:"INVALID_REPORT_REVIEW"
                  ~message:"Report review JSON is invalid or unsupported."
              | Ok review ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let reviews =
                  Sandwalk_protocol.Report_review.blocks review
                  |> List.map ~f:(fun block ->
                    ( Sandwalk_protocol.Report_review.ordinal block
                    , Sandwalk_protocol.Report_review.block_md5 block
                    , (Sandwalk_protocol.Report_review.verdict block
                       |> Sandwalk_protocol.Finding_review.verdict_to_string)
                    , Sandwalk_protocol.Report_review.summary block ))
                in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ; ( "review_file"
                      , `Assoc
                          [ "path", `String review_path
                          ; "size", `Int (Sandwalk_runtime.File_input.size input)
                          ; ( "hash"
                            , `Assoc
                                [ "algorithm", `String "md5"
                                ; ( "value"
                                  , `String
                                      (Sandwalk_runtime.File_input.md5 input) )
                                ] )
                          ] )
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~phase
                      ~state_changes
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"draft review"
                       ~arguments
                       ~phase
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit ~code ~message =
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Failed
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "draft-review")
                      ~state_changes:[]
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~phase:(Some "draft-review")
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind recorded =
                     In_thread.run (fun () ->
                       Sandwalk_store.review_report
                         ~database_path:
                           (Sandwalk_runtime.Workspace.database_path workspace)
                         ~expected_slug:slug
                         ~report_revision:
                           (Sandwalk_protocol.Report_review.report_revision
                              review)
                         ~reviews
                         ~now:
                           (Sandwalk_runtime.timestamp_utc
                              (Time_float_unix.now ()))
                         ())
                   in
                   (match recorded with
                    | Error error ->
                      let code, message = report_error error in
                      fail_with_audit ~code ~message
                    | Ok recorded ->
                      let phase =
                        Sandwalk_store.Review_report_result.phase recorded
                      in
                      let phase_text = Sandwalk_core.Phase.to_string phase in
                      let finished_at = Time_float_unix.now () in
                      let duration_ms =
                        Time_float.diff finished_at started_at
                        |> Time_float.Span.to_ms
                        |> Float.iround_nearest_exn
                      in
                      let%bind logged =
                        append_event
                          ~kind:`Finished
                          ~timestamp:
                            (Sandwalk_runtime.timestamp_utc finished_at)
                          ~phase:(Some phase_text)
                          ~state_changes:
                            [ `Assoc
                                [ "entity", `String "workspace.phase"
                                ; "from", `String "draft-review"
                                ; "to", `String phase_text
                                ]
                            ]
                          ~duration_ms
                          ~outcome:"success"
                          ()
                      in
                      (match logged with
                       | Error _ ->
                         print_failure_and_exit
                           ~code:"AUDIT_LOG_ERROR"
                           ~message:"Could not append workspace audit log."
                       | Ok () ->
                         let result =
                           `Assoc
                             [ ( "revision"
                               , `Int
                                   (Sandwalk_store.Review_report_result.revision
                                      recorded) )
                             ; ( "accepted"
                               , `Bool
                                   (Sandwalk_store.Review_report_result.accepted
                                      recorded) )
                             ; "phase", `String phase_text
                             ]
                         in
                         Sandwalk_protocol.Envelope.success ~result ()
                         |> Sandwalk_protocol.Envelope.render
                         |> print_endline;
                         Deferred.unit))))))
;;

let draft_command =
  Async.Command.group
    ~summary:"Prepare bounded drafting inputs."
    [ "prepare", draft_prepare_command
    ; "review", draft_review_command
    ; "submit", draft_submit_command
    ]
;;

let finalize_command =
  Async.Command.async
    ~summary:"Render stable citations and complete the workspace."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let%bind database_exists =
           Async.Sys.file_exists_exn
             (Sandwalk_runtime.Workspace.database_path workspace)
         in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind state =
             In_thread.run (fun () ->
               Sandwalk_store.read_finalization_state
                 ~database_path:
                   (Sandwalk_runtime.Workspace.database_path workspace)
                 ~expected_slug:slug
                 ())
           in
           match state with
           | Error error ->
             let code, message = finalize_error error in
             print_failure_and_exit ~code ~message
           | Ok state ->
             (match
                Sandwalk_core.Final_report.render
                  ~markdown:
                    (Sandwalk_store.Finalization_state.report_text state)
                  ~sources_by_finding:
                    (Sandwalk_store.Finalization_state.sources_by_finding state)
              with
              | Error (Missing_source reference) ->
                print_failure_and_exit
                  ~code:"FINALIZE_SOURCE_MISSING"
                  ~message:
                    (sprintf "Citation %S has no current source." reference)
              | Ok rendered ->
                let started_at = Time_float_unix.now () in
                let%bind invocation_id =
                  In_thread.run (fun () ->
                    Sandwalk_runtime.invocation_id ~now:started_at)
                in
                let report_path =
                  Sandwalk_runtime.Workspace.report_path workspace
                in
                let sources_path =
                  Sandwalk_runtime.Workspace.sources_path workspace
                in
                let final_report =
                  Sandwalk_core.Final_report.report rendered
                in
                let sources = Sandwalk_core.Final_report.sources rendered in
                let arguments =
                  `Assoc
                    [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                    ; "directory_prefix", `String directory_prefix
                    ]
                in
                let append_event
                      ~kind
                      ~timestamp
                      ~phase
                      ~state_changes
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ()
                  =
                  Sandwalk_runtime.Audit.append
                    ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                    (Sandwalk_protocol.Audit_event.create
                       ~invocation_id
                       ~timestamp
                       ~kind
                       ~command:"finalize"
                       ~arguments
                       ~phase
                       ~raw_argv:(Sys.get_argv () |> Array.to_list)
                       ~state_changes
                       ?duration_ms
                       ?outcome
                       ?error_code
                       ())
                in
                let fail_with_audit ~code ~message =
                  let finished_at = Time_float_unix.now () in
                  let duration_ms =
                    Time_float.diff finished_at started_at
                    |> Time_float.Span.to_ms
                    |> Float.iround_nearest_exn
                  in
                  let%bind logged =
                    append_event
                      ~kind:`Failed
                      ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                      ~phase:(Some "finalizing")
                      ~state_changes:[]
                      ~duration_ms
                      ~outcome:"failure"
                      ~error_code:code
                      ()
                  in
                  match logged with
                  | Error _ ->
                    print_failure_and_exit
                      ~code:"AUDIT_LOG_ERROR"
                      ~message:"Could not append workspace audit log."
                  | Ok () -> print_failure_and_exit ~code ~message
                in
                let%bind started =
                  append_event
                    ~kind:`Started
                    ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                    ~phase:(Some "finalizing")
                    ~state_changes:[]
                    ()
                in
                (match started with
                 | Error _ ->
                   print_failure_and_exit
                     ~code:"AUDIT_LOG_ERROR"
                     ~message:"Could not append workspace audit log."
                 | Ok () ->
                   let%bind sources_written =
                     Sandwalk_runtime.Atomic_file.write
                       ~path:sources_path
                       ~temporary_suffix:invocation_id
                       sources
                   in
                   (match sources_written with
                    | Error _ ->
                      fail_with_audit
                        ~code:"WORKSPACE_IO_ERROR"
                        ~message:"Could not publish sources bibliography."
                    | Ok () ->
                      let%bind report_written =
                        Sandwalk_runtime.Atomic_file.write
                          ~path:report_path
                          ~temporary_suffix:invocation_id
                          final_report
                      in
                      (match report_written with
                       | Error _ ->
                         fail_with_audit
                           ~code:"WORKSPACE_IO_ERROR"
                           ~message:"Could not publish final report."
                       | Ok () ->
                         let final_report_md5 =
                           Md5.digest_string final_report |> Md5.to_hex
                         in
                         let sources_md5 =
                           Md5.digest_string sources |> Md5.to_hex
                         in
                         let%bind completed =
                           In_thread.run (fun () ->
                             Sandwalk_store.finalize_workspace
                               ~database_path:
                                 (Sandwalk_runtime.Workspace.database_path
                                    workspace)
                               ~expected_slug:slug
                               ~report_revision:
                                 (Sandwalk_store.Finalization_state
                                  .report_revision
                                    state)
                               ~final_report_md5
                               ~sources_md5
                               ~source_count:
                                 (Sandwalk_core.Final_report.source_count
                                    rendered)
                               ~now:
                                 (Sandwalk_runtime.timestamp_utc
                                    (Time_float_unix.now ()))
                               ())
                         in
                         (match completed with
                          | Error error ->
                            let code, message = finalize_error error in
                            fail_with_audit ~code ~message
                          | Ok phase ->
                            let finished_at = Time_float_unix.now () in
                            let duration_ms =
                              Time_float.diff finished_at started_at
                              |> Time_float.Span.to_ms
                              |> Float.iround_nearest_exn
                            in
                            let%bind logged =
                              append_event
                                ~kind:`Finished
                                ~timestamp:
                                  (Sandwalk_runtime.timestamp_utc finished_at)
                                ~phase:(Some "completed")
                                ~state_changes:
                                  [ `Assoc
                                      [ "entity", `String "workspace.phase"
                                      ; "from", `String "finalizing"
                                      ; ( "to"
                                        , `String
                                            (Sandwalk_core.Phase.to_string
                                               phase) )
                                      ]
                                  ]
                                ~duration_ms
                                ~outcome:"success"
                                ()
                            in
                            (match logged with
                             | Error _ ->
                               print_failure_and_exit
                                 ~code:"AUDIT_LOG_ERROR"
                                 ~message:
                                   "Could not append workspace audit log."
                             | Ok () ->
                               let result =
                                 `Assoc
                                   [ "phase", `String "completed"
                                   ; "report", `String report_path
                                   ; "sources", `String sources_path
                                   ; ( "source_count"
                                     , `Int
                                         (Sandwalk_core.Final_report
                                          .source_count
                                            rendered) )
                                   ]
                               in
                               Sandwalk_protocol.Envelope.success ~result ()
                               |> Sandwalk_protocol.Envelope.render
                               |> print_endline;
                               Deferred.unit))))))))
;;

let export_pdf_command =
  Async.Command.async
    ~summary:"Render finalized Markdown and bibliography as PDF."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and adapter =
       flag
         "--adapter"
         (optional_with_default "sandwalk-export-pandoc-pdf" string)
         ~doc:"PATH PDF export adapter executable"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let database_path =
           Sandwalk_runtime.Workspace.database_path workspace
         in
         let%bind database_exists = Async.Sys.file_exists_exn database_path in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let%bind state =
             In_thread.run (fun () ->
               Sandwalk_store.read_completed_export_state
                 ~database_path
                 ~expected_slug:slug
                 ())
           in
           match state with
           | Error error ->
             let code, message = export_error error in
             print_failure_and_exit ~code ~message
           | Ok state ->
             let started_at = Time_float_unix.now () in
             let%bind invocation_id =
               In_thread.run (fun () ->
                 Sandwalk_runtime.invocation_id ~now:started_at)
             in
             let report_path =
               Sandwalk_runtime.Workspace.report_path workspace
             in
             let sources_path =
               Sandwalk_runtime.Workspace.sources_path workspace
             in
             let output_path =
               Sandwalk_runtime.Workspace.report_pdf_path workspace
             in
             let expected_report_md5 =
               Sandwalk_store.Completed_export_state.final_report_md5 state
             in
             let expected_sources_md5 =
               Sandwalk_store.Completed_export_state.sources_md5 state
             in
             let arguments =
               `Assoc
                 [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                 ; "directory_prefix", `String directory_prefix
                 ; "format", `String "pdf"
                 ; "adapter", `String adapter
                 ; ( "inputs"
                   , `List
                       [ `Assoc
                           [ "role", `String "report"
                           ; "path", `String report_path
                           ; "md5", `String expected_report_md5
                           ]
                       ; `Assoc
                           [ "role", `String "bibliography"
                           ; "path", `String sources_path
                           ; "md5", `String expected_sources_md5
                           ]
                       ] )
                 ; "output", `String output_path
                 ]
             in
             let append_event
                   ~kind
                   ~timestamp
                   ~state_changes
                   ?duration_ms
                   ?outcome
                   ?error_code
                   ()
               =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp
                    ~kind
                    ~command:"export pdf"
                    ~arguments
                    ~phase:(Some "completed")
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ())
             in
             let fail_with_audit ~code ~message =
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let%bind logged =
                 append_event
                   ~kind:`Failed
                   ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                   ~state_changes:[]
                   ~duration_ms
                   ~outcome:"failure"
                   ~error_code:code
                   ()
               in
               match logged with
               | Error _ ->
                 print_failure_and_exit
                   ~code:"AUDIT_LOG_ERROR"
                   ~message:"Could not append workspace audit log."
               | Ok () -> print_failure_and_exit ~code ~message
             in
             let%bind started =
               append_event
                 ~kind:`Started
                 ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                 ~state_changes:[]
                 ()
             in
             (match started with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                let%bind report_input, sources_input =
                  Deferred.both
                    (Sandwalk_runtime.File_input.read
                       ~path:report_path
                       ~maximum_bytes:Sandwalk_core.Report.maximum_bytes)
                    (Sandwalk_runtime.File_input.read
                       ~path:sources_path
                       ~maximum_bytes:1_048_576)
                in
                (match report_input, sources_input with
                 | Error _, _ | _, Error _ ->
                   fail_with_audit
                     ~code:"EXPORT_INPUT_ERROR"
                     ~message:
                       "Final report or bibliography is missing or oversized."
                 | Ok report_input, Ok sources_input ->
                   let report_md5 =
                     Sandwalk_runtime.File_input.md5 report_input
                   in
                   let sources_md5 =
                     Sandwalk_runtime.File_input.md5 sources_input
                   in
                   if
                     not
                       (String.equal report_md5 expected_report_md5
                        && String.equal sources_md5 expected_sources_md5)
                   then
                     fail_with_audit
                       ~code:"EXPORT_INPUT_STALE"
                       ~message:
                         "Final report or bibliography differs from the \
                          finalized workspace."
                   else (
                     let temporary_path =
                       Sandwalk_runtime.Workspace.temporary_export_path
                         workspace
                         ~invocation_id
                     in
                     let%bind () = Unix.mkdir ~p:() temporary_path in
                     let request =
                       Sandwalk_protocol.Export_adapter.request
                         ~format:"pdf"
                         ~inputs:
                           [ "report", report_path, report_md5
                           ; "bibliography", sources_path, sources_md5
                           ]
                         ~output_directory:temporary_path
                     in
                     let%bind adapter_output =
                       Sandwalk_runtime.Adapter.run_json
                         ~executable:adapter
                         ~request
                         ~timeout:(Time_float.Span.of_sec 120.)
                         ~maximum_output_bytes:65_536
                     in
                     (match adapter_output with
                      | Error _ ->
                        fail_with_audit
                          ~code:"EXPORT_ADAPTER_FAILED"
                          ~message:"PDF export adapter failed."
                      | Ok _ ->
                        let manifest_path =
                          Filename.concat temporary_path "manifest.json"
                        in
                        let%bind manifest_input =
                          Sandwalk_runtime.File_input.read
                            ~path:manifest_path
                            ~maximum_bytes:262_144
                        in
                        (match manifest_input with
                         | Error _ ->
                           fail_with_audit
                             ~code:"EXPORT_ARTIFACT_ERROR"
                             ~message:
                               "Export adapter omitted its bounded manifest."
                         | Ok manifest_input ->
                           let decoded =
                             try
                               manifest_input
                               |> Sandwalk_runtime.File_input.content
                               |> Yojson.Safe.from_string
                               |> Sandwalk_protocol.Export_adapter.manifest
                             with
                             | _ ->
                               Error
                                 Sandwalk_protocol.Export_adapter.Invalid_manifest
                           in
                           (match decoded with
                            | Error _ ->
                              fail_with_audit
                                ~code:"EXPORT_PROTOCOL_ERROR"
                                ~message:"Export manifest is invalid."
                            | Ok manifest ->
                              let artifact_path =
                                Filename.concat
                                  temporary_path
                                  (Sandwalk_protocol.Export_adapter.artifact_path
                                     manifest)
                              in
                              let manifest_matches =
                                String.equal
                                  (Sandwalk_protocol.Export_adapter.format
                                     manifest)
                                  "pdf"
                                && String.equal
                                     (Sandwalk_protocol.Export_adapter
                                      .artifact_path
                                        manifest)
                                     "report.pdf"
                                && String.equal
                                     (Sandwalk_protocol.Export_adapter.media_type
                                        manifest)
                                     "application/pdf"
                                && Option.value_map
                                     (Sandwalk_protocol.Export_adapter.input_md5
                                        manifest
                                        "report")
                                     ~default:false
                                     ~f:(String.equal report_md5)
                                && Option.value_map
                                     (Sandwalk_protocol.Export_adapter.input_md5
                                        manifest
                                        "bibliography")
                                     ~default:false
                                     ~f:(String.equal sources_md5)
                              in
                              if not manifest_matches
                              then
                                fail_with_audit
                                  ~code:"EXPORT_PROTOCOL_ERROR"
                                  ~message:
                                    "Export manifest does not match the current \
                                     finalized inputs."
                              else (
                                let%bind artifact_input =
                                  Sandwalk_runtime.File_input.read
                                    ~path:artifact_path
                                    ~maximum_bytes:104_857_600
                                in
                                (match artifact_input with
                                 | Error _ ->
                                   fail_with_audit
                                     ~code:"EXPORT_ARTIFACT_ERROR"
                                     ~message:
                                       "Export adapter omitted the PDF artifact."
                                 | Ok artifact_input ->
                                   let artifact_md5 =
                                     Sandwalk_runtime.File_input.md5
                                       artifact_input
                                   in
                                   let artifact_content =
                                     Sandwalk_runtime.File_input.content
                                       artifact_input
                                   in
                                   if
                                     not
                                       (String.is_prefix
                                          artifact_content
                                          ~prefix:"%PDF-"
                                        && String.equal
                                             artifact_md5
                                             (Sandwalk_protocol.Export_adapter
                                              .artifact_md5
                                                manifest))
                                   then
                                     fail_with_audit
                                       ~code:"EXPORT_ARTIFACT_ERROR"
                                       ~message:
                                         "Exported artifact is not the declared \
                                          PDF."
                                   else (
                                     let%bind published =
                                       Deferred.Or_error.try_with (fun () ->
                                         Unix.rename
                                           ~src:artifact_path
                                           ~dst:output_path)
                                     in
                                     (match published with
                                      | Error _ ->
                                        fail_with_audit
                                          ~code:"WORKSPACE_IO_ERROR"
                                          ~message:
                                            "Could not publish PDF export."
                                      | Ok () ->
                                        let%bind _ =
                                          Monitor.try_with (fun () ->
                                            let%bind () =
                                              Unix.unlink manifest_path
                                            in
                                            Unix.rmdir temporary_path)
                                        in
                                        let finished_at =
                                          Time_float_unix.now ()
                                        in
                                        let duration_ms =
                                          Time_float.diff finished_at started_at
                                          |> Time_float.Span.to_ms
                                          |> Float.iround_nearest_exn
                                        in
                                        let%bind logged =
                                          append_event
                                            ~kind:`Finished
                                            ~timestamp:
                                              (Sandwalk_runtime.timestamp_utc
                                                 finished_at)
                                            ~state_changes:
                                              [ `Assoc
                                                  [ ( "entity"
                                                    , `String "export.pdf" )
                                                  ; "from", `Null
                                                  ; ( "to"
                                                    , `String artifact_md5 )
                                                  ]
                                              ]
                                            ~duration_ms
                                            ~outcome:"success"
                                            ()
                                        in
                                        (match logged with
                                         | Error _ ->
                                           print_failure_and_exit
                                             ~code:"AUDIT_LOG_ERROR"
                                             ~message:
                                               "Could not append workspace \
                                                audit log."
                                         | Ok () ->
                                           let result =
                                             `Assoc
                                               [ "format", `String "pdf"
                                               ; "artifact", `String output_path
                                               ; ( "media_type"
                                                 , `String "application/pdf" )
                                               ; "md5", `String artifact_md5
                                               ; ( "size"
                                                 , `Int
                                                     (Sandwalk_runtime.File_input
                                                      .size
                                                        artifact_input) )
                                               ]
                                           in
                                           Sandwalk_protocol.Envelope.success
                                             ~result
                                             ()
                                           |> Sandwalk_protocol.Envelope.render
                                           |> print_endline;
                                           Deferred.unit)))))))))))))
;;

let export_command =
  Async.Command.group
    ~summary:"Render finalized reports through export adapters."
    [ "pdf", export_pdf_command ]
;;

let gc_command =
  Async.Command.async
    ~summary:"Plan or apply explicit raw snapshot cleanup."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     and raw = flag "--raw" no_arg ~doc:" Target retained raw payloads"
     and plan = flag "--plan" no_arg ~doc:" Write a cleanup plan"
     and apply = flag "--apply" no_arg ~doc:" Apply the current cleanup plan" in
     fun () ->
       if (not raw) || Bool.equal plan apply
       then
         print_failure_and_exit
           ~code:"INVALID_GC_MODE"
           ~message:"Specify --raw and exactly one of --plan or --apply."
       else
         match Sandwalk_core.Slug.of_string slug_text with
         | Error error ->
           print_failure_and_exit
             ~code:"INVALID_SLUG"
             ~message:(Sandwalk_core.Slug.Error.message error)
         | Ok slug ->
           let directory_prefix =
             Sandwalk_runtime.resolve_directory_prefix
               ~command_line:directory_prefix
           in
           let workspace =
             Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
           in
           let%bind database_exists =
             Async.Sys.file_exists_exn
               (Sandwalk_runtime.Workspace.database_path workspace)
           in
           if not database_exists
           then
             print_failure_and_exit
               ~code:"WORKSPACE_NOT_FOUND"
               ~message:"Workspace does not exist."
           else (
             let started_at = Time_float_unix.now () in
             let%bind invocation_id =
               In_thread.run (fun () ->
                 Sandwalk_runtime.invocation_id ~now:started_at)
             in
             let mode = if plan then "plan" else "apply" in
             let arguments =
               `Assoc
                 [ "slug", `String (Sandwalk_core.Slug.to_string slug)
                 ; "directory_prefix", `String directory_prefix
                 ; "raw", `Bool true
                 ; "mode", `String mode
                 ]
             in
             let append_event
                   ~kind
                   ~timestamp
                   ~state_changes
                   ?duration_ms
                   ?outcome
                   ?error_code
                   ()
               =
               Sandwalk_runtime.Audit.append
                 ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                 (Sandwalk_protocol.Audit_event.create
                    ~invocation_id
                    ~timestamp
                    ~kind
                    ~command:("gc raw " ^ mode)
                    ~arguments
                    ~phase:None
                    ~raw_argv:(Sys.get_argv () |> Array.to_list)
                    ~state_changes
                    ?duration_ms
                    ?outcome
                    ?error_code
                    ())
             in
             let fail_with_audit ~code ~message =
               let finished_at = Time_float_unix.now () in
               let duration_ms =
                 Time_float.diff finished_at started_at
                 |> Time_float.Span.to_ms
                 |> Float.iround_nearest_exn
               in
               let%bind logged =
                 append_event
                   ~kind:`Failed
                   ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                   ~state_changes:[]
                   ~duration_ms
                   ~outcome:"failure"
                   ~error_code:code
                   ()
               in
               match logged with
               | Error _ ->
                 print_failure_and_exit
                   ~code:"AUDIT_LOG_ERROR"
                   ~message:"Could not append workspace audit log."
               | Ok () -> print_failure_and_exit ~code ~message
             in
             let%bind started =
               append_event
                 ~kind:`Started
                 ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                 ~state_changes:[]
                 ()
             in
             (match started with
              | Error _ ->
                print_failure_and_exit
                  ~code:"AUDIT_LOG_ERROR"
                  ~message:"Could not append workspace audit log."
              | Ok () ->
                let plan_path =
                  Sandwalk_runtime.Workspace.gc_raw_plan_path workspace
                in
                let%bind operation =
                  if plan
                  then (
                    let%bind candidates =
                      In_thread.run (fun () ->
                        Sandwalk_store.read_raw_gc_candidates
                          ~database_path:
                            (Sandwalk_runtime.Workspace.database_path workspace)
                          ~expected_slug:slug
                          ())
                    in
                    match candidates with
                    | Error error -> Deferred.return (Error error)
                    | Ok artifact_directories ->
                      let paths =
                        List.map artifact_directories ~f:(fun directory ->
                          Filename.concat directory "original")
                      in
                      let%bind paths =
                        Deferred.List.filter paths ~how:`Sequential ~f:(fun path ->
                          Async.Sys.file_exists_exn path)
                      in
                      let plan_json =
                        `Assoc
                          [ "protocol", `String "sandwalk.gc-raw-plan.v1"
                          ; ( "artifacts"
                            , `List
                                (List.map paths ~f:(fun path ->
                                   `String path)) )
                          ]
                        |> Yojson.Safe.to_string
                      in
                      let plan_md5 =
                        Md5.digest_string plan_json |> Md5.to_hex
                      in
                      let%bind written =
                        Sandwalk_runtime.Atomic_file.write
                          ~path:plan_path
                          ~temporary_suffix:invocation_id
                          plan_json
                      in
                      (match written with
                       | Error _ ->
                         Deferred.return
                           (Error
                              (Sandwalk_store.Error.Database_error
                                 "Could not write GC plan."))
                       | Ok () ->
                         let%map recorded =
                           In_thread.run (fun () ->
                             Sandwalk_store.record_raw_gc_plan
                               ~database_path:
                                 (Sandwalk_runtime.Workspace.database_path
                                    workspace)
                               ~expected_slug:slug
                               ~plan_path
                               ~plan_json
                               ~plan_md5
                               ~now:
                                 (Sandwalk_runtime.timestamp_utc
                                    (Time_float_unix.now ()))
                               ())
                         in
                         Result.map recorded ~f:(fun () -> paths)))
                  else (
                    let%bind stored =
                      In_thread.run (fun () ->
                        Sandwalk_store.read_raw_gc_plan
                          ~database_path:
                            (Sandwalk_runtime.Workspace.database_path workspace)
                          ~expected_slug:slug
                          ())
                    in
                    match stored with
                    | Error error -> Deferred.return (Error error)
                    | Ok stored ->
                      let%bind input =
                        Sandwalk_runtime.File_input.read
                          ~path:plan_path
                          ~maximum_bytes:1_048_576
                      in
                      (match input with
                       | Error _ ->
                         Deferred.return (Error Sandwalk_store.Error.Gc_plan_stale)
                       | Ok input
                         when String.equal
                                (Sandwalk_runtime.File_input.md5 input)
                                (Sandwalk_store.Raw_gc_plan.plan_md5 stored)
                              && String.equal
                                   (Sandwalk_runtime.File_input.content input)
                                   (Sandwalk_store.Raw_gc_plan.plan_json stored)
                              && String.equal
                                   plan_path
                                   (Sandwalk_store.Raw_gc_plan.plan_path stored)
                         ->
                         let paths =
                           Sandwalk_store.Raw_gc_plan.artifact_paths stored
                         in
                         let%bind removed =
                           Deferred.List.map
                             paths
                             ~how:`Sequential
                             ~f:(fun path ->
                               let%bind exists = Async.Sys.file_exists_exn path in
                               if not exists
                               then Deferred.return (Ok ())
                               else Monitor.try_with (fun () -> Unix.unlink path))
                         in
                         (match Result.all_unit removed with
                          | Error _ ->
                            Deferred.return
                              (Error
                                 (Sandwalk_store.Error.Database_error
                                    "Could not remove raw artifact."))
                          | Ok () ->
                            let%map marked =
                              In_thread.run (fun () ->
                                Sandwalk_store.mark_raw_gc_applied
                                  ~database_path:
                                    (Sandwalk_runtime.Workspace.database_path
                                       workspace)
                                  ~expected_slug:slug
                                  ~plan_md5:
                                    (Sandwalk_store.Raw_gc_plan.plan_md5 stored)
                                  ~now:
                                    (Sandwalk_runtime.timestamp_utc
                                       (Time_float_unix.now ()))
                                  ())
                            in
                            Result.map marked ~f:(fun () -> paths))
                       | Ok _ ->
                         Deferred.return
                           (Error Sandwalk_store.Error.Gc_plan_stale)))
                in
                (match operation with
                 | Error error ->
                   let code, message =
                     match error with
                     | Sandwalk_store.Error.Database_error
                         "Could not write GC plan." ->
                       "WORKSPACE_IO_ERROR", "Could not write raw cleanup plan."
                     | Database_error "Could not remove raw artifact." ->
                       "WORKSPACE_IO_ERROR", "Could not remove raw artifact."
                     | error -> gc_error error
                   in
                   fail_with_audit ~code ~message
                 | Ok paths ->
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~state_changes:
                         [ `Assoc
                             [ "entity", `String "snapshot.raw"
                             ; "from", `Int (List.length paths)
                             ; "to", `Int (if plan then List.length paths else 0)
                             ]
                         ]
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      let result =
                        `Assoc
                          [ "mode", `String mode
                          ; "count", `Int (List.length paths)
                          ; "plan_path", `String plan_path
                          ]
                      in
                      Sandwalk_protocol.Envelope.success ~result ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let step_command =
  Async.Command.group
    ~summary:"Manage durable plan-step execution."
    [ "checkpoint", step_checkpoint_command
    ; "claim", step_claim_command
    ; "complete", step_complete_command
    ]
;;

let continue_command =
  Async.Command.async
    ~summary:"Materialize one durable work packet for the next research action."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let database_path =
           Sandwalk_runtime.Workspace.database_path workspace
         in
         let packet_path =
           Sandwalk_runtime.Workspace.work_packet_path workspace
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists = Async.Sys.file_exists_exn database_path in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ?(state_changes = [])
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"continue"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let fail_with_audit ~phase ~code ~message =
             let finished_at = Time_float_unix.now () in
             let duration_ms =
               Time_float.diff finished_at started_at
               |> Time_float.Span.to_ms
               |> Float.iround_nearest_exn
             in
             let%bind _ =
               append_event
                 ~kind:`Failed
                 ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                 ~phase
                 ~duration_ms
                 ~outcome:"failure"
                 ~error_code:code
                 ()
             in
             print_failure_and_exit ~code ~message
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind migrated_and_status =
               In_thread.run (fun () ->
                 let open Result.Let_syntax in
                 let%bind previous_schema_version =
                   Sandwalk_store.migrate_workspace
                     ~database_path
                     ~expected_slug:slug
                     ~now:(Sandwalk_runtime.timestamp_utc started_at)
                     ()
                 in
                 let%map status =
                   Sandwalk_store.read_status
                     ~database_path
                     ~expected_slug:slug
                     ()
                 in
                 previous_schema_version, status)
             in
             (match migrated_and_status with
              | Error error ->
                let code, message = status_error error in
                fail_with_audit ~phase:None ~code ~message
              | Ok (previous_schema_version, status) ->
                let phase = Sandwalk_store.Workspace_status.phase status in
                let phase_text = Sandwalk_core.Phase.to_string phase in
                let%bind recommendation =
                  recommendation_for_phase
                    ~database_path
                    ~slug
                    ~directory_prefix
                    ~phase
                in
                (match recommendation with
                 | Error error ->
                   let code, message = status_error error in
                   fail_with_audit
                     ~phase:(Some phase_text)
                     ~code
                     ~message
                 | Ok recommendation ->
                   let%bind report_blocks =
                     if
                       Sandwalk_core.Phase.equal
                         phase
                         Sandwalk_core.Phase.Draft_review
                     then
                       In_thread.run (fun () ->
                         Sandwalk_store.read_current_report_blocks
                           ~database_path
                           ())
                     else Deferred.return (Ok [])
                   in
                   (match report_blocks with
                    | Error error ->
                      let code, message = status_error error in
                      fail_with_audit
                        ~phase:(Some phase_text)
                        ~code
                        ~message
                    | Ok report_blocks ->
                      let%bind step_context =
                        match recommendation_detail recommendation "step" with
                        | Some (`String step_key) ->
                          In_thread.run (fun () ->
                            Sandwalk_store.read_step_context
                              ~database_path
                              ~step_key
                              ()
                            |> Result.map ~f:Option.some)
                        | _ -> Deferred.return (Ok None)
                      in
                      (match step_context with
                       | Error error ->
                         let code, message = status_error error in
                         fail_with_audit
                           ~phase:(Some phase_text)
                           ~code
                           ~message
                       | Ok step_context ->
                         let%bind finding_review_context =
                        if String.equal recommendation.action "review-finding"
                        then
                          In_thread.run (fun () ->
                            Sandwalk_store.read_finding_review_context
                              ~database_path
                              ~finding_reference:
                                (recommendation_detail_string_exn
                                   recommendation
                                   "finding")
                              ()
                            |> Result.map ~f:Option.some)
                        else Deferred.return (Ok None)
                      in
                      (match finding_review_context with
                       | Error error ->
                         let code, message = status_error error in
                         fail_with_audit
                           ~phase:(Some phase_text)
                           ~code
                           ~message
                       | Ok finding_review_context ->
                         let packet =
                           work_packet
                             ~workspace
                             ~slug
                             ~directory_prefix
                             ~phase
                             ~report_blocks
                             ~finding_review_context
                             ~step_context
                             recommendation
                           |> seal_work_packet
                         in
                      let packet_text = Yojson.Safe.pretty_to_string packet ^ "\n" in
                      let%bind directory_created =
                        Deferred.Or_error.try_with (fun () ->
                          Unix.mkdir ~p:() (Filename.dirname packet_path))
                      in
                      (match directory_created with
                       | Error _ ->
                         fail_with_audit
                           ~phase:(Some phase_text)
                           ~code:"WORKSPACE_IO_ERROR"
                           ~message:"Could not create work-packet directory."
                       | Ok () ->
                         let%bind written =
                           Sandwalk_runtime.Atomic_file.write
                             ~path:packet_path
                             ~temporary_suffix:invocation_id
                             packet_text
                         in
                         (match written with
                          | Error _ ->
                            fail_with_audit
                              ~phase:(Some phase_text)
                              ~code:"WORKSPACE_IO_ERROR"
                              ~message:"Could not write current work packet."
                          | Ok () ->
                            let finished_at = Time_float_unix.now () in
                            let duration_ms =
                              Time_float.diff finished_at started_at
                              |> Time_float.Span.to_ms
                              |> Float.iround_nearest_exn
                            in
                            let%bind logged =
                              append_event
                                ~kind:`Finished
                                ~timestamp:
                                  (Sandwalk_runtime.timestamp_utc finished_at)
                                ~phase:(Some phase_text)
                                ~state_changes:
                                  (if
                                     previous_schema_version
                                     < Sandwalk_store.current_schema_version
                                   then
                                     [ `Assoc
                                         [ "entity", `String "workspace.schema"
                                         ; "from", `Int previous_schema_version
                                         ; ( "to"
                                           , `Int
                                               Sandwalk_store
                                               .current_schema_version )
                                         ]
                                     ]
                                   else [])
                                ~duration_ms
                                ~outcome:"success"
                                ()
                            in
                            (match logged with
                             | Error _ ->
                               print_failure_and_exit
                                 ~code:"AUDIT_LOG_ERROR"
                                 ~message:"Could not append workspace audit log."
                             | Ok () ->
                               let result =
                                 match
                                   recommendation_result
                                     ~phase
                                     recommendation
                                 with
                                 | `Assoc fields ->
                                   `Assoc
                                     ([ "packet", `String packet_path
                                      ; ( "loop"
                                        , `String
                                            "Edit only editable; keep integrity_md5 unchanged; apply the packet; then run continue again." )
                                      ]
                                      @ fields)
                                 | _ -> assert false
                               in
                               (if
                                  Sandwalk_core.Phase.equal
                                    phase
                                    Sandwalk_core.Phase.Completed
                                then
                                  Sandwalk_protocol.Envelope.success ~result ()
                                else
                                  let next =
                                    Sandwalk_protocol.Shell_command.of_words
                                      [ "sandwalk"
                                      ; "apply"
                                      ; "--file"
                                      ; packet_path
                                      ]
                                  in
                                  Sandwalk_protocol.Envelope.success
                                    ~result
                                    ~next
                                    ())
                               |> Sandwalk_protocol.Envelope.render
                               |> print_endline;
                               Deferred.unit))))))))))
;;

let apply_command =
  Async.Command.async
    ~summary:"Validate and apply one current Sandwalk work packet."
    (let%map_open.Command packet_path =
       flag "--file" (required string) ~doc:"PATH Current work packet"
     in
     fun () ->
       let%bind packet_input =
         Sandwalk_runtime.File_input.read
           ~path:packet_path
           ~maximum_bytes:(3 * 1024 * 1024)
       in
       match packet_input with
       | Error _ ->
         print_failure_and_exit
           ~code:"WORK_PACKET_READ_ERROR"
           ~message:"Could not read the bounded work packet."
       | Ok packet_input ->
         let parsed =
           parse_work_packet
             ~packet_path
             ~content:(Sandwalk_runtime.File_input.content packet_input)
         in
         (match parsed with
          | Error error ->
            print_failure_and_exit
              ~code:"INVALID_WORK_PACKET"
              ~message:(work_packet_parse_error_message error)
          | Ok (packet, slug, directory_prefix, workspace) ->
            let action = json_string_member "action" packet in
            let fixed = json_member_assoc "fixed" packet in
            let editable = json_member_assoc "editable" packet in
            let workspace_arguments arguments =
              arguments
              @ [ "--slug"
                ; Sandwalk_core.Slug.to_string slug
                ; "--directory-prefix"
                ; directory_prefix
                ]
            in
            let input_path =
              Sandwalk_runtime.Workspace.work_input_path workspace
            in
            let reject_or_accept
                  ~editable
                  ~kind
                  ~reference
                  ~claim
                  ~accept_commands
              =
              match json_string_member "decision" editable with
              | "accept" -> `Commands accept_commands, None
              | ("reject" | "restart-search") as decision ->
                let reason =
                  json_string_member "rejection_reason" editable
                  |> String.strip
                in
                if String.is_empty reason
                then failwith "A rejection reason is required";
                let reason_path = input_path ^ "-rejection.md" in
                let replacement_query =
                  if String.equal decision "restart-search"
                  then (
                    let query =
                      json_string_member "replacement_query" editable
                      |> String.strip
                    in
                    if String.is_empty query
                    then failwith "A replacement search query is required";
                    Some query)
                  else None
                in
                ( `Reject (kind, reference, claim, replacement_query)
                , Some (reason_path, reason) )
              | _ -> failwith "Decision must be accept or reject"
            in
            let prepared =
              Or_error.try_with (fun () ->
                match action with
                | "run-command" ->
                  let arguments = json_string_list_member "arguments" fixed in
                  `Commands [ arguments ], None
                | "search" ->
                  let query = json_string_member "query" editable |> String.strip in
                  if String.is_empty query
                  then failwith "Search query must not be empty";
                  let source_root =
                    json_string_member "source_root" editable |> String.strip
                  in
                  if String.length source_root > 4_096
                  then failwith "Source root is too long";
                  let command =
                    workspace_arguments
                      ([ "search"
                       ; "--claim"
                       ; json_string_member "claim" fixed
                       ; "--query"
                       ; query
                       ]
                       @
                       if String.is_empty source_root
                       then []
                       else [ "--source-root"; source_root ])
                  in
                  `Commands [ command ], None
                | "fetch" ->
                  let claim = json_string_member "claim" fixed in
                  let hit = json_string_member "hit" fixed in
                  reject_or_accept
                    ~editable
                    ~kind:"hit"
                    ~reference:hit
                    ~claim
                    ~accept_commands:
                      [ workspace_arguments [ "fetch"; "--claim"; claim; hit ] ]
                | "create-excerpt" ->
                  let claim = json_string_member "claim" fixed in
                  let snapshot = json_string_member "snapshot" fixed in
                  let accept_commands =
                    match json_string_member "decision" editable with
                    | "accept" ->
                      let first = json_int_member "line_start" editable in
                      let last = json_int_member "line_end" editable in
                      if first < 1 || last < first
                      then failwith "Invalid inclusive excerpt line range";
                      [ workspace_arguments
                          [ "excerpt"
                          ; "create"
                          ; "--claim"
                          ; claim
                          ; "--snapshot"
                          ; snapshot
                          ; "--lines"
                          ; sprintf "%d:%d" first last
                          ]
                      ]
                    | _ -> []
                  in
                  reject_or_accept
                    ~editable
                    ~kind:"snapshot"
                    ~reference:snapshot
                    ~claim
                    ~accept_commands
                | "create-finding" ->
                  let claim = json_string_member "claim" fixed in
                  let excerpt = json_string_member "candidate_excerpt" fixed in
                  (match json_string_member "decision" editable with
                   | "reject" | "restart-search" ->
                     reject_or_accept
                       ~editable
                       ~kind:"excerpt"
                       ~reference:excerpt
                       ~claim
                       ~accept_commands:[]
                   | _ ->
                     let relation = json_string_member "relation" editable in
                     if
                       Option.is_none
                         (Sandwalk_core.Finding_relation.of_string relation)
                     then failwith "Invalid evidence relation";
                     let statement = json_string_member "statement" editable in
                     if String.is_empty (String.strip statement)
                     then failwith "Finding statement must not be empty";
                     let key = json_string_member "key" editable in
                     let step = json_string_member "step" fixed in
                     let finding = step ^ "/" ^ key in
                     let statement_path = input_path ^ ".md" in
                     ignore
                       (reject_or_accept
                          ~editable
                          ~kind:"excerpt"
                          ~reference:excerpt
                          ~claim
                          ~accept_commands:[]);
                     ( `Commands
                         [ workspace_arguments
                             [ "finding"
                             ; "create"
                             ; "--step"
                             ; step
                             ; "--claim"
                             ; claim
                             ; "--key"
                             ; key
                             ; "--claim-file"
                             ; statement_path
                             ]
                         ; workspace_arguments
                             [ "finding"
                             ; "attach"
                             ; "--claim"
                             ; claim
                             ; "--finding"
                             ; finding
                             ; "--excerpt"
                             ; excerpt
                             ; "--relation"
                             ; relation
                             ]
                         ; workspace_arguments
                             [ "finding"
                             ; "seal"
                             ; "--claim"
                             ; claim
                             ; "--finding"
                             ; finding
                             ]
                         ]
                     , Some (statement_path, statement) ))
                | "attach-evidence" ->
                  let claim = json_string_member "claim" fixed in
                  let finding = json_string_member "finding" fixed in
                  let excerpt = json_string_member "candidate_excerpt" fixed in
                  let accept_commands =
                    match json_string_member "decision" editable with
                    | "accept" ->
                      let relation = json_string_member "relation" editable in
                      if
                        Option.is_none
                          (Sandwalk_core.Finding_relation.of_string relation)
                      then failwith "Invalid evidence relation";
                      [ workspace_arguments
                          [ "finding"
                          ; "attach"
                          ; "--claim"
                          ; claim
                          ; "--finding"
                          ; finding
                          ; "--excerpt"
                          ; excerpt
                          ; "--relation"
                          ; relation
                          ]
                      ; workspace_arguments
                          [ "finding"
                          ; "seal"
                          ; "--claim"
                          ; claim
                          ; "--finding"
                          ; finding
                          ]
                      ]
                    | _ -> []
                  in
                  reject_or_accept
                    ~editable
                    ~kind:"excerpt"
                    ~reference:excerpt
                    ~claim
                    ~accept_commands
                | "review-finding" ->
                  let review = json_member_assoc "review" editable in
                  let review_path = input_path ^ ".json" in
                  ( `Commands
                      [ workspace_arguments
                          [ "finding"
                          ; "review"
                          ; "--claim"
                          ; json_string_member "claim" fixed
                          ; "--finding"
                          ; json_string_member "finding" fixed
                          ; "--review-file"
                          ; review_path
                          ]
                      ]
                  , Some (review_path, Yojson.Safe.to_string review ^ "\n") )
                | "submit-report" ->
                  let report = json_string_member "report_markdown" editable in
                  if String.is_empty (String.strip report)
                  then failwith "Report Markdown must not be empty";
                  let report_path = input_path ^ ".md" in
                  ( `Commands
                      [ workspace_arguments
                          [ "draft"
                          ; "submit"
                          ; "--report-file"
                          ; report_path
                          ]
                      ]
                  , Some (report_path, report) )
                | "review-report" ->
                  let revision = json_int_member "report_revision" fixed in
                  let reviews = json_member_assoc "reviews" editable in
                  let review_path = input_path ^ ".json" in
                  let review =
                    `Assoc
                      [ "protocol", `String "sandwalk.report-review.v1"
                      ; "report_revision", `Int revision
                      ; "blocks", reviews
                      ]
                  in
                  ( `Commands
                      [ workspace_arguments
                          [ "draft"
                          ; "review"
                          ; "--review-file"
                          ; review_path
                          ]
                      ]
                  , Some (review_path, Yojson.Safe.to_string review ^ "\n") )
                | _ -> failwith "Unsupported work packet action")
            in
            (match prepared with
             | Error _ ->
               print_failure_and_exit
                 ~code:"INVALID_WORK_PACKET"
                 ~message:
                   "Fill every editable field with a valid value and retry apply."
             | Ok (operation, input) ->
               let started_at = Time_float_unix.now () in
               let%bind invocation_id =
                 In_thread.run (fun () ->
                   Sandwalk_runtime.invocation_id ~now:started_at)
               in
               let phase_text = json_string_member "phase" packet in
               let append_event
                     ~kind
                     ~timestamp
                     ?duration_ms
                     ?outcome
                     ?error_code
                     ()
                 =
                 Sandwalk_runtime.Audit.append
                   ~path:(Sandwalk_runtime.Workspace.events_path workspace)
                   (Sandwalk_protocol.Audit_event.create
                      ~invocation_id
                      ~timestamp
                      ~kind
                      ~command:"apply"
                      ~arguments:
                        (`Assoc
                           [ "file", `String packet_path
                           ; ( "slug"
                             , `String (Sandwalk_core.Slug.to_string slug) )
                           ; "directory_prefix", `String directory_prefix
                           ])
                      ~phase:(Some phase_text)
                      ~raw_argv:(Sys.get_argv () |> Array.to_list)
                      ~state_changes:[]
                      ?duration_ms
                      ?outcome
                      ?error_code
                      ())
               in
               let finish_event ~kind ~outcome ?error_code () =
                 let finished_at = Time_float_unix.now () in
                 let duration_ms =
                   Time_float.diff finished_at started_at
                   |> Time_float.Span.to_ms
                   |> Float.iround_nearest_exn
                 in
                 append_event
                   ~kind
                   ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                   ~duration_ms
                   ~outcome
                   ?error_code
                   ()
               in
               let%bind started =
                 append_event
                   ~kind:`Started
                   ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
                   ()
               in
               (match started with
                | Error _ ->
                  print_failure_and_exit
                    ~code:"AUDIT_LOG_ERROR"
                    ~message:"Could not append workspace audit log."
                | Ok () ->
                  let%bind input_written =
                    match input with
                    | None -> Deferred.return (Ok ())
                    | Some (path, content) ->
                      Sandwalk_runtime.Atomic_file.write
                        ~path
                        ~temporary_suffix:invocation_id
                        content
                  in
                  (match input_written with
                   | Error _ ->
                     let%bind _ =
                       finish_event
                         ~kind:`Failed
                         ~outcome:"failure"
                         ~error_code:"WORKSPACE_IO_ERROR"
                         ()
                     in
                     print_failure_and_exit
                       ~code:"WORKSPACE_IO_ERROR"
                       ~message:"Could not materialize work-packet input."
                   | Ok () ->
                     let rec run_commands = function
                       | [] -> Deferred.return (Ok ())
                       | command :: rest ->
                         let%bind output = run_self_command command in
                         (match
                            Core_unix.Exit_or_signal.or_error output.exit_status
                          with
                          | Ok () -> run_commands rest
                          | Error _ ->
                            if not (String.is_empty output.stdout)
                            then print_string output.stdout;
                            if not (String.is_empty output.stderr)
                            then eprintf "%s" output.stderr;
                            Deferred.return (Error ()))
                     in
                     let%bind applied =
                       match operation with
                       | `Commands commands -> run_commands commands
                       | `Reject
                           ( kind_text
                           , reference
                           , claim_text
                           , replacement_query ) ->
                         let rejection =
                           Or_error.try_with (fun () ->
                             let kind =
                               Sandwalk_core.Candidate_kind.of_string kind_text
                               |> Option.value_exn
                             in
                             let claim_id =
                               Sandwalk_core.Claim_id.of_string claim_text
                               |> Option.value_exn
                             in
                             let reason_path, reason_text =
                               Option.value_exn input
                             in
                             kind, claim_id, reason_path, reason_text)
                         in
                         (match rejection with
                          | Error _ -> Deferred.return (Error ())
                          | Ok (kind, claim_id, reason_path, reason_text) ->
                            let%bind rejected =
                              In_thread.run (fun () ->
                                Sandwalk_store.reject_candidate
                                  ~database_path:
                                    (Sandwalk_runtime.Workspace.database_path
                                       workspace)
                                  ~expected_slug:slug
                                  ~claim_id
                                  ~kind
                                  ~reference
                                  ~reason_text
                                  ~reason_path
                                  ~reason_md5:
                                    (Md5.digest_string reason_text
                                     |> Md5.to_hex)
                                  ~reason_size:(String.length reason_text)
                                  ~now:
                                    (Sandwalk_runtime.timestamp_utc
                                       started_at)
                                  ())
                            in
                            (match rejected with
                             | Ok _ ->
                               (match replacement_query with
                                | None -> Deferred.return (Ok ())
                                | Some query ->
                                  run_commands
                                    [ workspace_arguments
                                        [ "search"
                                        ; "--claim"
                                        ; claim_text
                                        ; "--query"
                                        ; query
                                        ]
                                    ])
                             | Error error ->
                               let code, message = candidate_error error in
                               Sandwalk_protocol.Envelope.failure
                                 ~code
                                 ~message
                                 ()
                               |> Sandwalk_protocol.Envelope.render
                               |> print_endline;
                               Deferred.return (Error ())))
                     in
                     (match applied with
                      | Error () ->
                        let%bind _ =
                          finish_event
                            ~kind:`Failed
                            ~outcome:"failure"
                            ~error_code:"APPLY_COMMAND_FAILED"
                            ()
                        in
                        Shutdown.exit 1
                      | Ok () ->
                        let%bind logged =
                          finish_event ~kind:`Finished ~outcome:"success" ()
                        in
                        (match logged with
                         | Error _ ->
                           print_failure_and_exit
                             ~code:"AUDIT_LOG_ERROR"
                             ~message:"Could not append workspace audit log."
                         | Ok () ->
                           let next =
                             Sandwalk_protocol.Shell_command.of_words
                               [ "sandwalk"
                               ; "continue"
                               ; "--slug"
                               ; Sandwalk_core.Slug.to_string slug
                               ; "--directory-prefix"
                               ; directory_prefix
                               ]
                           in
                           Sandwalk_protocol.Envelope.success
                             ~result:
                               (`Assoc
                                  [ "applied", `String action
                                  ; "packet", `String packet_path
                                  ])
                             ~next
                             ()
                           |> Sandwalk_protocol.Envelope.render
                           |> print_endline;
                           Deferred.unit)))))))
;;

let next_command =
  Async.Command.async
    ~summary:"Recommend one deterministic command from durable workspace state."
    (let%map_open.Command slug_text =
       flag "--slug" (required string) ~doc:"SLUG Workspace slug"
     and directory_prefix =
       flag "--directory-prefix" (optional string) ~doc:"PATH Workspace parent"
     in
     fun () ->
       match Sandwalk_core.Slug.of_string slug_text with
       | Error error ->
         print_failure_and_exit
           ~code:"INVALID_SLUG"
           ~message:(Sandwalk_core.Slug.Error.message error)
       | Ok slug ->
         let directory_prefix =
           Sandwalk_runtime.resolve_directory_prefix
             ~command_line:directory_prefix
         in
         let workspace =
           Sandwalk_runtime.Workspace.resolve ~directory_prefix ~slug
         in
         let database_path =
           Sandwalk_runtime.Workspace.database_path workspace
         in
         let arguments = parsed_arguments ~slug ~directory_prefix in
         let%bind database_exists = Async.Sys.file_exists_exn database_path in
         if not database_exists
         then
           print_failure_and_exit
             ~code:"WORKSPACE_NOT_FOUND"
             ~message:"Workspace does not exist."
         else (
           let started_at = Time_float_unix.now () in
           let%bind invocation_id =
             In_thread.run (fun () ->
               Sandwalk_runtime.invocation_id ~now:started_at)
           in
           let append_event
                 ~kind
                 ~timestamp
                 ~phase
                 ?(state_changes = [])
                 ?duration_ms
                 ?outcome
                 ?error_code
                 ()
             =
             Sandwalk_runtime.Audit.append
               ~path:(Sandwalk_runtime.Workspace.events_path workspace)
               (Sandwalk_protocol.Audit_event.create
                  ~invocation_id
                  ~timestamp
                  ~kind
                  ~command:"next"
                  ~arguments
                  ~phase
                  ~raw_argv:(Sys.get_argv () |> Array.to_list)
                  ~state_changes
                  ?duration_ms
                  ?outcome
                  ?error_code
                  ())
           in
           let%bind started =
             append_event
               ~kind:`Started
               ~timestamp:(Sandwalk_runtime.timestamp_utc started_at)
               ~phase:None
               ()
           in
           match started with
           | Error _ ->
             print_failure_and_exit
               ~code:"AUDIT_LOG_ERROR"
               ~message:"Could not append workspace audit log."
           | Ok () ->
             let%bind migrated_and_status =
               In_thread.run (fun () ->
                 let open Result.Let_syntax in
                 let%bind previous_schema_version =
                   Sandwalk_store.migrate_workspace
                     ~database_path
                     ~expected_slug:slug
                     ~now:(Sandwalk_runtime.timestamp_utc started_at)
                     ()
                 in
                 let%map status =
                   Sandwalk_store.read_status
                     ~database_path
                     ~expected_slug:slug
                     ()
                 in
                 previous_schema_version, status)
             in
             (match migrated_and_status with
              | Error error ->
                let code, message = status_error error in
                let%bind _ =
                  append_event
                    ~kind:`Failed
                    ~timestamp:
                      (Sandwalk_runtime.timestamp_utc (Time_float_unix.now ()))
                    ~phase:None
                    ~outcome:"failure"
                    ~error_code:code
                    ()
                in
                print_failure_and_exit ~code ~message
              | Ok (previous_schema_version, status) ->
                let phase = Sandwalk_store.Workspace_status.phase status in
                let%bind recommendation =
                  recommendation_for_phase
                    ~database_path
                    ~slug
                    ~directory_prefix
                    ~phase
                in
                let phase_text = Sandwalk_core.Phase.to_string phase in
                (match recommendation with
                 | Error error ->
                   let code, message = status_error error in
                   let%bind _ =
                     append_event
                       ~kind:`Failed
                       ~timestamp:
                         (Sandwalk_runtime.timestamp_utc
                            (Time_float_unix.now ()))
                       ~phase:(Some phase_text)
                       ~outcome:"failure"
                       ~error_code:code
                       ()
                   in
                   print_failure_and_exit ~code ~message
                 | Ok recommendation ->
                   let command =
                     Sandwalk_protocol.Shell_command.of_words
                       recommendation.words
                   in
                   let finished_at = Time_float_unix.now () in
                   let duration_ms =
                     Time_float.diff finished_at started_at
                     |> Time_float.Span.to_ms
                     |> Float.iround_nearest_exn
                   in
                   let%bind logged =
                     append_event
                       ~kind:`Finished
                       ~timestamp:(Sandwalk_runtime.timestamp_utc finished_at)
                       ~phase:(Some phase_text)
                       ~state_changes:
                         (if
                            previous_schema_version
                            < Sandwalk_store.current_schema_version
                          then
                            [ `Assoc
                                [ "entity", `String "workspace.schema"
                                ; "from", `Int previous_schema_version
                                ; ( "to"
                                  , `Int
                                      Sandwalk_store.current_schema_version )
                                ]
                            ]
                          else [])
                       ~duration_ms
                       ~outcome:"success"
                       ()
                   in
                   (match logged with
                    | Error _ ->
                      print_failure_and_exit
                        ~code:"AUDIT_LOG_ERROR"
                        ~message:"Could not append workspace audit log."
                    | Ok () ->
                      Sandwalk_protocol.Envelope.success
                        ~result:(recommendation_result ~phase recommendation)
                        ~next:command
                        ()
                      |> Sandwalk_protocol.Envelope.render
                      |> print_endline;
                      Deferred.unit)))))
;;

let command =
  Async.Command.group
    ~summary:"Deterministic research orchestration for AI agents."
    [ "about", about_command
    ; "apply", apply_command
    ; "continue", continue_command
    ; "draft", draft_command
    ; "explain", explain_command
    ; "excerpt", excerpt_command
    ; "export", export_command
    ; "fetch", fetch_command
    ; "finding", finding_command
    ; "finalize", finalize_command
    ; "gc", gc_command
    ; "init", init_command
    ; "list", list_command
    ; "next", next_command
    ; "plan", plan_command
    ; "recon", recon_command
    ; "resume", resume_command
    ; "search", search_command
    ; "snapshot", snapshot_command
    ; "status", status_command
    ; "step", step_command
    ]
;;

let () = Command_unix.run command
