use sutra_core::models::Thread;

/// LWW-Element-Set CRDT merge.
/// For each incoming thread: if not present locally → insert.
/// If present: apply only if remote `updated_at` is strictly greater (Last-Write-Wins).
/// Deletion is represented as status = "done" with a terminal updated_at — no tombstones needed.
pub fn merge(local: &mut Vec<Thread>, incoming: &[Thread]) {
    for remote in incoming {
        match local.iter_mut().find(|t| t.id == remote.id) {
            Some(existing) => {
                if remote.updated_at > existing.updated_at {
                    *existing = remote.clone();
                }
            }
            None => local.push(remote.clone()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sutra_core::models::{CueType, ThreadStatus};

    fn make_thread(id: &str, title: &str, updated_at: i64) -> Thread {
        Thread {
            id: id.to_string(),
            cue_type: CueType::Note,
            title: title.to_string(),
            notes: None,
            status: ThreadStatus::Waiting,
            created_at: 0,
            updated_at,
            due_at: None,
            snoozed_until: None,
            anchor: None,
            checklist: vec![],
            attachments: vec![],
            device_origin: "test".to_string(),
            tags: vec![],
        }
    }

    #[test]
    fn merge_inserts_new_remote() {
        let mut local = vec![make_thread("a", "Local A", 100)];
        let incoming  = vec![make_thread("b", "Remote B", 200)];
        merge(&mut local, &incoming);
        assert_eq!(local.len(), 2);
    }

    #[test]
    fn lww_remote_wins_when_newer() {
        let mut local = vec![make_thread("a", "Old Title", 100)];
        let incoming  = vec![make_thread("a", "New Title", 200)];
        merge(&mut local, &incoming);
        assert_eq!(local[0].title, "New Title");
    }

    #[test]
    fn lww_local_wins_when_newer() {
        let mut local = vec![make_thread("a", "Local Newer", 300)];
        let incoming  = vec![make_thread("a", "Remote Older", 100)];
        merge(&mut local, &incoming);
        assert_eq!(local[0].title, "Local Newer");
    }
}
