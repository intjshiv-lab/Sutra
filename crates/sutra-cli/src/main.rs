mod recovery;
mod sniff;

use clap::{Parser, Subcommand};
use recovery::execute_recovery;
use sniff::sniff_frontmost_context;
use std::path::PathBuf;
use sutra_core::models::{CueType, Thread, ThreadStatus};
use sutra_core::Database;

#[derive(Parser)]
#[command(name = "sutra")]
#[command(about = "Sutra — Sovereign Attention Thread & Context-Waking Engine", long_about = None)]
struct Cli {
    #[arg(long, global = true)]
    db: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Capture a new cognitive thread with instant frontmost context sniffing
    Capture {
        /// Title of the thread (what to do when back)
        #[arg(short, long)]
        title: Option<String>,

        /// Contextual notes or observations
        #[arg(short, long)]
        notes: Option<String>,

        /// Cue type: note, checklist, link, file, voice
        #[arg(short = 'c', long, default_value = "note")]
        cue_type: String,

        /// Override target application name
        #[arg(long)]
        app: Option<String>,

        /// Override URL anchor
        #[arg(long)]
        url: Option<String>,

        /// Override file path anchor
        #[arg(long)]
        file: Option<String>,

        /// Override line number anchor
        #[arg(long)]
        line: Option<u32>,

        /// Add tags
        #[arg(long = "tag")]
        tags: Vec<String>,

        /// Skip automatic context sniffing
        #[arg(long)]
        no_sniff: bool,

        /// Output created thread as raw JSON
        #[arg(long)]
        json: bool,
    },

    /// List cognitive threads (filtered by status)
    List {
        /// Filter by status: waiting (default), later, done, all
        #[arg(short, long, default_value = "waiting")]
        status: String,

        /// Output results as JSON (for UI / Alfred / Raycast consumption)
        #[arg(long)]
        json: bool,
    },

    /// 1-Click Resume an interrupted thread (re-launches app, tab, or file)
    Resume {
        /// Thread ID
        id: String,
    },

    /// Snooze a thread to Later
    Snooze {
        /// Thread ID
        id: String,

        /// Snooze duration in hours (default: 4)
        #[arg(long, default_value = "4")]
        hours: u32,
    },

    /// Mark a thread as Done
    Done {
        /// Thread ID
        id: String,
    },

    /// Undo mistake / restore thread back to Waiting
    Undo {
        /// Thread ID
        id: String,
    },

    /// Sub-10ms full-text search across all threads
    Search {
        /// Search query
        query: String,

        /// Output as JSON
        #[arg(long)]
        json: bool,
    },

    /// Sniff and output the active frontmost window context
    Sniff,

    /// Print database location
    DbPath,
}

