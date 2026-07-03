let check database return_code =
  if not (Sqlite3.Rc.is_success return_code)
  then failwith (Sqlite3.errmsg database)
;;

let print_query database sql =
  check
    database
    (Sqlite3.exec database sql ~cb:(fun row _headers ->
       row
       |> Array.to_list
       |> List.map (Option.value ~default:"NULL")
       |> String.concat "|"
       |> print_endline))
;;

let create_v1 database slug =
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE workspaces (
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (1, '2026-01-01 00:00:00Z');
PRAGMA user_version = 1;
PRAGMA journal_mode = WAL;
|});
  let statement =
    Sqlite3.prepare
      database
      {|
INSERT INTO workspaces (singleton, slug, phase, created_at, updated_at)
VALUES (1, ?1, 'initialized', '2026-01-01 00:00:00Z', '2026-01-01 00:00:00Z')
|}
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    (fun () ->
      check database (Sqlite3.bind_text statement 1 slug);
      check database (Sqlite3.step statement))
;;

let create_v2 database slug =
  create_v1 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO plan_metadata (singleton, revision) VALUES (1, 1);
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES ('fixture-step', 'Fixture step', 1, 1, '2026-01-01 00:00:00Z');
INSERT INTO schema_migrations (version, applied_at)
VALUES (2, '2026-01-01 00:00:00Z');
UPDATE workspaces SET phase = 'planning';
PRAGMA user_version = 2;
|})
;;

let create_v3 database slug =
  create_v2 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE plan_metadata ADD COLUMN validated_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN validated_at TEXT;
UPDATE plan_metadata
SET validated_revision = 1, validated_at = '2026-01-01 00:00:00Z';
INSERT INTO schema_migrations (version, applied_at)
VALUES (3, '2026-01-01 00:00:00Z');
PRAGMA user_version = 3;
|})
;;

let create_v4 database slug =
  create_v3 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE plan_metadata ADD COLUMN sealed_revision INTEGER;
ALTER TABLE plan_metadata ADD COLUMN sealed_at TEXT;
UPDATE plan_metadata
SET sealed_revision = 1, sealed_at = '2026-01-01 00:00:00Z';
UPDATE workspaces SET phase = 'researching';
INSERT INTO schema_migrations (version, applied_at)
VALUES (4, '2026-01-01 00:00:00Z');
PRAGMA user_version = 4;
|})
;;

let create_v5 database slug =
  create_v4 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO step_executions (
  step_key, state, active_claim_id, lease_expires_unix_seconds, attempt
) VALUES (
  'fixture-step', 'claimed', 'claim_00000000000000000000000000000001',
  4102444800, 1
);
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds
) VALUES (
  'claim_00000000000000000000000000000001', 'fixture-step', 1,
  '2026-01-01 00:00:00Z', '2100-01-01 00:00:00Z', 4102444800
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (5, '2026-01-01 00:00:00Z');
PRAGMA user_version = 5;
|})
;;

let create_v6 database slug =
  create_v5 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
ALTER TABLE claims ADD COLUMN lease_duration_seconds INTEGER
  CHECK (lease_duration_seconds BETWEEN 30 AND 86400);
UPDATE claims SET lease_duration_seconds = 900;
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (6, '2026-01-01 00:00:00Z');
PRAGMA user_version = 6;
|})
;;

