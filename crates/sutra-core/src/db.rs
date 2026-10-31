use crate::error::{Result, SutraError};
use crate::models::{Anchor, Attachment, ChecklistItem, CueType, Thread, ThreadStatus};
use crate::state::StateMachine;
use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;
use std::sync::Mutex;

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    /// Opens or creates an embedded SQLite database with WAL mode enabled.
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.init_schema()?;
        Ok(db)
    }

    /// Opens an in-memory SQLite database for testing and ephemeral workloads.
    pub fn in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let db = Self {
            conn: Mutex::new(conn),
        };
        db.init_schema()?;
        Ok(db)
    }

    fn init_schema(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        // 1. Configure high-performance WAL mode and memory settings
        conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA temp_store = MEMORY;
            "#,
        )?;

        // 2. Primary threads table
        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS threads (
                id TEXT PRIMARY KEY,
                cue_type TEXT NOT NULL,
                title TEXT NOT NULL,
                notes TEXT,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                due_at INTEGER,
                snoozed_until INTEGER,
                anchor_json TEXT,
                checklist_json TEXT,
                attachments_json TEXT,
                device_origin TEXT NOT NULL,
                tags_json TEXT
            );
            "#,
            [],
        )?;

        // Indexes on frequently queried fields
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_threads_status ON threads(status);",
            [],
        )?;
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_threads_updated_at ON threads(updated_at DESC);",
            [],
        )?;

        // 3. FTS5 Virtual Table for full-text search (< 10ms lookup)
        conn.execute(
            r#"
            CREATE VIRTUAL TABLE IF NOT EXISTS threads_fts USING fts5(
                id UNINDEXED,
                title,
                notes,
                tags
            );
            "#,
            [],
        )?;

        // Triggers to keep FTS table synchronized with threads table
        conn.execute_batch(
            r#"
            CREATE TRIGGER IF NOT EXISTS threads_ai AFTER INSERT ON threads BEGIN
                INSERT INTO threads_fts(id, title, notes, tags)
                VALUES (new.id, new.title, coalesce(new.notes, ''), coalesce(new.tags_json, ''));
            END;

            CREATE TRIGGER IF NOT EXISTS threads_ad AFTER DELETE ON threads BEGIN
                DELETE FROM threads_fts WHERE id = old.id;
            END;

            CREATE TRIGGER IF NOT EXISTS threads_au AFTER UPDATE ON threads BEGIN
                DELETE FROM threads_fts WHERE id = old.id;
                INSERT INTO threads_fts(id, title, notes, tags)
                VALUES (new.id, new.title, coalesce(new.notes, ''), coalesce(new.tags_json, ''));
            END;
            "#,
        )?;

        Ok(())
    }

    /// Insert a new thread into the database.
    pub fn create_thread(&self, thread: &Thread) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        let cue_type_str = serde_json::to_string(&thread.cue_type)?;
        let cue_type_str = cue_type_str.trim_matches('"');
        let status_str = thread.status.to_string();
        let anchor_json = serde_json::to_string(&thread.anchor)?;
        let checklist_json = serde_json::to_string(&thread.checklist)?;
        let attachments_json = serde_json::to_string(&thread.attachments)?;
        let tags_json = serde_json::to_string(&thread.tags)?;

        conn.execute(
            r#"
            INSERT INTO threads (
                id, cue_type, title, notes, status, created_at, updated_at,
                due_at, snoozed_until, anchor_json, checklist_json, attachments_json,
                device_origin, tags_json
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14);
            "#,
            params![
                thread.id,
                cue_type_str,
                thread.title,
                thread.notes,
                status_str,
                thread.created_at,
                thread.updated_at,
                thread.due_at,
                thread.snoozed_until,
                anchor_json,
                checklist_json,
                attachments_json,
                thread.device_origin,
                tags_json,
            ],
        )?;

        Ok(())
    }

    /// Retrieve a thread by its ID.
    pub fn get_thread(&self, id: &str) -> Result<Thread> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            r#"
            SELECT id, cue_type, title, notes, status, created_at, updated_at,
                   due_at, snoozed_until, anchor_json, checklist_json, attachments_json,
                   device_origin, tags_json
            FROM threads WHERE id = ?1;
            "#,
        )?;

        let thread = stmt
            .query_row(params![id], |row| {
                let cue_type_str: String = row.get(1)?;
                let status_str: String = row.get(4)?;
                let anchor_str: Option<String> = row.get(9)?;
                let checklist_str: Option<String> = row.get(10)?;
                let attachments_str: Option<String> = row.get(11)?;
                let tags_str: Option<String> = row.get(13)?;

                Ok((
                    row.get::<_, String>(0)?,
                    cue_type_str,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    status_str,
                    row.get::<_, i64>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    anchor_str,
                    checklist_str,
                    attachments_str,
                    row.get::<_, String>(12)?,
                    tags_str,
                ))
            })
            .optional()?;

        let (
            id,
            cue_type_str,
            title,
            notes,
            status_str,
            created_at,
            updated_at,
            due_at,
            snoozed_until,
            anchor_str,
            checklist_str,
            attachments_str,
            device_origin,
            tags_str,
        ) = match thread {
            Some(t) => t,
            None => return Err(SutraError::NotFound(id.to_string())),
        };

        let cue_type: CueType = serde_json::from_str(&format!("\"{}\"", cue_type_str))
            .map_err(|e| SutraError::Validation(e.to_string()))?;
        let status: ThreadStatus = status_str
            .parse()
            .map_err(SutraError::Validation)?;
        let anchor: Option<Anchor> = anchor_str
            .as_deref()
            .map(serde_json::from_str)
            .transpose()?;
        let checklist: Vec<ChecklistItem> = checklist_str
            .as_deref()
            .map(serde_json::from_str)
            .transpose()?
            .unwrap_or_default();
        let attachments: Vec<Attachment> = attachments_str
            .as_deref()
            .map(serde_json::from_str)
            .transpose()?
            .unwrap_or_default();
        let tags: Vec<String> = tags_str
            .as_deref()
            .map(serde_json::from_str)
            .transpose()?
            .unwrap_or_default();

        Ok(Thread {
            id,
            cue_type,
            title,
            notes,
            status,
            created_at,
            updated_at,
            due_at,
            snoozed_until,
            anchor,
            checklist,
            attachments,
            device_origin,
            tags,
        })
    }

    /// Transition a thread's status through the Tri-State machine.
    pub fn update_status(&self, id: &str, target_status: ThreadStatus) -> Result<()> {
        let current = self.get_thread(id)?;
        let next_status = StateMachine::transition(current.status, target_status)?;

        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp_millis();

        conn.execute(
            "UPDATE threads SET status = ?1, updated_at = ?2 WHERE id = ?3;",
            params![next_status.to_string(), now, id],
        )?;

        Ok(())
    }

    /// Snooze a thread to Later until a specific epoch timestamp.
    pub fn snooze_thread(&self, id: &str, until: i64) -> Result<()> {
        let current = self.get_thread(id)?;
        let next_status = StateMachine::transition(current.status, ThreadStatus::Later)?;

        let conn = self.conn.lock().unwrap();
        let now = chrono::Utc::now().timestamp_millis();

        conn.execute(
            "UPDATE threads SET status = ?1, snoozed_until = ?2, updated_at = ?3 WHERE id = ?4;",
            params![next_status.to_string(), until, now, id],
        )?;

        Ok(())
    }

    /// List threads, optionally filtered by status.
    pub fn list_threads(&self, filter: Option<ThreadStatus>) -> Result<Vec<Thread>> {
        let conn = self.conn.lock().unwrap();
        let query = match filter {
            Some(_) => "SELECT id FROM threads WHERE status = ?1 ORDER BY updated_at DESC;",
            None => "SELECT id FROM threads ORDER BY updated_at DESC;",
        };

        let mut stmt = conn.prepare(query)?;
        let ids: Vec<String> = match filter {
            Some(st) => {
                let st_str = st.to_string();
                let rows = stmt.query_map(params![st_str], |row| row.get(0))?;
                rows.collect::<std::result::Result<Vec<String>, _>>()?
            }
            None => {
                let rows = stmt.query_map([], |row| row.get(0))?;
                rows.collect::<std::result::Result<Vec<String>, _>>()?
            }
        };

        drop(stmt);
        drop(conn);

        let mut results = Vec::with_capacity(ids.len());
        for id in ids {
            results.push(self.get_thread(&id)?);
        }
        Ok(results)
    }

    /// Full-text search across titles, notes, and tags using FTS5.
    pub fn search_threads(&self, query: &str) -> Result<Vec<Thread>> {
        if query.trim().is_empty() {
            return self.list_threads(None);
        }

        let conn = self.conn.lock().unwrap();
        let sanitized = format!("{}*", query.replace('"', "\"\""));
        let mut stmt = conn.prepare(
            r#"
            SELECT t.id FROM threads t
            JOIN threads_fts f ON t.id = f.id
            WHERE threads_fts MATCH ?1
            ORDER BY rank;
            "#,
        )?;

        let rows = stmt.query_map(params![sanitized], |row| row.get(0))?;
        let ids: Vec<String> = rows.collect::<std::result::Result<Vec<String>, _>>()?;

        drop(stmt);
        drop(conn);

        let mut results = Vec::with_capacity(ids.len());
        for id in ids {
            results.push(self.get_thread(&id)?);
        }
        Ok(results)
    }

    /// Delete a thread by ID.
    pub fn delete_thread(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute("DELETE FROM threads WHERE id = ?1;", params![id])?;
        if affected == 0 {
            return Err(SutraError::NotFound(id.to_string()));
        }
        Ok(())
    }

    /// Return all `waiting` threads not updated in the last `days` days.
    /// Used by the anti-hoarding cognitive debt engine to surface stale threads.
    pub fn list_stale(&self, days: u32) -> Result<Vec<Thread>> {
        let cutoff_ms = chrono::Utc::now().timestamp_millis()
            - (days as i64 * 24 * 60 * 60 * 1_000);
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id FROM threads WHERE status = 'waiting' AND updated_at < ?1 ORDER BY updated_at ASC;"
        )?;
        let ids: Vec<String> = stmt
            .query_map(params![cutoff_ms], |row| row.get(0))?
            .collect::<std::result::Result<Vec<String>, _>>()?;
        drop(stmt);
        drop(conn);
        let mut results = Vec::with_capacity(ids.len());
        for id in ids {
            results.push(self.get_thread(&id)?);
        }
        Ok(results)
    }

    /// Decay stale `waiting` threads older than `days` days into `later` status.
    /// Returns the number of threads decayed. Called nightly by the launchctl hook.
    pub fn decay_stale_to_later(&self, days: u32) -> Result<usize> {
        let cutoff_ms = chrono::Utc::now().timestamp_millis()
            - (days as i64 * 24 * 60 * 60 * 1_000);
        let conn = self.conn.lock().unwrap();
        let now_ms = chrono::Utc::now().timestamp_millis();
        let affected = conn.execute(
            "UPDATE threads SET status = 'later', updated_at = ?1 WHERE status = 'waiting' AND updated_at < ?2;",
            params![now_ms, cutoff_ms],
        )?;
        Ok(affected)
    }

    /// Count threads by status string.
    pub fn count_by_status(&self, status: &str) -> Result<u64> {
        let conn = self.conn.lock().unwrap();
        let n: u64 = conn.query_row(
            "SELECT COUNT(*) FROM threads WHERE status = ?1;",
            params![status],
            |row| row.get(0),
        )?;
        Ok(n)
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    fn sample_thread(id: &str, title: &str) -> Thread {
        Thread {
            id: id.to_string(),
            cue_type: CueType::Checklist,
            title: title.to_string(),
            notes: Some("Fix zero denominator issue".to_string()),
            status: ThreadStatus::Waiting,
            created_at: 1000,
            updated_at: 1000,
            due_at: None,
            snoozed_until: None,
            anchor: Some(Anchor {
                app_name: Some("VS Code".to_string()),
                bundle_id: Some("com.microsoft.VSCode".to_string()),
                url: None,
                file_path: Some("/src/engine.rs".to_string()),
                line_number: Some(142),
                window_title: Some("engine.rs".to_string()),
                timestamp_seconds: None,
                slide_index: None,
                selected_text: None,
            }),
            checklist: vec![ChecklistItem {
                id: "c1".to_string(),
                text: "Add guard check".to_string(),
                done: false,
            }],
            attachments: vec![],
            device_origin: "macbook-pro".to_string(),
            tags: vec!["bugfix".to_string(), "engine".to_string()],
        }
    }

    #[test]
    fn test_crud_and_status_transitions() {
        let db = Database::in_memory().unwrap();
        let thread = sample_thread("t1", "Fix underflow error");

        db.create_thread(&thread).unwrap();
        let retrieved = db.get_thread("t1").unwrap();
        assert_eq!(retrieved.title, "Fix underflow error");
        assert_eq!(retrieved.status, ThreadStatus::Waiting);

        // Move to Later (snooze)
        db.snooze_thread("t1", 2000).unwrap();
        assert_eq!(db.get_thread("t1").unwrap().status, ThreadStatus::Later);

        // Move to Done
        db.update_status("t1", ThreadStatus::Done).unwrap();
        assert_eq!(db.get_thread("t1").unwrap().status, ThreadStatus::Done);

        // 1-Click Undo back to Waiting
        db.update_status("t1", ThreadStatus::Waiting).unwrap();
        assert_eq!(db.get_thread("t1").unwrap().status, ThreadStatus::Waiting);
    }

    #[test]
    fn test_fts5_full_text_search() {
        let db = Database::in_memory().unwrap();
        let t1 = sample_thread("t1", "Compile Rust bindings");
        let mut t2 = sample_thread("t2", "Review economic surplus notes");
        t2.notes = Some("Lecture 5 microeconomics elasticity".to_string());

        db.create_thread(&t1).unwrap();
        db.create_thread(&t2).unwrap();

        let search1 = db.search_threads("Rust").unwrap();
        assert_eq!(search1.len(), 1);
        assert_eq!(search1[0].id, "t1");

        let search2 = db.search_threads("elasticity").unwrap();
        assert_eq!(search2.len(), 1);
        assert_eq!(search2[0].id, "t2");
    }
}
