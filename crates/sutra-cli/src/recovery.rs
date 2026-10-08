use std::process::Command;
use sutra_core::models::Thread;

pub fn execute_recovery(thread: &Thread) -> Result<(), String> {
    println!("🪡 Sutra Resuming: \"{}\"", thread.title);

    let anchor = thread.anchor.as_ref();

    // 1. Resume URL
    if let Some(url) = anchor.and_then(|a| a.url.as_ref()) {
        println!("   Opening URL: {}", url);
        // Prioritize bundle_id (essential for Chrome PWAs like Peepal)
        if let Some(bundle_id) = anchor.and_then(|a| a.bundle_id.as_ref()) {
            let status = Command::new("open")
                .arg("-b")
                .arg(bundle_id)
                .arg(url)
                .status();
            if status.is_ok() && status.unwrap().success() {
                let name = anchor.and_then(|a| a.app_name.as_ref()).map(|s| s.as_str()).unwrap_or(bundle_id);
                send_notification(&thread.title, &format!("Opened in {}", name));
                return Ok(());
            }
        }
        if let Some(app) = anchor.and_then(|a| a.app_name.as_ref()) {
            let status = Command::new("open")
                .arg("-a")
                .arg(app)
                .arg(url)
                .status();
            if status.is_ok() && status.unwrap().success() {
                send_notification(&thread.title, &format!("Opened in {}", app));
                return Ok(());
            }
        }
        let st = Command::new("open")
            .arg(url)
            .status()
            .map_err(|e| e.to_string())?;
        if st.success() {
            send_notification(&thread.title, "Opened URL in default browser");
            return Ok(());
        }
    }

    // 2. Resume File Path + Line Number
    if let Some(file_path) = anchor.and_then(|a| a.file_path.as_ref()) {
        println!("   Opening File: {}", file_path);

        // Preview PDF deep page jump
        if file_path.to_lowercase().ends_with(".pdf") {
            if let Some(page) = anchor.and_then(|a| a.line_number) {
                let script = format!(
                    r#"
                    set targetFile to "{}"
                    set targetPage to "{}"

                    tell application "Preview"
                        activate
                        open POSIX file targetFile
                    end tell

                    repeat 30 times
                        delay 0.15
                        tell application "System Events"
                            if exists (process "Preview") then
                                tell process "Preview"
                                    if not frontmost then
                                        set frontmost to true
                                    end if
                                    try
                                        if enabled of (menu item "Go to Page…" of menu "Go" of menu bar 1) then
                                            click menu item "Go to Page…" of menu "Go" of menu bar 1
                                            delay 0.15
                                            keystroke targetPage
                                            key code 36
                                            return "SUCCESS"
                                        end if
                                    end try
                                end tell
                            end if
                        end tell
                    end repeat
                    return "TIMEOUT"
                    "#,
                    file_path, page
                );
                if let Ok(st) = Command::new("osascript").arg("-e").arg(&script).status() {
                    if st.success() {
                        send_notification(&thread.title, &format!("Opened {} @ page {}", file_path, page));
                        return Ok(());
                    }
                }
            }
        }

        if let Some(line) = anchor.and_then(|a| a.line_number) {
            let target = format!("{}:{}", file_path, line);
            if let Ok(st) = Command::new("code").arg("-g").arg(&target).status() {
                if st.success() {
                    send_notification(&thread.title, &format!("Opened {} @ line {}", file_path, line));
                    return Ok(());
                }
            }
        }

        if let Some(app) = anchor.and_then(|a| a.app_name.as_ref()) {
            let st = Command::new("open")
                .arg("-a")
                .arg(app)
                .arg(file_path)
                .status();
            if st.is_ok() && st.unwrap().success() {
                send_notification(&thread.title, &format!("Opened in {}", app));
                return Ok(());
            }
        }

        let st = Command::new("open")
            .arg(file_path)
            .status()
            .map_err(|e| e.to_string())?;
        if st.success() {
            send_notification(&thread.title, &format!("Opened {}", file_path));
            return Ok(());
        }
    }

    // 3. Fallback: Relaunch Application by Name or Bundle ID
    if let Some(app) = anchor.and_then(|a| a.app_name.as_ref()) {
        println!("   Launching Application: {}", app);
        let st = Command::new("open")
            .arg("-a")
            .arg(app)
            .status()
            .map_err(|e| e.to_string())?;
        if st.success() {
            send_notification(&thread.title, &format!("Switched to {}", app));
            return Ok(());
        }
    }

    // 4. Pure Text / Note Thread with No Window Anchor
    let subtitle = thread.notes.as_deref().unwrap_or("Working memory restored");
    send_notification(&thread.title, subtitle);
    println!("   Active cue restored: {}", thread.title);
    Ok(())
}

fn send_notification(title: &str, subtitle: &str) {
    let script = format!(
        r#"display notification "{}" with title "🪡 Sutra Thread" subtitle "{}""#,
        subtitle.replace('"', "\\\""),
        title.replace('"', "\\\"")
    );
    let _ = Command::new("osascript").arg("-e").arg(script).status();
}