let create_v7 database slug =
  create_v6 database slug;
  check
    database
    (Sqlite3.exec
       database
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
UPDATE plan_metadata
SET revision = 2, validated_revision = 2, sealed_revision = 2;
INSERT INTO plan_steps (step_key, title, position, required, created_at)
VALUES (
  'completed-step', 'Completed fixture step', 2, 1,
  '2026-01-01 00:00:00Z'
);
INSERT INTO step_executions (
  step_key, state, active_claim_id, lease_expires_unix_seconds, attempt
) VALUES ('completed-step', 'completed', NULL, NULL, 1);
INSERT INTO claims (
  claim_id, step_key, attempt, issued_at, lease_expires_at,
  lease_expires_unix_seconds, ended_at, end_reason, lease_duration_seconds
) VALUES (
  'claim_00000000000000000000000000000002', 'completed-step', 1,
  '2026-01-01 00:00:00Z', '2026-01-01 00:15:00Z', 1767226500,
  '2026-01-01 00:10:00Z', 'completed', 900
);
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
) VALUES (
  'fixture query', 'researching',
  'claim_00000000000000000000000000000001', 'fixture-step',
  'fixture-search', '2026-01-01 00:00:00Z'
);
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (
  'hit_00000000000000000000000000000001', 1, 1,
  'https://example.test/start', 'Fixture result', 'Fixture snippet.'
);
INSERT INTO search_queries (
  query, phase, claim_id, step_key, adapter, created_at
) VALUES (
  'completed fixture query', 'researching',
  'claim_00000000000000000000000000000002', 'completed-step',
  'fixture-search', '2026-01-01 00:00:00Z'
);
INSERT INTO search_hits (hit_ref, query_id, position, url, title, snippet)
VALUES (
  'hit_00000000000000000000000000000002', 2, 1,
  'https://example.test/completed', 'Completed result', 'Completed snippet.'
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (7, '2026-01-01 00:00:00Z');
PRAGMA user_version = 7;
|})
;;

let create_v8 database slug =
  create_v7 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (8, '2026-01-01 00:00:00Z');
PRAGMA user_version = 8;
|});
  let statement =
    Sqlite3.prepare
      database
      {|
INSERT INTO snapshots (
  snapshot_ref, hit_ref, claim_id, step_key, artifact_path, final_url,
  input_sha256, markdown_sha256, manifest_json, retrieved_at
) VALUES (
  'snap_00000000000000000000000000000001',
  'hit_00000000000000000000000000000001',
  'claim_00000000000000000000000000000001',
  'fixture-step', ?1, 'https://example.test/final', ?2, ?3, '{}',
  '2026-01-01 00:00:00Z'
)
|}
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    (fun () ->
      check
        database
        (Sqlite3.bind_text
           statement
           1
           ("workspace/"
            ^ slug
            ^ "/artifacts/snapshots/snap_00000000000000000000000000000001"));
      check database (Sqlite3.bind_text statement 2 (String.make 64 'a'));
      check database (Sqlite3.bind_text statement 3 (String.make 64 'b'));
      check database (Sqlite3.step statement))
;;

let create_v9 database slug =
  create_v8 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (9, '2026-01-01 00:00:00Z');
PRAGMA user_version = 9;
|})
;;

let create_v10 database slug =
  create_v9 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO excerpts (
  excerpt_ref, snapshot_ref, claim_id, step_key, artifact_path,
  markdown_sha256, line_start, line_end, byte_start, byte_end,
  excerpt_md5, excerpt_size, created_at
) VALUES (
  'excerpt_00000000000000000000000000000001',
  'snap_00000000000000000000000000000001',
  'claim_00000000000000000000000000000001', 'fixture-step',
  'fixture-excerpt.md',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  1, 1, 0, 7, 'bfc1041d408b88953eacd86820332d8c', 7,
  '2026-01-01 00:00:00Z'
);
INSERT INTO findings (
  step_key, finding_key, current_revision, state, created_at, updated_at
) VALUES (
  'fixture-step', 'fixture-finding', 1, 'draft',
  '2026-01-01 00:00:00Z', '2026-01-01 00:00:00Z'
);
INSERT INTO finding_revisions (
  step_key, finding_key, revision, claim_text, claim_md5, claim_size, created_at
) VALUES (
  'fixture-step', 'fixture-finding', 1, 'Fixture claim.',
  'dddddddddddddddddddddddddddddddd', 14, '2026-01-01 00:00:00Z'
);
INSERT INTO findings (
  step_key, finding_key, current_revision, state, created_at, updated_at
) VALUES (
  'fixture-step', 'sealed-finding', 1, 'sealed',
  '2026-01-01 00:00:00Z', '2026-01-01 00:00:00Z'
);
INSERT INTO finding_revisions (
  step_key, finding_key, revision, claim_text, claim_md5, claim_size,
  created_at, sealed_at
) VALUES (
  'fixture-step', 'sealed-finding', 1, 'Sealed claim.',
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 13,
  '2026-01-01 00:00:00Z', '2026-01-01 00:00:00Z'
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (10, '2026-01-01 00:00:00Z');
PRAGMA user_version = 10;
|})
;;

