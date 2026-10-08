use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CueType {
    Note,
    Checklist,
    Link,
    File,
    Voice,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThreadStatus {
    Waiting,
    Later,
    Done,
}

impl std::fmt::Display for ThreadStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ThreadStatus::Waiting => write!(f, "waiting"),
            ThreadStatus::Later => write!(f, "later"),
            ThreadStatus::Done => write!(f, "done"),
        }
    }
}

impl std::str::FromStr for ThreadStatus {
    type Err = String;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "waiting" => Ok(ThreadStatus::Waiting),
            "later" => Ok(ThreadStatus::Later),
            "done" => Ok(ThreadStatus::Done),
            _ => Err(format!("Unknown thread status: {}", s)),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Anchor {
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub url: Option<String>,
    pub file_path: Option<String>,
    pub line_number: Option<u32>,
    pub window_title: Option<String>,
    pub timestamp_seconds: Option<f64>,
    pub slide_index: Option<u32>,
    pub selected_text: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecklistItem {
    pub id: String,
    pub text: String,
    pub done: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attachment {
    pub id: String,
    pub att_type: String,
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Thread {
    pub id: String,
    pub cue_type: CueType,
    pub title: String,
    pub notes: Option<String>,
    pub status: ThreadStatus,
    pub created_at: i64,
    pub updated_at: i64,
    pub due_at: Option<i64>,
    pub snoozed_until: Option<i64>,
    pub anchor: Option<Anchor>,
    pub checklist: Vec<ChecklistItem>,
    pub attachments: Vec<Attachment>,
    pub device_origin: String,
    pub tags: Vec<String>,
}
