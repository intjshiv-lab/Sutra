use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use sutra_core::models::{Anchor, CueType, Thread, ThreadStatus};
use sutra_core::Database;

pub struct SutraDbHandle {
    db: Database,
}

/// Helper to parse C strings safely
unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        None
    } else {
        CStr::from_ptr(ptr).to_str().ok()
    }
}

/// Helper to allocate a C-string from Rust String
fn str_to_c_char(s: String) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Opens or creates the SQLite database at the specified path.
/// Returns null on failure.
#[no_mangle]
pub unsafe extern "C" fn sutra_db_open(path: *const c_char) -> *mut SutraDbHandle {
    let path_str = match cstr_to_str(path) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };

    match Database::open(Path::new(path_str)) {
        Ok(db) => Box::into_raw(Box::new(SutraDbHandle { db })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Closes and frees a SutraDbHandle.
#[no_mangle]
pub unsafe extern "C" fn sutra_db_close(handle: *mut SutraDbHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Captures a new thread and persists it into the SQLite database.
/// Returns thread JSON on success (must be freed via sutra_free_string), or null on failure.
#[no_mangle]
pub unsafe extern "C" fn sutra_capture(
    handle: *mut SutraDbHandle,
    title: *const c_char,
    notes: *const c_char,
    cue_type: *const c_char,
    app_name: *const c_char,
    url: *const c_char,
    file_path: *const c_char,
    line_number: i32,
    due_at: i64,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let db = &(*handle).db;

    let title_str = match cstr_to_str(title) {
        Some(s) if !s.trim().is_empty() => s,
        _ => return std::ptr::null_mut(),
    };

    let notes_str = cstr_to_str(notes).map(|s| s.to_string());
    let cue_type_enum = match cstr_to_str(cue_type) {
        Some("checklist") => CueType::Checklist,
        Some("link") => CueType::Link,
        Some("file") => CueType::File,
        Some("voice") => CueType::Voice,
        _ => CueType::Note,
    };

    let app_opt = cstr_to_str(app_name).map(|s| s.to_string());
    let url_opt = cstr_to_str(url).map(|s| s.to_string());
    let file_opt = cstr_to_str(file_path).map(|s| s.to_string());

    let anchor = if app_opt.is_some() || url_opt.is_some() || file_opt.is_some() {
        Some(Anchor {
            app_name: app_opt,
            bundle_id: None,
            url: url_opt,
            file_path: file_opt,
            line_number: if line_number > 0 { Some(line_number as u32) } else { None },
            window_title: None,
            timestamp_seconds: None,
            slide_index: None,
            selected_text: None,
        })
    } else {
        None
    };

    let now = chrono::Utc::now().timestamp_millis();
    let thread = Thread {
        id: uuid::Uuid::new_v4().to_string(),
        cue_type: cue_type_enum,
        title: title_str.to_string(),
        notes: notes_str,
        status: ThreadStatus::Waiting,
        created_at: now,
        updated_at: now,
        due_at: if due_at > 0 { Some(due_at) } else { None },
        snoozed_until: None,
        anchor,
        checklist: Vec::new(),
        attachments: Vec::new(),
        device_origin: "desktop".to_string(),
        tags: Vec::new(),
    };

    match db.create_thread(&thread) {
        Ok(_) => match serde_json::to_string(&thread) {
            Ok(json) => str_to_c_char(json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Lists threads with optional status filter ("waiting", "later", "done", or null for all).
/// Returns a JSON array string (must be freed via sutra_free_string).
#[no_mangle]
pub unsafe extern "C" fn sutra_list(
    handle: *mut SutraDbHandle,
    status: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let db = &(*handle).db;

    let filter = match cstr_to_str(status) {
        Some("waiting") => Some(ThreadStatus::Waiting),
        Some("later") => Some(ThreadStatus::Later),
        Some("done") => Some(ThreadStatus::Done),
        _ => None,
    };

    match db.list_threads(filter) {
        Ok(threads) => match serde_json::to_string(&threads) {
            Ok(json) => str_to_c_char(json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Searches threads using the embedded SQLite FTS5 index.
/// Returns a JSON array string (must be freed via sutra_free_string).
#[no_mangle]
pub unsafe extern "C" fn sutra_search(
    handle: *mut SutraDbHandle,
    query: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let db = &(*handle).db;

    let query_str = match cstr_to_str(query) {
        Some(q) => q,
        None => return std::ptr::null_mut(),
    };

    match db.search_threads(query_str) {
        Ok(threads) => match serde_json::to_string(&threads) {
            Ok(json) => str_to_c_char(json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Updates the status of a thread ("waiting", "later", "done").
/// Returns 0 on success, -1 on failure.
#[no_mangle]
pub unsafe extern "C" fn sutra_update_status(
    handle: *mut SutraDbHandle,
    id: *const c_char,
    new_status: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let db = &(*handle).db;

    let id_str = match cstr_to_str(id) {
        Some(s) => s,
        None => return -1,
    };

    let status = match cstr_to_str(new_status) {
        Some("waiting") => ThreadStatus::Waiting,
        Some("later") => ThreadStatus::Later,
        Some("done") => ThreadStatus::Done,
        _ => return -1,
    };

    match db.update_status(id_str, status) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Snoozes a thread for the given number of hours.
/// Returns 0 on success, -1 on failure.
#[no_mangle]
pub unsafe extern "C" fn sutra_snooze(
    handle: *mut SutraDbHandle,
    id: *const c_char,
    hours: i64,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let db = &(*handle).db;

    let id_str = match cstr_to_str(id) {
        Some(s) => s,
        None => return -1,
    };

    let until = chrono::Utc::now().timestamp_millis() + (hours * 3600 * 1000);
    match db.snooze_thread(id_str, until) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Frees a string returned by any sutra_* function.
#[no_mangle]
pub unsafe extern "C" fn sutra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