let create_v11 database slug =
  create_v10 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO finding_evidence (
  step_key, finding_key, revision, excerpt_ref, relation, attached_at
) VALUES (
  'fixture-step', 'sealed-finding', 1,
  'excerpt_00000000000000000000000000000001', 'supports',
  '2026-01-01 00:00:00Z'
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (11, '2026-01-01 00:00:00Z');
PRAGMA user_version = 11;
|})
;;

let create_v12 database slug =
  create_v11 database slug;
  check
    database
    (Sqlite3.exec
       database
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
DELETE FROM finding_revisions
WHERE step_key = 'fixture-step' AND finding_key = 'fixture-finding';
DELETE FROM findings
WHERE step_key = 'fixture-step' AND finding_key = 'fixture-finding';
INSERT INTO finding_reviews (
  step_key, finding_key, revision, verdict, summary, source_quality,
  conflicts, qualifications, review_json, review_md5, reviewed_at
) VALUES (
  'fixture-step', 'sealed-finding', 1, 'supported', 'Supported fixture.',
  'Primary source.', '', '', '{}',
  'ffffffffffffffffffffffffffffffff', '2026-01-01 00:00:00Z'
);
UPDATE findings SET state = 'reviewed'
WHERE step_key = 'fixture-step' AND finding_key = 'sealed-finding';
UPDATE step_executions
SET state = 'completed', active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE step_key = 'fixture-step';
UPDATE claims
SET ended_at = '2026-01-01 00:00:00Z', end_reason = 'completed'
WHERE claim_id = 'claim_00000000000000000000000000000001';
UPDATE workspaces SET phase = 'drafting';
INSERT INTO schema_migrations (version, applied_at)
VALUES (12, '2026-01-01 00:00:00Z');
PRAGMA user_version = 12;
|})
;;

let create_v13 database slug =
  create_v12 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO reports (
  revision, report_path, report_text, report_md5, report_size, submitted_at, current
) VALUES (
  1, 'fixture-report.md',
  '# Fixture

Supported fixture. [cite:fixture-step/sealed-finding]
',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 64,
  '2026-01-01 00:00:00Z', 1
);
INSERT INTO report_blocks (
  report_revision, ordinal, block_text, block_md5, citations_json
) VALUES
  (1, 1, '# Fixture', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '[]'),
  (1, 2, 'Supported fixture.', 'cccccccccccccccccccccccccccccccc',
   '["fixture-step/sealed-finding"]');
UPDATE workspaces SET phase = 'draft-review';
INSERT INTO schema_migrations (version, applied_at)
VALUES (13, '2026-01-01 00:00:00Z');
PRAGMA user_version = 13;
|})
;;

let create_v14 database slug =
  create_v13 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO report_block_reviews (
  report_revision, ordinal, verdict, summary, block_md5, reviewed_at
) VALUES
  (1, 1, 'supported', 'Heading is consistent.',
   'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '2026-01-01 00:00:00Z'),
  (1, 2, 'supported', 'Claim is supported.',
   'cccccccccccccccccccccccccccccccc', '2026-01-01 00:00:00Z');
UPDATE workspaces SET phase = 'finalizing';
INSERT INTO schema_migrations (version, applied_at)
VALUES (14, '2026-01-01 00:00:00Z');
PRAGMA user_version = 14;
|})
;;

let create_v15 database slug =
  create_v14 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE finalizations (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  report_revision INTEGER NOT NULL REFERENCES reports(revision),
  final_report_md5 TEXT NOT NULL CHECK (length(final_report_md5) = 32),
  sources_md5 TEXT NOT NULL CHECK (length(sources_md5) = 32),
  source_count INTEGER NOT NULL CHECK (source_count >= 1),
  completed_at TEXT NOT NULL
);
UPDATE workspaces SET phase = 'completed';
INSERT INTO finalizations (
  singleton, report_revision, final_report_md5, sources_md5,
  source_count, completed_at
) VALUES (
  1, 1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 1, '2026-01-01 00:00:00Z'
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (15, '2026-01-01 00:00:00Z');
PRAGMA user_version = 15;
|})
;;

