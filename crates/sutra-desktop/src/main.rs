#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;

use commands::AppState;
use std::sync::Mutex;
use sutra_core::db::Database;
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager,
};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

fn toggle_window(app: &AppHandle, label: &str) {
    if let Some(window) = app.get_webview_window(label) {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

fn main() {
    let db_path = dirs_or_home_db();
    let db = Database::open(&db_path).expect("Failed to initialize Sutra SQLite database");
    let state = AppState {
        db: Mutex::new(db),
    };

    tauri::Builder::default()
        .manage(state)
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            // Setup Tray Menu
            let quit_i = MenuItem::with_id(app, "quit", "Quit Sutra", true, None::<&str>)?;
            let sanctuary_i = MenuItem::with_id(app, "sanctuary", "Sanctuary (⌥S)", true, None::<&str>)?;
            let quickcue_i = MenuItem::with_id(app, "quickcue", "Quick Cue (⌥Space)", true, None::<&str>)?;
            let wakebar_i = MenuItem::with_id(app, "wakebar", "Floating Bar (⌥A)", true, None::<&str>)?;
            let tray_menu = Menu::with_items(app, &[&sanctuary_i, &quickcue_i, &wakebar_i, &quit_i])?;

            let _tray = TrayIconBuilder::new()
                .menu(&tray_menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "sanctuary" => toggle_window(app, "sanctuary"),
                    "quickcue" => toggle_window(app, "quickcue"),
                    "wakebar" => toggle_window(app, "wakebar"),
                    _ => {}
                })
                .build(app)?;

            // Register Global Hotkeys
            let app_handle_s = app.handle().clone();
            let app_handle_q = app.handle().clone();
            let app_handle_w = app.handle().clone();

            let shortcut_s: Shortcut = "Alt+KeyS".parse().unwrap();
            let shortcut_space: Shortcut = "Alt+Space".parse().unwrap();
            let shortcut_a: Shortcut = "Alt+KeyA".parse().unwrap();

            let _ = app.global_shortcut().on_shortcut(shortcut_s, move |_app, _shortcut, event| {
                if event.state() == ShortcutState::Pressed {
                    toggle_window(&app_handle_s, "sanctuary");
                }
            });

            let _ = app.global_shortcut().on_shortcut(shortcut_space, move |_app, _shortcut, event| {
                if event.state() == ShortcutState::Pressed {
                    toggle_window(&app_handle_q, "quickcue");
                }
            });

            let _ = app.global_shortcut().on_shortcut(shortcut_a, move |_app, _shortcut, event| {
                if event.state() == ShortcutState::Pressed {
                    toggle_window(&app_handle_w, "wakebar");
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_threads,
            commands::capture_thread,
            commands::complete_thread,
            commands::snooze_thread,
            commands::undo_thread,
            commands::update_notes
        ])
        .run(tauri::generate_context!())
        .expect("error while running Sutra desktop application");
}

fn dirs_or_home_db() -> String {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    format!("{}/.sutra/sutra.db", home)
}
