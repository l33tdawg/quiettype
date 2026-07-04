-- QuietType encrypted SQLite logical schema.
-- The database file must be encrypted at rest using SQLCipher or an
-- app-managed encrypted container with a Keychain-backed key.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  language TEXT NOT NULL,
  speech_rate_wpm INTEGER NOT NULL,
  pause_threshold_ms INTEGER NOT NULL,
  vad_sensitivity REAL NOT NULL,
  mic_noise_floor_db REAL,
  active_asr_backend TEXT NOT NULL,
  active_editor_model TEXT NOT NULL,
  strict_offline_enabled INTEGER NOT NULL DEFAULT 1,
  learning_enabled INTEGER NOT NULL DEFAULT 1,
  app_context_enabled INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS vocabulary (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  term TEXT NOT NULL,
  preferred_spelling TEXT NOT NULL,
  spoken_forms_json TEXT NOT NULL,
  category TEXT NOT NULL,
  boost REAL NOT NULL,
  source TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS vocabulary_profile_term_idx
ON vocabulary(profile_id, term);

CREATE TABLE IF NOT EXISTS asr_confusions (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  heard TEXT NOT NULL,
  corrected TEXT NOT NULL,
  context_terms_json TEXT NOT NULL,
  confidence REAL NOT NULL,
  source TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS corrections (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  raw_text TEXT NOT NULL,
  inserted_text TEXT NOT NULL,
  user_corrected_text TEXT,
  app_context_json TEXT NOT NULL,
  accepted INTEGER NOT NULL,
  timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS style_profiles (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  app_name TEXT NOT NULL,
  tone TEXT NOT NULL,
  formatting_rules_json TEXT NOT NULL,
  preserve_terms INTEGER NOT NULL DEFAULT 1,
  prefer_bullets INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS style_profiles_profile_app_idx
ON style_profiles(profile_id, app_name);

CREATE TABLE IF NOT EXISTS dictation_sessions (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  started_at TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  app_name TEXT NOT NULL,
  raw_transcript TEXT,
  final_text TEXT,
  latency_ms INTEGER,
  user_edited_after_insert INTEGER,
  retained_for_learning INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS excluded_apps (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  bundle_identifier TEXT NOT NULL,
  reason TEXT,
  created_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS excluded_apps_profile_bundle_idx
ON excluded_apps(profile_id, bundle_identifier);