let create_v16 database slug =
  create_v15 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO plan_objective (
  singleton, objective_text, objective_path, objective_md5,
  objective_size, updated_at
) VALUES (
  1, 'Fixture objective.', 'objective.md',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 18, '2026-01-01 00:00:00Z'
);
INSERT INTO plan_dependencies (step_key, dependency_key, created_at)
VALUES ('completed-step', 'fixture-step', '2026-01-01 00:00:00Z');
INSERT INTO schema_migrations (version, applied_at)
VALUES (16, '2026-01-01 00:00:00Z');
PRAGMA user_version = 16;
|})
;;

let create_v17 database slug =
  create_v16 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (17, '2026-01-01 00:00:00Z');
PRAGMA user_version = 17;
|})
;;

let create_v18 database slug =
  create_v17 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE raw_gc_plan (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  plan_path TEXT NOT NULL,
  plan_json TEXT NOT NULL,
  plan_md5 TEXT NOT NULL CHECK (length(plan_md5) = 32),
  created_at TEXT NOT NULL,
  applied_at TEXT
);
INSERT INTO schema_migrations (version, applied_at)
VALUES (18, '2026-01-01 00:00:00Z');
PRAGMA user_version = 18;
|})
;;

let create_v19 database slug =
  create_v18 database slug;
  check
    database
    (Sqlite3.exec
       database
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
INSERT INTO schema_migrations (version, applied_at)
VALUES (19, '2026-01-01 00:00:00Z');
PRAGMA user_version = 19;
|})
;;

let create_v20 database slug =
  create_v19 database slug;
  check
    database
    (Sqlite3.exec
       database
       {|
CREATE TABLE snapshot_promotions (
  snapshot_ref TEXT PRIMARY KEY REFERENCES snapshots(snapshot_ref),
  step_key TEXT NOT NULL REFERENCES plan_steps(step_key),
  claim_id TEXT NOT NULL REFERENCES claims(claim_id),
  promoted_at TEXT NOT NULL
);
UPDATE step_executions
SET state = 'expired',
    active_claim_id = NULL,
    lease_expires_unix_seconds = NULL
WHERE step_key = 'fixture-step';
UPDATE claims
SET ended_at = '2026-01-01 00:15:00Z',
    end_reason = 'expired'
WHERE claim_id = 'claim_00000000000000000000000000000001';
INSERT INTO schema_migrations (version, applied_at)
VALUES (20, '2026-01-01 00:00:00Z');
PRAGMA user_version = 20;
|})
;;

let inspect database =
  print_query database "SELECT slug, phase FROM workspaces";
  print_query database "PRAGMA user_version";
  print_query database "PRAGMA journal_mode";
  print_query database "PRAGMA integrity_check"
;;

let inspect_claims database =
  print_query
    database
    {|
SELECT step_key, state, attempt, length(active_claim_id),
       lease_expires_unix_seconds IS NOT NULL
FROM step_executions
ORDER BY step_key
|};
  print_query
    database
    {|
SELECT step_key, attempt, COALESCE(end_reason, 'NULL')
FROM claims
ORDER BY step_key, attempt
|}
;;

let inspect_checkpoints database =
  print_query
    database
    {|
SELECT step_key, checkpoint_number, summary, next,
       length(summary_md5), summary_size, length(next_md5), next_size
FROM checkpoints
ORDER BY checkpoint_id
|}
;;

let inspect_hits database =
  print_query
    database
    {|
SELECT length(hit_ref), position, url, title, snippet
FROM search_hits
ORDER BY position
|}
;;

let inspect_snapshots database =
  print_query
    database
    {|
SELECT length(snapshot_ref), hit_ref, final_url,
       length(input_sha256), length(markdown_sha256), artifact_path
FROM snapshots
ORDER BY retrieved_at, snapshot_ref
|}
;;

