-- AutomationState.db — full schema (Phase 7 Wave 0)
--
-- Byte-identical in table and column names to what scripts/Initialize-AutomationDb.ps1
-- emits. Pester suites feed this file to sqlite3.exe to spin up a throwaway DB without
-- invoking the init script.
--
-- 11 tables: Role, Region, GroupRoleMap, RefUser, UserRole, RolePublication, Snapshot,
--            SyncRun, PipelineConfig, ContentItem, ContentCache
-- 3 indexes: idx_grm_active, idx_userrole_role, idx_userrole_user
--
-- Naming resolutions (07-RESEARCH.md § Discretion Resolutions, D-01):
--   PipelineConfig  (not Config)
--   ContentCache    (the superseded 2026-08-01 design used a different table name)
--   one wide SyncRun table with a Type column and nullable content-only columns

CREATE TABLE IF NOT EXISTS Role (
  RoleID      INTEGER PRIMARY KEY AUTOINCREMENT,
  Role        TEXT NOT NULL UNIQUE COLLATE NOCASE,
  Description TEXT,
  Active      INTEGER NOT NULL DEFAULT 1,
  Created_on  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS Region (
  RegionID     INTEGER PRIMARY KEY AUTOINCREMENT,
  GPC_Sub_Name TEXT NOT NULL UNIQUE COLLATE NOCASE,   -- must equal the endpoint client-setting value
  Description  TEXT,
  Active       INTEGER NOT NULL DEFAULT 1,
  Created_on   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS GroupRoleMap (
  GRMID      INTEGER PRIMARY KEY AUTOINCREMENT,
  Pattern    TEXT NOT NULL,
  Match_On   TEXT NOT NULL DEFAULT 'cn',              -- cn | display | dn
  Role       TEXT NOT NULL COLLATE NOCASE,
  Priority   INTEGER NOT NULL DEFAULT 100,
  Active     INTEGER NOT NULL DEFAULT 1,
  Notes      TEXT,
  Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Updated_on TEXT
);

CREATE TABLE IF NOT EXISTS RefUser (
  RefUserID    INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID       TEXT NOT NULL UNIQUE COLLATE NOCASE,   -- normalised lowercased match key
  SamAccount   TEXT,
  Upn          TEXT,
  Display_Name TEXT,
  Domain       TEXT,
  Username_Src TEXT NOT NULL,                         -- sam | upn | username
  RegionID     INTEGER REFERENCES Region(RegionID),   -- reporting only, operator-set later
  First_Seen   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_RunID   TEXT
);

CREATE TABLE IF NOT EXISTS UserRole (
  URID          INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID        TEXT NOT NULL COLLATE NOCASE,
  Role          TEXT NOT NULL COLLATE NOCASE,
  Source_Type   TEXT NOT NULL,
  Source_Value  TEXT NOT NULL,
  Source_System TEXT,
  Matched_Rule  INTEGER REFERENCES GroupRoleMap(GRMID),
  Active        INTEGER NOT NULL DEFAULT 1,           -- 0 = not in latest export (age-out; row kept)
  First_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen     TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_RunID    TEXT,
  UNIQUE (UserID, Role, Source_Value)
);

CREATE TABLE IF NOT EXISTS RolePublication (
  RPID       INTEGER PRIMARY KEY AUTOINCREMENT,
  Role       TEXT NOT NULL COLLATE NOCASE,
  RegionID   INTEGER REFERENCES Region(RegionID),     -- NULL = all regions
  Active     INTEGER NOT NULL DEFAULT 1,
  Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  UNIQUE (Role, RegionID)
);

CREATE TABLE IF NOT EXISTS Snapshot (
  SnapshotID INTEGER PRIMARY KEY AUTOINCREMENT,
  RunID      TEXT NOT NULL,
  Built_on   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  File_Name  TEXT NOT NULL,
  SHA1       TEXT NOT NULL,
  Size_Bytes INTEGER,
  Role_Count INTEGER,
  User_Count INTEGER,
  Region     TEXT,
  Status     TEXT NOT NULL DEFAULT 'built'            -- built | published | failed
);

CREATE TABLE IF NOT EXISTS SyncRun (
  RunID           TEXT PRIMARY KEY,
  Type            TEXT NOT NULL,                      -- Ingest | Publish | ContentSync | RepoStage
  Started_on      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Ended_on        TEXT,
  Status          TEXT NOT NULL DEFAULT 'running',    -- running | success | partial | failed
  Rows_In         INTEGER,
  Users_Seen      INTEGER,
  Roles_Seen      INTEGER,
  Entitlements    INTEGER,
  Items_Discovered INTEGER,                           -- content-only, nullable
  Items_Copied    INTEGER,                            -- content-only, nullable
  Items_Failed    INTEGER,                            -- content-only, nullable
  Summary         TEXT,
  Error_Count     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS PipelineConfig (
  Key         TEXT PRIMARY KEY,
  Value       TEXT,
  Description TEXT
);

CREATE TABLE IF NOT EXISTS ContentItem (
  fixlet_id    TEXT NOT NULL,
  source_site  TEXT NOT NULL,
  fixlet_name  TEXT NOT NULL,
  stage        TEXT NOT NULL DEFAULT 'discovered',    -- discovered|staged|categorized|ready|live|rejected
  category     TEXT,
  roles        TEXT,
  is_task      INTEGER NOT NULL DEFAULT 0,
  copied_at    TEXT,
  dispatched_at TEXT,
  PRIMARY KEY (fixlet_id, source_site)
);

CREATE TABLE IF NOT EXISTS ContentCache (
  sha1         TEXT PRIMARY KEY,
  filename     TEXT NOT NULL,
  original_url TEXT,
  staged_at    TEXT,
  size_bytes   INTEGER,
  verified     INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_grm_active     ON GroupRoleMap (Active, Role);
CREATE INDEX IF NOT EXISTS idx_userrole_role  ON UserRole (Role, Active);
CREATE INDEX IF NOT EXISTS idx_userrole_user  ON UserRole (UserID, Active);
