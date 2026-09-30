/// On-device voice cue transcription interface.
///
/// Scaffold only — full whisper.rs integration is post-v1.0.
/// Interface contract is defined now so CLI and iOS can call it
/// without knowing when the backend arrives.
///
/// To enable: compile with `--features whisper` and add whisper-rs dep.
///
/// ponytail: stub returns Err until --features whisper is compiled in

/// Transcribe a local audio file to text.
/// Accepts m4a, wav, mp3.
/// Returns the transcribed string or a descriptive error.
pub fn transcribe_audio(path: &str) -> Result<String, String> {
    // ponytail: real impl — add whisper-rs + quantized ggml model when ready
    let _ = path;
    Err(format!(
        "sutra-voice: transcription not available. Recompile with --features whisper. (path: {path})"
    ))
}

/// Record a short voice memo via system microphone and transcribe it.
/// Duration: up to `max_seconds` (default 10).
///
/// ponytail: system mic capture deferred — add AVFoundation/CoreAudio bridge when whisper is live
pub fn record_and_transcribe(max_seconds: u32) -> Result<String, String> {
    let _ = max_seconds;
    Err("sutra-voice: recording not available. Recompile with --features whisper.".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transcribe_returns_err_without_feature() {
        let result = transcribe_audio("test.m4a");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("--features whisper"));
    }
}