let inspect_excerpts database =
  print_query
    database
    {|
SELECT length(excerpt_ref), snapshot_ref, line_start, line_end,
       byte_start, byte_end, length(excerpt_md5), excerpt_size
FROM excerpts
ORDER BY byte_start, byte_end
|}
;;

let inspect_findings database =
  print_query
    database
    {|
SELECT f.step_key, f.finding_key, f.current_revision, f.state,
       length(r.claim_md5), r.claim_size, r.claim_text
FROM findings AS f
JOIN finding_revisions AS r
  ON r.step_key = f.step_key AND r.finding_key = f.finding_key
ORDER BY f.step_key, f.finding_key, r.revision
|}
;;

let inspect_evidence database =
  print_query
    database
    {|
SELECT step_key, finding_key, revision, excerpt_ref, relation
FROM finding_evidence
ORDER BY step_key, finding_key, revision, excerpt_ref, relation
|}
;;

let inspect_reviews database =
  print_query
    database
    {|
SELECT step_key, finding_key, revision, verdict, length(review_md5), summary
FROM finding_reviews
ORDER BY step_key, finding_key, revision
|}
;;

let inspect_reports database =
  print_query
    database
    {|
SELECT revision, length(report_md5), report_size, current
FROM reports
ORDER BY revision
|};
  print_query
    database
    {|
SELECT report_revision, ordinal, length(block_md5), citations_json
FROM report_blocks
ORDER BY report_revision, ordinal
|}
;;

let inspect_block_reviews database =
  print_query
    database
    {|
SELECT report_revision, ordinal, verdict, length(block_md5), summary
FROM report_block_reviews
ORDER BY report_revision, ordinal
|}
;;

let inspect_finalization database =
  print_query
    database
    {|
SELECT report_revision, length(final_report_md5), length(sources_md5),
       source_count
FROM finalizations
|}
;;

let inspect_recon database =
  print_query
    database
    {|
SELECT goal_text, summary_text, finished_at IS NOT NULL
FROM reconnaissance
|};
  print_query
    database
    {|
SELECT observation_id, observation_text
FROM reconnaissance_observations
ORDER BY observation_id
|}
;;

let inspect_extensions database =
  print_query
    database
    {|
SELECT revision, step_key, reason_text, length(reason_md5), reason_size
FROM plan_extensions
ORDER BY revision
|}
;;

let inspect_promotions database =
  print_query
    database
    {|
SELECT snapshot_ref, step_key, claim_id
FROM snapshot_promotions
ORDER BY snapshot_ref
|}
;;