fn get_default_db_path() -> PathBuf {
    if let Ok(p) = std::env::var("SUTRA_DB_PATH") {
        return PathBuf::from(p);
    }
    if let Ok(home) = std::env::var("HOME") {
        let dir = PathBuf::from(home).join(".sutra");
        if std::fs::create_dir_all(&dir).is_ok() {
            let candidate = dir.join("sutra.db");
            if std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(&candidate)
                .is_ok()
            {
                return candidate;
            }
        }
    }
    PathBuf::from("sutra.db")
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let db_path = cli.db.unwrap_or_else(get_default_db_path);

    let db = Database::open(&db_path)?;

    match cli.command {
        Commands::DbPath => {
            println!("{}", db_path.display());
        }

        Commands::Sniff => {
            let anchor = sniff_frontmost_context();
            println!("{}", serde_json::to_string_pretty(&anchor)?);
        }

        Commands::Capture {
            title,
            notes,
            cue_type,
            app,
            url,
            file,
            line,
            tags,
            no_sniff,
            json,
        } => {
            let now = chrono::Utc::now().timestamp_millis();
            let mut anchor = if no_sniff {
                Default::default()
            } else {
                sniff_frontmost_context()
            };

            if let Some(a) = app {
                anchor.app_name = Some(a);
            }
            if let Some(u) = url {
                anchor.url = Some(u);
            }
            if let Some(f) = file {
                anchor.file_path = Some(f);
            }
            if let Some(l) = line {
                anchor.line_number = Some(l);
            }

            let cue: CueType = match cue_type.to_lowercase().as_str() {
                "checklist" => CueType::Checklist,
                "link" => CueType::Link,
                "file" => CueType::File,
                "voice" => CueType::Voice,
                _ => CueType::Note,
            };

            let title = title.unwrap_or_else(|| {
                if let Some(ref a) = anchor.app_name {
                    if let Some(ref w) = anchor.window_title {
                        format!("Resume {} ({})", a, w)
                    } else {
                        format!("Resume {}", a)
                    }
                } else {
                    "Untitled Thread".to_string()
                }
            });

            let thread_id = format!("sutra_{}", &uuid::Uuid::new_v4().to_string()[..13]);

            let thread = Thread {
                id: thread_id.clone(),
                cue_type: cue,
                title: title.clone(),
                notes,
                status: ThreadStatus::Waiting,
                created_at: now,
                updated_at: now,
                due_at: None,
                snoozed_until: None,
                anchor: Some(anchor),
                checklist: vec![],
                attachments: vec![],
                device_origin: "macOS".to_string(),
                tags,
            };

            db.create_thread(&thread)?;

            if json {
                println!("{}", serde_json::to_string_pretty(&thread)?);
            } else {
                println!("🪡 Sutra Thread Captured!");
                println!("   ID:     {}", thread.id);
                println!("   Title:  {}", thread.title);
                if let Some(ref a) = thread.anchor {
                    if let Some(ref app) = a.app_name {
                        println!("   App:    {}", app);
                    }
                    if let Some(ref u) = a.url {
                        println!("   URL:    {}", u);
                    }
                    if let Some(ref f) = a.file_path {
                        println!("   File:   {}", f);
                    }
                }
                println!("   Status: waiting");
            }
        }

        Commands::List { status, json } => {
            let filter = match status.to_lowercase().as_str() {
                "all" => None,
                "later" => Some(ThreadStatus::Later),
                "done" => Some(ThreadStatus::Done),
                _ => Some(ThreadStatus::Waiting),
            };

            let threads = db.list_threads(filter)?;

            if json {
                println!("{}", serde_json::to_string_pretty(&threads)?);
            } else if threads.is_empty() {
                println!("No threads in [{}] state.", status);
            } else {
                println!("─── SUTRA THREAD SANCTUARY [{}] ───", status.to_uppercase());
                for t in threads {
                    let anchor_info = match &t.anchor {
                        Some(a) => {
                            if let Some(app) = &a.app_name {
                                format!(" [{}]", app)
                            } else {
                                String::new()
                            }
                        }
                        None => String::new(),
                    };
                    println!(
                        "• [{}] {} - {}{}",
                        t.id,
                        t.status.to_string().to_uppercase(),
                        t.title,
                        anchor_info
                    );
                }
            }
        }

        Commands::Resume { id } => {
            let thread = db.get_thread(&id)?;
            execute_recovery(&thread)?;
        }

        Commands::Snooze { id, hours } => {
            let until = chrono::Utc::now().timestamp_millis() + (hours as i64 * 3600 * 1000);
            db.snooze_thread(&id, until)?;
            println!("⏳ Thread [{}] snoozed for {} hour(s) to LATER.", id, hours);
        }

        Commands::Done { id } => {
            db.update_status(&id, ThreadStatus::Done)?;
            println!("✓ Thread [{}] marked DONE.", id);
        }

        Commands::Undo { id } => {
            db.update_status(&id, ThreadStatus::Waiting)?;
            println!("↩ Thread [{}] restored back to WAITING.", id);
        }

        Commands::Search { query, json } => {
            let results = db.search_threads(&query)?;
            if json {
                println!("{}", serde_json::to_string_pretty(&results)?);
            } else if results.is_empty() {
                println!("No threads found matching \"{}\".", query);
            } else {
                println!("─── SUTRA SEARCH RESULTS FOR \"{}\" ───", query);
                for t in results {
                    println!("• [{}] {} - {}", t.id, t.status, t.title);
                }
            }
        }
    }

    Ok(())
}
