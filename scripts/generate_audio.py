#!/usr/bin/env python3
"""
generate_audio.py — Generates ultra-natural human woman narration (en-US-AvaNeural)
and an energetic cinematic hype music bed with 2.5s Fade-In, speech ducking, and 3.0s Fade-Out.
"""

import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets/launch/audio")
EDGE_TTS = shutil.which("edge-tts") or "edge-tts"
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"

os.makedirs(AUDIO_DIR, exist_ok=True)

# 7 Acts with natural conversational text and precise timestamps
ACTS = [
    {
        "id": "act1_intro",
        "start": 1.8,  # Music fades in first for hype
        "text": "Sutra. Sootram dhaaraya, punah aarabhasva. Leave the thread where you'll need it again. Find it when you're back."
    },
    {
        "id": "act2_crisis",
        "start": 10.2,
        "text": "Every three minutes and five seconds, knowledge workers are interrupted. UC Irvine research reveals it takes over twenty-three minutes to recover deep focus. This is Resumption Lag."
    },
    {
        "id": "act3_science",
        "start": 21.2,
        "text": "Cognitive psychology explains why. Working memory decays exponentially under interruption. But an explicit retrieval cue and concrete implementation intentions eliminate cognitive friction completely."
    },
    {
        "id": "act4_hud",
        "start": 33.2,
        "text": "Hit Control Option Space. In under fifteen milliseconds, Sutra's native sniffer captures your active window, file line, or web URL. Five multi-modal cue types hold your exact mental intention."
    },
    {
        "id": "act5_demos",
        "start": 46.2,
        "text": "Here it is in action. Leaving a voice memo cue over MacWhisper, and anchoring deep research in Chrome over Underdog AI. Exact context, instantly preserved across any application."
    },
    {
        "id": "act6_recovery",
        "start": 60.0,
        "text": "The Closed-App Recovery Guarantee. Even if applications quit or tabs close, one click relaunches the app and seeks directly to your line and link."
    },
    {
        "id": "act7_outro",
        "start": 71.8,
        "text": "One hundred percent offline. Sovereign SQLite storage with zero cloud telemetry. Sutra: Never lose your thread."
    }
]

TOTAL_DURATION = 82.0

def build_neural_voice_tracks():
    print("Synthesizing natural human woman voice (en-US-AvaNeural)...")
    for act in ACTS:
        mp3_raw = os.path.join(AUDIO_DIR, f"{act['id']}_raw.mp3")
        wav_path = os.path.join(AUDIO_DIR, f"{act['id']}.wav")
        
        # Synthesize via edge-tts with AvaNeural voice
        cmd_tts = [
            EDGE_TTS,
            "--voice", "en-US-AvaNeural",
            "--text", act["text"],
            "--write-media", mp3_raw
        ]
        subprocess.run(cmd_tts, check=True)

        # Convert to 48kHz stereo WAV with subtle warm presence EQ
        cmd_ffmpeg = [
            FFMPEG, "-y", "-i", mp3_raw,
            "-af", "highpass=f=80,equalizer=f=2800:width_type=q:width=1.2:g=2.2,alimiter=limit=0.98",
            "-ar", "48000", "-ac", "2",
            wav_path
        ]
        subprocess.run(cmd_ffmpeg, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        print(f"  ✓ {act['id']} rendered with AvaNeural")

def compose_hype_music_and_mix():
    print("Composing energetic cinematic hype music bed (with 2.5s Fade-In & 3.0s Fade-Out)...")
    raw_music = os.path.join(AUDIO_DIR, "hype_soundbed_raw.wav")
    
    # Sophisticated layered synth with driving rhythm:
    # 1. Warm sub-bass & root drone (D2, 73.4Hz + A2, 110Hz)
    # 2. Driving 16th-note pulsing arpeggio chords (D-minor: D3 146.8Hz, F3 174.6Hz, A3 220Hz, C4 261.6Hz)
    # 3. High energetic sparkle (880Hz rhythmic pulse)
    synth_expr = (
        # Bass foundation
        "0.18*sin(2*PI*73.4*t) + 0.14*sin(2*PI*110*t) + "
        # Driving arpeggiated melodic pulse (4 Hz gating for high-energy rhythm)
        "0.08*sin(2*PI*146.8*t)*(0.5+0.5*sin(2*PI*4*t)) + "
        "0.07*sin(2*PI*174.6*t)*(0.5+0.5*sin(2*PI*8*t)) + "
        "0.06*sin(2*PI*220.0*t)*(0.5+0.5*cos(2*PI*4*t)) + "
        "0.05*sin(2*PI*261.6*t)*(0.5+0.5*sin(2*PI*16*t)) + "
        # High rhythmic shimmer
        "0.03*sin(2*PI*880.0*t)*(0.5+0.5*sin(2*PI*8*t))"
    )

    # Filter with smooth 2.5s Fade-In, wide stereo chorus, echo, and 3.0s Fade-Out
    music_filter = (
        f"aevalsrc='{synth_expr}':d={TOTAL_DURATION}:s=48000[raw];"
        f"[raw]lowpass=f=1200,aecho=0.8:0.88:80|140:0.35|0.22,"
        f"afade=t=in:ss=0:d=2.5,afade=t=out:st=79.0:d=3.0,"
        f"volume=0.35[music]"
    )

    subprocess.run([
        FFMPEG, "-y",
        "-f", "lavfi", "-i", music_filter.replace("[music]", ""),
        "-t", str(TOTAL_DURATION),
        "-ar", "48000", "-ac", "2",
        raw_music
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    print("  ✓ Energetic hype soundbed generated")

    # Multi-input delay and mix
    inputs = ["-i", raw_music]
    filter_complex = []

    for idx, act in enumerate(ACTS, start=1):
        wav_path = os.path.join(AUDIO_DIR, f"{act['id']}.wav")
        inputs.extend(["-i", wav_path])
        delay_ms = int(act["start"] * 1000)
        filter_complex.append(f"[{idx}]adelay={delay_ms}|{delay_ms},volume=1.45[v{idx}];")

    v_mix_inputs = "".join(f"[v{i}]" for i in range(1, len(ACTS) + 1))
    filter_complex.append(f"{v_mix_inputs}amix=inputs={len(ACTS)}:normalize=0[all_voices];")
    # Duck music smoothly under narration
    filter_complex.append("[0:a]volume=0.30[music_ducked];")
    filter_complex.append("[music_ducked][all_voices]amix=inputs=2:duration=first:dropout_transition=2,alimiter=limit=0.96[master]")

    master_wav = os.path.join(AUDIO_DIR, "master_launch_audio.wav")
    master_mp3 = os.path.join(AUDIO_DIR, "master_launch_audio.mp3")

    cmd = [
        FFMPEG, "-y"
    ] + inputs + [
        "-filter_complex", "".join(filter_complex),
        "-map", "[master]",
        "-t", str(TOTAL_DURATION),
        "-ar", "48000", "-ac", "2",
        master_wav
    ]

    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    subprocess.run([FFMPEG, "-y", "-i", master_wav, "-b:a", "320k", master_mp3],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

    print(f"✓ Master Audio successfully compiled at:\n  - {master_wav}\n  - {master_mp3}")

if __name__ == "__main__":
    build_neural_voice_tracks()
    compose_hype_music_and_mix()