let () =
  let action, path =
    match Sys.argv with
    | [| _; "--create-v1"; path; slug |] -> `Create (1, slug), path
    | [| _; "--create-v2"; path; slug |] -> `Create (2, slug), path
    | [| _; "--create-v3"; path; slug |] -> `Create (3, slug), path
    | [| _; "--create-v4"; path; slug |] -> `Create (4, slug), path
    | [| _; "--create-v5"; path; slug |] -> `Create (5, slug), path
    | [| _; "--create-v6"; path; slug |] -> `Create (6, slug), path
    | [| _; "--create-v7"; path; slug |] -> `Create (7, slug), path
    | [| _; "--create-v8"; path; slug |] -> `Create (8, slug), path
    | [| _; "--create-v9"; path; slug |] -> `Create (9, slug), path
    | [| _; "--create-v10"; path; slug |] -> `Create (10, slug), path
    | [| _; "--create-v11"; path; slug |] -> `Create (11, slug), path
    | [| _; "--create-v12"; path; slug |] -> `Create (12, slug), path
    | [| _; "--create-v13"; path; slug |] -> `Create (13, slug), path
    | [| _; "--create-v14"; path; slug |] -> `Create (14, slug), path
    | [| _; "--create-v15"; path; slug |] -> `Create (15, slug), path
    | [| _; "--create-v16"; path; slug |] -> `Create (16, slug), path
    | [| _; "--create-v17"; path; slug |] -> `Create (17, slug), path
    | [| _; "--create-v18"; path; slug |] -> `Create (18, slug), path
    | [| _; "--create-v19"; path; slug |] -> `Create (19, slug), path
    | [| _; "--create-v20"; path; slug |] -> `Create (20, slug), path
    | [| _; "--inspect-claims"; path |] -> `Inspect_claims, path
    | [| _; "--inspect-checkpoints"; path |] -> `Inspect_checkpoints, path
    | [| _; "--inspect-hits"; path |] -> `Inspect_hits, path
    | [| _; "--inspect-snapshots"; path |] -> `Inspect_snapshots, path
    | [| _; "--inspect-excerpts"; path |] -> `Inspect_excerpts, path
    | [| _; "--inspect-findings"; path |] -> `Inspect_findings, path
    | [| _; "--inspect-evidence"; path |] -> `Inspect_evidence, path
    | [| _; "--inspect-reviews"; path |] -> `Inspect_reviews, path
    | [| _; "--inspect-reports"; path |] -> `Inspect_reports, path
    | [| _; "--inspect-block-reviews"; path |] -> `Inspect_block_reviews, path
    | [| _; "--inspect-finalization"; path |] -> `Inspect_finalization, path
    | [| _; "--inspect-recon"; path |] -> `Inspect_recon, path
    | [| _; "--inspect-extensions"; path |] -> `Inspect_extensions, path
    | [| _; "--inspect-promotions"; path |] -> `Inspect_promotions, path
    | [| _; "--set-legacy-deadline"; path; step |] ->
      `Set_legacy_deadline step, path
    | [| _; path |] -> `Inspect, path
    | _ -> failwith "usage: inspect_workspace [--create-v1] DATABASE [SLUG]"
  in
  let database = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
    (fun () ->
      match action with
      | `Create (1, slug) -> create_v1 database slug
      | `Create (2, slug) -> create_v2 database slug
      | `Create (3, slug) -> create_v3 database slug
      | `Create (4, slug) -> create_v4 database slug
      | `Create (5, slug) -> create_v5 database slug
      | `Create (6, slug) -> create_v6 database slug
      | `Create (7, slug) -> create_v7 database slug
      | `Create (8, slug) -> create_v8 database slug
      | `Create (9, slug) -> create_v9 database slug
      | `Create (10, slug) -> create_v10 database slug
      | `Create (11, slug) -> create_v11 database slug
      | `Create (12, slug) -> create_v12 database slug
      | `Create (13, slug) -> create_v13 database slug
      | `Create (14, slug) -> create_v14 database slug
      | `Create (15, slug) -> create_v15 database slug
      | `Create (16, slug) -> create_v16 database slug
      | `Create (17, slug) -> create_v17 database slug
      | `Create (18, slug) -> create_v18 database slug
      | `Create (19, slug) -> create_v19 database slug
      | `Create (20, slug) -> create_v20 database slug
      | `Create _ -> assert false
      | `Inspect -> inspect database
      | `Inspect_claims -> inspect_claims database
      | `Inspect_checkpoints -> inspect_checkpoints database
      | `Inspect_hits -> inspect_hits database
      | `Inspect_snapshots -> inspect_snapshots database
      | `Inspect_excerpts -> inspect_excerpts database
      | `Inspect_findings -> inspect_findings database
      | `Inspect_evidence -> inspect_evidence database
      | `Inspect_reviews -> inspect_reviews database
      | `Inspect_reports -> inspect_reports database
      | `Inspect_block_reviews -> inspect_block_reviews database
      | `Inspect_finalization -> inspect_finalization database
      | `Inspect_recon -> inspect_recon database
      | `Inspect_extensions -> inspect_extensions database
      | `Inspect_promotions -> inspect_promotions database
      | `Set_legacy_deadline step ->
        let statement =
          Sqlite3.prepare
            database
            {|
UPDATE step_executions
SET lease_expires_unix_seconds = 0
WHERE state = 'claimed' AND step_key = ?1
|}
        in
        Fun.protect
          ~finally:(fun () ->
            ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
          (fun () ->
            check database (Sqlite3.bind_text statement 1 step);
            check database (Sqlite3.step statement)))
;;
