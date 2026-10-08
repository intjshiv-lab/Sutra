use std::process::Command;
use sutra_core::models::Anchor;

pub fn sniff_frontmost_context() -> Anchor {
    let mut anchor = Anchor::default();

    // 1. Get frontmost app name and window title
    let app_script = r#"
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            set pName to name of frontApp
            set winTitle to ""
            try
                set winTitle to name of front window of frontApp
            end try
            return pName & "|||" & winTitle
        end tell
    "#;

    let mut window_title_hint = String::new();

    if let Ok(output) = Command::new("osascript").arg("-e").arg(app_script).output() {
        if output.status.success() {
            let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let parts: Vec<&str> = res.split("|||").collect();
            if !parts.is_empty() {
                let app_name = parts[0].trim().to_string();
                if !app_name.is_empty() {
                    anchor.app_name = Some(app_name);
                }
            }
            if parts.len() > 1 {
                let title = parts[1].trim().to_string();
                if !title.is_empty() {
                    window_title_hint = title.clone();
                    anchor.window_title = Some(title);
                }
            }
        }
    }

    // Check if this is a Chrome PWA (app_mode_loader)
    if let Some(name) = &anchor.app_name {
        if name == "app_mode_loader" {
            resolve_chrome_pwa(&mut anchor, &window_title_hint);
            return anchor;
        }
        anchor.bundle_id = get_bundle_id(name);
    }

    let app_name = match &anchor.app_name {
        Some(name) => name.as_str(),
        None => return anchor,
    };

    // 2. Query application-specific state
    match app_name {
        "Safari" => {
            let script = r#"
                tell application "Safari"
                    if (count of documents) > 0 then
                        return (URL of front document) & "|||" & (name of front document)
                    end if
                end tell
            "#;
            if let Ok(output) = Command::new("osascript").arg("-e").arg(script).output() {
                let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let parts: Vec<&str> = res.split("|||").collect();
                if parts.len() == 2 {
                    anchor.url = Some(parts[0].trim().to_string());
                    anchor.window_title = Some(parts[1].trim().to_string());
                }
            }
        }
        "Google Chrome" | "Brave Browser" | "Arc" | "Chromium" | "Microsoft Edge" => {
            let script = format!(
                r#"
                tell application "{}"
                    -- 1. Try front window first
                    try
                        if (count of windows) > 0 then
                            set u to URL of active tab of front window
                            set t to title of active tab of front window
                            if u is not "" and u is not "about:blank" and u does not contain "mermaid-cli" then
                                return u & "|||" & t
                            end if
                        end if
                    end try

                    -- 2. Fallback: find topmost interactive user window
                    repeat with w in windows
                        try
                            set u to URL of active tab of w
                            set t to title of active tab of w
                            if u is not "" and u is not "about:blank" and u does not contain "mermaid-cli" then
                                return u & "|||" & t
                            end if
                        end try
                    end repeat

                    -- 3. Ultimate fallback: whatever front window has
                    try
                        if (count of windows) > 0 then
                            return (URL of active tab of front window) & "|||" & (title of active tab of front window)
                        end if
                    end try
                    return ""
                end tell
            "#,
                app_name
            );
            if let Ok(output) = Command::new("osascript").arg("-e").arg(&script).output() {
                let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let parts: Vec<&str> = res.split("|||").collect();
                if parts.len() == 2 && !parts[0].is_empty() {
                    anchor.url = Some(parts[0].trim().to_string());
                    anchor.window_title = Some(parts[1].trim().to_string());
                }
            }
        }
        "Preview" => {
            let script = r#"
                tell application "Preview"
                    if (count of documents) > 0 then
                        set docPath to path of front document
                        set docName to name of front document
                    else
                        return ""
                    end if
                end tell
                set pageInfo to ""
                tell application "System Events"
                    if exists (process "Preview") then
                        tell process "Preview"
                            try
                                set winMenuItems to name of menu items of menu "Window" of menu bar 1
                                repeat with itemStr in winMenuItems
                                    if itemStr is not missing value and itemStr contains docName and itemStr contains "Page" then
                                        set pageInfo to itemStr
                                        exit repeat
                                    end if
                                end repeat
                            end try
                        end tell
                    end if
                end tell
                return docPath & "|||" & pageInfo
            "#;
            if let Ok(output) = Command::new("osascript").arg("-e").arg(script).output() {
                let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
                let parts: Vec<&str> = res.split("|||").collect();
                if parts.len() >= 2 {
                    let path = parts[0].trim();
                    let page_info = parts[1].trim();
                    if !path.is_empty() {
                        anchor.file_path = Some(path.to_string());
                        let fallback_title = std::path::Path::new(path)
                            .file_name()
                            .and_then(|n| n.to_str())
                            .unwrap_or(path);
                        anchor.window_title = Some(if page_info.is_empty() { fallback_title.to_string() } else { page_info.to_string() });

                        // Parse "Page X" from window title (e.g. "Doc.pdf (Page 11 of 15)")
                        if let Some(pos) = page_info.to_lowercase().find("page ") {
                            let after = &page_info[pos + 5..];
                            let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
                            if let Ok(p_num) = digits.parse::<u32>() {
                                anchor.line_number = Some(p_num);
                            }
                        }
                    }
                }
            }
        }
        "Finder" => {
            let script = r#"
                tell application "Finder"
                    if (count of Finder windows) > 0 then
                        try
                            set p to POSIX path of (target of front Finder window as alias)
                            return p
                        end try
                    end if
                end tell
            "#;
            if let Ok(output) = Command::new("osascript").arg("-e").arg(script).output() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() {
                    anchor.file_path = Some(path.clone());
                    anchor.window_title = Some(path);
                }
            }
        }
        _ => {
            // Generic window title sniffing if not already obtained
            if anchor.window_title.is_none() {
                let script = format!(
                    r#"
                    tell application "System Events"
                        tell process "{}"
                            if (count of windows) > 0 then
                                return name of front window
                            end if
                        end tell
                    end tell
                "#,
                    app_name
                );
                if let Ok(output) = Command::new("osascript").arg("-e").arg(&script).output() {
                    let title = String::from_utf8_lossy(&output.stdout).trim().to_string();
                    if !title.is_empty() {
                        anchor.window_title = Some(title);
                    }
                }
            }

            if let Some(title) = &anchor.window_title {
                if title.contains('/') {
                    let tokens: Vec<&str> = title.split_whitespace().collect();
                    for token in tokens {
                        if token.starts_with('/') && std::path::Path::new(token).exists() {
                            anchor.file_path = Some(token.to_string());
                            break;
                        }
                    }
                }
            }
        }
    }

    anchor
}

