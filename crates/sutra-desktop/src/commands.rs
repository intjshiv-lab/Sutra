use sutra_core::models::SutraThread;
use sutra_core::db::Database;
use std::sync::Mutex;
use tauri::State;

pub struct AppState {
    pub db: Mutex<Database>,
}

#[tauri::command]
pub fn list_threads(status: Option<String>, state: State<'_, AppState>) -> Result<Vec<SutraThread>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let stat = status.unwrap_or_else(|| "waiting".to_string());
    db.list_threads(&stat).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn capture_thread(
    title: String,
    notes: Option<String>,
    cue_type: Option<String>,
    due_at: Option<i64>,
    state: State<'_, AppState>,
) -> Result<SutraThread, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.create_thread(&title, notes.as_deref(), cue_type.as_deref(), due_at)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn complete_thread(thread_id: String, state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.set_thread_status(&thread_id, "done").map_err(|e| e.to_string())
}

#[tauri::command]
pub fn snooze_thread(thread_id: String, hours: i64, state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.snooze_thread(&thread_id, hours).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn undo_thread(thread_id: String, state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.set_thread_status(&thread_id, "waiting").map_err(|e| e.to_string())
}

#[tauri::command]
pub fn update_notes(thread_id: String, notes: String, state: State<'_, AppState>) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.update_notes(&thread_id, &notes).map_err(|e| e.to_string())
}