fn resolve_chrome_pwa(anchor: &mut Anchor, window_title_hint: &str) {
    // 1. Ask Google Chrome for the tab whose title matches window_title_hint
    let script = format!(
        r#"
        tell application "Google Chrome"
            set searchTitle to "{}"
            repeat with w in windows
                set t to title of active tab of w
                set u to URL of active tab of w
                if searchTitle contains t or t contains searchTitle or searchTitle is "" then
                    return u & "|||" & t
                end if
            end repeat
            return ""
        end tell
        "#,
        window_title_hint.replace('"', "\\\"")
    );

    if let Ok(output) = Command::new("osascript").arg("-e").arg(&script).output() {
        let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let parts: Vec<&str> = res.split("|||").collect();
        if parts.len() == 2 && !parts[0].is_empty() {
            anchor.url = Some(parts[0].trim().to_string());
            anchor.window_title = Some(parts[1].trim().to_string());
        }
    }

    // 2. Resolve PWA name and bundle ID from ~/Applications/Chrome Apps.localized/
    if let Ok(home) = std::env::var("HOME") {
        let pwa_dirs = vec![
            format!("{}/Applications/Chrome Apps.localized", home),
            format!("{}/Applications/Chrome Apps", home),
        ];

        for dir in pwa_dirs {
            let path = std::path::Path::new(&dir);
            if let Ok(entries) = std::fs::read_dir(path) {
                for entry in entries.flatten() {
                    let entry_path = entry.path();
                    if entry_path.extension().map_or(false, |ext| ext == "app") {
                        let app_name = entry_path.file_stem().unwrap().to_string_lossy().to_string();
                        let title = anchor.window_title.as_deref().unwrap_or(window_title_hint);
                        
                        if title.to_lowercase().contains(&app_name.to_lowercase())
                            || app_name.to_lowercase().contains(&title.to_lowercase())
                            || (app_name.to_lowercase() == "peepal" && title.to_lowercase().contains("knowledge forest")) {
                            
                            anchor.app_name = Some(app_name);
                            // Read Info.plist for bundle ID
                            let plist_path = entry_path.join("Contents/Info.plist");
                            if let Ok(plist_content) = std::fs::read_to_string(&plist_path) {
                                if let Some(idx) = plist_content.find("com.google.Chrome.app.") {
                                    let sub = &plist_content[idx..];
                                    if let Some(end_idx) = sub.find('<') {
                                        anchor.bundle_id = Some(sub[..end_idx].trim().to_string());
                                    }
                                }
                            }
                            return;
                        }
                    }
                }
            }
        }
    }

    // Fallback if not matched
    anchor.app_name = Some(if window_title_hint.is_empty() { "Web App".to_string() } else { window_title_hint.to_string() });
}

fn get_bundle_id(app_name: &str) -> Option<String> {
    let script = format!(r#"id of application "{}""#, app_name);
    if let Ok(output) = Command::new("osascript").arg("-e").arg(&script).output() {
        let bid = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !bid.is_empty() && !bid.contains("error") {
            return Some(bid);
        }
    }
    None
}
