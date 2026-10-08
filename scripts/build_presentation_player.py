#!/usr/bin/env python3
"""
build_presentation_player.py — Generates self-contained 4K/1080p HTML motion presentation
with GSAP timelines, embedded audio, and interactive player controls.
"""

import os
import base64
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCH_DIR = os.path.join(ROOT, "assets/launch")
AUDIO_FILE = os.path.join(LAUNCH_DIR, "audio/master_launch_audio.mp3")

def file_to_base64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def generate_player():
    print("Embedding assets into self-contained HTML launch player...")
    
    logo_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "01_logo.png"))
    research_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "02_research.png"))
    hud_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "03_hud_steps.png"))
    cue_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "04_cue_types.png"))
    macwhisper_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "05_demo_macwhisper.png"))
    underdog_b64 = file_to_base64(os.path.join(LAUNCH_DIR, "06_demo_underdog.png"))
    audio_b64 = file_to_base64(AUDIO_FILE)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sutra — Official Product Launch Video</title>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js"></script>
  <style>
    :root {{
      --bg: #08080a;
      --surface: #121215;
      --surface-card: rgba(26, 26, 32, 0.85);
      --accent: #b3562a;
      --accent-glow: rgba(179, 86, 42, 0.45);
      --accent-light: #e07a48;
      --text: #ffffff;
      --text-muted: #8e8e93;
      --text-dim: #545458;
      --border: rgba(255, 255, 255, 0.10);
      --border-accent: rgba(179, 86, 42, 0.40);
    }}

    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      user-select: none;
    }}

    body {{
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }}

    /* 16:9 Cinema Container (Up to 4K / 1080p Crisp Scaling) */
    #cinema-viewport {{
      position: relative;
      width: 1920px;
      height: 1080px;
      background: radial-gradient(circle at 50% 45%, #181418 0%, #08080a 75%, #040405 100%);
      overflow: hidden;
      transform-origin: center center;
      box-shadow: 0 30px 100px rgba(0,0,0,0.8), 0 0 80px rgba(179, 86, 42, 0.15);
    }}

    /* Ambient Silk Thread Particle Canvas */
    #ambient-canvas {{
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
      z-index: 1;
      opacity: 0.7;
    }}

    /* Top Brand Watermark */
    .brand-pill {{
      position: absolute;
      top: 36px;
      left: 48px;
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 8px 18px;
      background: rgba(18, 18, 22, 0.7);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid var(--border);
      border-radius: 999px;
      z-index: 50;
    }}
    .brand-pill img {{
      width: 22px;
      height: 22px;
      object-fit: contain;
    }}
    .brand-pill span {{
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 2px;
      color: #fff5eb;
    }}
    .brand-tag {{
      position: absolute;
      top: 36px;
      right: 48px;
      padding: 6px 14px;
      background: rgba(179, 86, 42, 0.15);
      border: 1px solid var(--border-accent);
      border-radius: 6px;
      color: var(--accent-light);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 1.5px;
      text-transform: uppercase;
      z-index: 50;
    }}

    /* Scene Stage */
    .scene {{
      position: absolute;
      inset: 0;
      padding: 100px 100px 120px 100px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      opacity: 0;
      pointer-events: none;
      z-index: 10;
    }}
    .scene.active {{
      opacity: 1;
      pointer-events: auto;
    }}

    /* Typography */
    .eyebrow {{
      font-size: 15px;
      font-weight: 700;
      letter-spacing: 4px;
      text-transform: uppercase;
      color: var(--accent-light);
      margin-bottom: 16px;
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }}
    .title-large {{
      font-family: Georgia, serif;
      font-size: 72px;
      font-weight: 400;
      line-height: 1.05;
      text-align: center;
      letter-spacing: -1.5px;
      background: linear-gradient(180deg, #ffffff 30%, #a1a1aa 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 24px;
    }}
    .subtitle-lead {{
      font-size: 24px;
      font-weight: 400;
      line-height: 1.5;
      color: #d4d4d8;
      max-width: 860px;
      text-align: center;
      margin-bottom: 40px;
    }}
    .quote-box {{
      font-family: Georgia, serif;
      font-style: italic;
      font-size: 26px;
      color: #fbdac8;
      background: rgba(179, 86, 42, 0.12);
      border-left: 4px solid var(--accent);
      padding: 18px 32px;
      border-radius: 8px;
      margin-top: 20px;
      text-align: center;
    }}

    /* Emblem Presentation */
    .emblem-wrap {{
      position: relative;
      width: 220px;
      height: 220px;
      margin-bottom: 30px;
    }}
    .emblem-glow {{
      position: absolute;
      inset: -40px;
      background: radial-gradient(circle, var(--accent-glow) 0%, transparent 70%);
      filter: blur(30px);
      z-index: 1;
      animation: pulseGlow 4s infinite ease-in-out;
    }}
    .emblem-img {{
      position: relative;
      width: 100%;
      height: 100%;
      object-fit: contain;
      z-index: 2;
      filter: drop-shadow(0 20px 40px rgba(0,0,0,0.8));
    }}

    /* Split Cards Layout */
    .split-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 40px;
      width: 100%;
      max-width: 1560px;
      align-items: center;
    }}
    .card-frosted {{
      background: var(--surface-card);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 44px;
      box-shadow: 0 20px 50px rgba(0,0,0,0.6);
      backdrop-filter: blur(25px);
      -webkit-backdrop-filter: blur(25px);
    }}
    .stat-hero {{
      font-family: Georgia, serif;
      font-size: 84px;
      font-weight: 700;
      color: var(--accent-light);
      line-height: 1.0;
      margin-bottom: 8px;
    }}
    .stat-label {{
      font-size: 16px;
      letter-spacing: 2px;
      text-transform: uppercase;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 18px;
    }}
    .stat-desc {{
      font-size: 20px;
      line-height: 1.6;
      color: #e4e4e7;
    }}

    /* Image Showcase Frames */
    .media-card {{
      position: relative;
      border-radius: 16px;
      overflow: hidden;
      border: 1px solid rgba(255,255,255,0.15);
      box-shadow: 0 25px 60px rgba(0,0,0,0.7);
      background: #000;
    }}
    .media-card img {{
      width: 100%;
      height: auto;
      display: block;
      transition: transform 12s ease-out;
    }}
    .media-card:hover img {{
      transform: scale(1.03);
    }}
    .media-tag {{
      position: absolute;
      top: 18px;
      left: 18px;
      padding: 6px 14px;
      background: rgba(0, 0, 0, 0.75);
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      color: #fff;
      display: flex;
      align-items: center;
      gap: 6px;
      backdrop-filter: blur(10px);
    }}
    .dot-live {{
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #22c55e;
      box-shadow: 0 0 8px #22c55e;
    }}

    /* 5 Pillars Row */
    .pillar-row {{
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 20px;
      width: 100%;
      max-width: 1560px;
      margin-top: 36px;
    }}
    .pillar-item {{
      background: rgba(255,255,255,0.03);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 24px 18px;
      text-align: center;
      transition: border-color 0.3s;
    }}
    .pillar-item.highlight {{
      border-color: var(--accent);
      background: rgba(179, 86, 42, 0.10);
    }}
    .pillar-icon {{
      font-size: 28px;
      margin-bottom: 12px;
    }}
    .pillar-title {{
      font-size: 16px;
      font-weight: 700;
      color: #fff;
      margin-bottom: 6px;
    }}
    .pillar-sub {{
      font-size: 12px;
      color: var(--text-muted);
      line-height: 1.4;
    }}

    /* Bottom Control Bar */
    #transport-bar {{
      position: absolute;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%);
      width: 88%;
      max-width: 1200px;
      height: 58px;
      background: rgba(18, 18, 22, 0.88);
      backdrop-filter: blur(30px);
      -webkit-backdrop-filter: blur(30px);
      border: 1px solid rgba(255,255,255,0.12);
      border-radius: 30px;
      display: flex;
      align-items: center;
      padding: 0 24px;
      gap: 20px;
      z-index: 100;
      box-shadow: 0 20px 40px rgba(0,0,0,0.6);
    }}
    .btn-control {{
      background: none;
      border: none;
      color: #fff;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      width: 38px;
      height: 38px;
      border-radius: 50%;
      transition: background 0.2s, transform 0.1s;
    }}
    .btn-control:hover {{
      background: rgba(255,255,255,0.15);
      transform: scale(1.05);
    }}
    .time-label {{
      font-family: "SF Mono", Menlo, monospace;
      font-size: 12px;
      color: var(--text-muted);
      min-width: 85px;
    }}
    .timeline-slider-wrap {{
      flex: 1;
      position: relative;
      height: 6px;
      background: rgba(255,255,255,0.15);
      border-radius: 3px;
      cursor: pointer;
    }}
    .timeline-progress {{
      position: absolute;
      left: 0;
      top: 0;
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--accent) 0%, var(--accent-light) 100%);
      border-radius: 3px;
      box-shadow: 0 0 10px var(--accent);
    }}
    .scene-markers {{
      position: absolute;
      inset: 0;
      pointer-events: none;
    }}
    .scene-dot {{
      position: absolute;
      top: -3px;
      width: 2px;
      height: 12px;
      background: rgba(255,255,255,0.4);
    }}

    @keyframes pulseGlow {{
      0%, 100% {{ transform: scale(1); opacity: 0.45; }}
      50% {{ transform: scale(1.15); opacity: 0.75; }}
    }}
  </style>
</head>
<body>

  <div id="cinema-viewport">
    <canvas id="ambient-canvas"></canvas>

    <!-- Header Brand Watermark -->
    <div class="brand-pill">
      <img src="data:image/png;base64,{logo_b64}" alt="Sutra Logo">
      <span>SUTRA</span>
    </div>
    <div class="brand-tag">4K Sovereign Presentation</div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 1: THE EMBLEM & THE INFINITE SILK THREAD (0.0s - 8.0s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-1" data-start="0" data-end="8">
      <div class="emblem-wrap">
        <div class="emblem-glow"></div>
        <img class="emblem-img" src="data:image/png;base64,{logo_b64}" alt="Sutra Emblem">
      </div>
      <div class="eyebrow">Cognitive Restoration Architecture</div>
      <h1 class="title-large">Sutra</h1>
      <p class="subtitle-lead">सूत्रम् धारय, पुनः आरभस्व</p>
      <div class="quote-box">
        "Leave the thread where you'll need it again. Find it when you're back."
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 2: THE COGNITIVE CRISIS — RESUMPTION LAG (8.0s - 18.0s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-2" data-start="8" data-end="18">
      <div class="eyebrow">The Hidden Cost of Modern Knowledge Work</div>
      <h2 class="title-large" style="font-size: 58px; margin-bottom: 36px;">The Resumption Lag Crisis</h2>
      
      <div class="split-grid">
        <div class="card-frosted">
          <div class="stat-hero">3m 05s</div>
          <div class="stat-label">Average Interruption Frequency</div>
          <p class="stat-desc">Knowledge workers face disruptions or task switches every three minutes. Deep flow is perpetually fractured.</p>
        </div>
        <div class="card-frosted" style="border-color: var(--border-accent);">
          <div class="stat-hero" style="color: #f87171;">23m 15s</div>
          <div class="stat-label">Average Recovery Lag</div>
          <p class="stat-desc">UC Irvine research confirms it takes over twenty-three minutes to re-establish deep cognitive context after a suspension.</p>
        </div>
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 3: RESEARCH-BACKED COGNITIVE ARCHITECTURE (18.0s - 28.5s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-3" data-start="18" data-end="28.5">
      <div class="eyebrow">Rigorous Cognitive Science Foundation</div>
      <h2 class="title-large" style="font-size: 54px; margin-bottom: 30px;">Two Psychological Discoveries</h2>

      <div class="split-grid" style="align-items: stretch;">
        <div class="card-frosted">
          <div style="font-size: 22px; font-weight: 700; color: var(--accent-light); margin-bottom: 12px;">
            Altmann & Trafton (2002) — Memory for Goals
          </div>
          <p class="stat-desc" style="font-size: 18px; margin-bottom: 16px;">
            Working memory decays exponentially during an interruption. Placing an explicit, salient <strong>retrieval cue</strong> at the exact point of suspension reduces resumption lag by <strong>over 80%</strong>.
          </p>
          <div style="font-size: 14px; color: var(--text-muted); border-top: 1px solid var(--border); padding-top: 12px;">
            The Needle: Surgical anchor pinning line, file, and spatial coordinates.
          </div>
        </div>

        <div class="card-frosted">
          <div style="font-size: 22px; font-weight: 700; color: var(--accent-light); margin-bottom: 12px;">
            Gollwitzer — Implementation Intentions
          </div>
          <p class="stat-desc" style="font-size: 18px; margin-bottom: 16px;">
            Abstract to-do lists fail under fatigue. Concrete <em>"When Situation X occurs, execute Action Y"</em> triggers make cognitive resumption near-automatic and involuntary.
          </p>
          <div style="font-size: 14px; color: var(--text-muted); border-top: 1px solid var(--border); padding-top: 12px;">
            The Silk Thread: Unbroken continuity weaving across all macOS apps.
          </div>
        </div>
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 4: THE 2-SECOND HUD & 5 CUE TYPES (28.5s - 39.5s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-4" data-start="28.5" data-end="39.5">
      <div class="eyebrow">Zero-Friction Context Capture</div>
      <h2 class="title-large" style="font-size: 52px; margin-bottom: 16px;">The 2-Second Quick Cue HUD</h2>
      <p class="subtitle-lead" style="font-size: 20px; margin-bottom: 24px;">
        Trigger anywhere in macOS via <span style="font-family: monospace; background: rgba(255,255,255,0.12); padding: 4px 10px; border-radius: 6px;">⌃ Control + ⌥ Option + Space</span>. Sniffs context in &lt; 15ms.
      </p>

      <div class="pillar-row">
        <div class="pillar-item highlight">
          <div class="pillar-icon">📝</div>
          <div class="pillar-title">Note</div>
          <div class="pillar-sub">Single immediate next physical action</div>
        </div>
        <div class="pillar-item">
          <div class="pillar-icon">☑️</div>
          <div class="pillar-title">Checklist</div>
          <div class="pillar-sub">Sequential micro-actions with checkmarks</div>
        </div>
        <div class="pillar-item">
          <div class="pillar-icon">🔗</div>
          <div class="pillar-title">Link</div>
          <div class="pillar-sub">URL with exact video or document timestamp</div>
        </div>
        <div class="pillar-item">
          <div class="pillar-icon">📄</div>
          <div class="pillar-title">File / Excerpt</div>
          <div class="pillar-sub">Local file path, crash log, or code snapshot</div>
        </div>
        <div class="pillar-item">
          <div class="pillar-icon">🎙️</div>
          <div class="pillar-title">Voice Memo</div>
          <div class="pillar-sub">Hands-busy spoken micro-cue transcribed</div>
        </div>
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 5: REAL-WORLD IN-ACTION DEMOS (39.5s - 51.5s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-5" data-start="39.5" data-end="51.5">
      <div class="eyebrow">Production-Verified Reality</div>
      <h2 class="title-large" style="font-size: 52px; margin-bottom: 24px;">Sutra Operating Across Real Workflows</h2>

      <div class="split-grid">
        <div class="media-card">
          <div class="media-tag"><span class="dot-live"></span> MacWhisper Live Cue Sniff</div>
          <img src="data:image/png;base64,{macwhisper_b64}" alt="MacWhisper HUD Snap">
        </div>
        <div class="media-card">
          <div class="media-tag"><span class="dot-live"></span> Chrome Underdog AI Web Anchor</div>
          <img src="data:image/png;base64,{underdog_b64}" alt="Underdog AI HUD Snap">
        </div>
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 6: THE 1-CLICK CLOSED-APP RECOVERY CONTRACT (51.5s - 62.5s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-6" data-start="51.5" data-end="62.5">
      <div class="eyebrow">Deterministic Workspace Restoration</div>
      <h2 class="title-large" style="font-size: 52px; margin-bottom: 24px;">The Closed-App Recovery Contract</h2>

      <div class="card-frosted" style="max-width: 1100px; width: 100%; border-color: var(--border-accent);">
        <p class="quote-box" style="margin-top: 0; margin-bottom: 24px; font-size: 22px;">
          "Even if the target application was completely quit, the window dismissed, or the browser tab closed, Sutra restores your physical workspace with a single click."
        </p>
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 24px; text-align: left;">
          <div>
            <div style="color: var(--accent-light); font-weight: 700; margin-bottom: 6px;">Web & PWA Anchors</div>
            <div style="font-size: 14px; color: #d4d4d8; line-height: 1.5;">Calls native handlers or Chrome PWA bundle IDs to focus the exact URL.</div>
          </div>
          <div>
            <div style="color: var(--accent-light); font-weight: 700; margin-bottom: 6px;">Code Editor Anchors</div>
            <div style="font-size: 14px; color: #d4d4d8; line-height: 1.5;">Invokes <code>code -g path:line</code> to reposition cursor at the exact suspended function.</div>
          </div>
          <div>
            <div style="color: var(--accent-light); font-weight: 700; margin-bottom: 6px;">Quit Applications</div>
            <div style="font-size: 14px; color: #d4d4d8; line-height: 1.5;">Utilizes <code>NSWorkspace</code> and <code>open -a</code> to spin up closed binaries instantly.</div>
          </div>
        </div>
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         SCENE 7: SOVEREIGN IDENTITY & OUTRO (62.5s - 73.0s)
    ═════════════════════════════════════════════════════════════════════════ -->
    <div class="scene" id="scene-7" data-start="62.5" data-end="73.0">
      <div class="emblem-wrap" style="width: 180px; height: 180px; margin-bottom: 20px;">
        <div class="emblem-glow"></div>
        <img class="emblem-img" src="data:image/png;base64,{logo_b64}" alt="Sutra Emblem">
      </div>
      <div class="eyebrow">Zero Cloud Telemetry • 100% Offline WAL Sovereignty</div>
      <h1 class="title-large" style="font-size: 64px; margin-bottom: 16px;">Never Lose Your Thread.</h1>
      <p class="subtitle-lead" style="font-size: 22px; margin-bottom: 24px;">
        Sutra is live on macOS. Native Rust Context Engine & Swift AppKit HUD.
      </p>
      <div style="font-size: 13px; color: var(--text-dim); letter-spacing: 1px;">
        Created by Ramesh • 22 September 2026 • Sutra Sovereign Engineering Hub
      </div>
    </div>

    <!-- ════════════════════════════════════════════════════════════════════════
         TRANSPORT CONTROL BAR
    ═════════════════════════════════════════════════════════════════════════ -->
    <div id="transport-bar">
      <button class="btn-control" id="play-btn" title="Play/Pause (Space)">▶</button>
      <div class="time-label" id="time-display">00:00 / 01:13</div>
      
      <div class="timeline-slider-wrap" id="slider-wrap">
        <div class="timeline-progress" id="progress-bar"></div>
        <div class="scene-markers">
          <div class="scene-dot" style="left: 0%;"></div>
          <div class="scene-dot" style="left: 10.9%;"></div>
          <div class="scene-dot" style="left: 24.6%;"></div>
          <div class="scene-dot" style="left: 39.0%;"></div>
          <div class="scene-dot" style="left: 54.1%;"></div>
          <div class="scene-dot" style="left: 70.5%;"></div>
          <div class="scene-dot" style="left: 85.6%;"></div>
        </div>
      </div>

      <button class="btn-control" id="mute-btn" title="Mute/Unmute">🔊</button>
      <button class="btn-control" id="fs-btn" title="Full Screen">⛶</button>
    </div>

    <audio id="master-audio" preload="auto">
      <source src="data:audio/mp3;base64,{audio_b64}" type="audio/mp3">
    </audio>
  </div>

  <script>
    // Responsive scaling to fit any screen while preserving 16:9 ratio
    const viewport = document.getElementById("cinema-viewport");
    function fitScreen() {{
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      const scale = Math.min(vw / 1920, vh / 1080);
      viewport.style.transform = `scale(${{scale}})`;
    }}
    window.addEventListener("resize", fitScreen);
    fitScreen();

    // Ambient floating particles canvas
    const canvas = document.getElementById("ambient-canvas");
    const ctx = canvas.getContext("2d");
    canvas.width = 1920;
    canvas.height = 1080;
    const particles = Array.from({{ length: 45 }}, () => ({{
      x: Math.random() * 1920,
      y: Math.random() * 1080,
      vx: (Math.random() - 0.5) * 0.4,
      vy: (Math.random() - 0.5) * 0.4,
      radius: Math.random() * 2 + 1,
      alpha: Math.random() * 0.5 + 0.2
    }}));

    function animateParticles() {{
      ctx.clearRect(0, 0, 1920, 1080);
      ctx.fillStyle = "#b3562a";
      for (const p of particles) {{
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0) p.x = 1920;
        if (p.x > 1920) p.x = 0;
        if (p.y < 0) p.y = 1080;
        if (p.y > 1080) p.y = 0;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
        ctx.globalAlpha = p.alpha;
        ctx.fill();
      }}
      requestAnimationFrame(animateParticles);
    }}
    animateParticles();

    // Scene timing contracts (82.0s timeline)
    const scenes = [
      {{ id: "scene-1", start: 0.0, end: 9.0 }},
      {{ id: "scene-2", start: 9.0, end: 20.0 }},
      {{ id: "scene-3", start: 20.0, end: 32.0 }},
      {{ id: "scene-4", start: 32.0, end: 45.0 }},
      {{ id: "scene-5", start: 45.0, end: 59.0 }},
      {{ id: "scene-6", start: 59.0, end: 70.5 }},
      {{ id: "scene-7", start: 70.5, end: 82.0 }}
    ];

    const audio = document.getElementById("master-audio");
    const playBtn = document.getElementById("play-btn");
    const muteBtn = document.getElementById("mute-btn");
    const fsBtn = document.getElementById("fs-btn");
    const progressBar = document.getElementById("progress-bar");
    const sliderWrap = document.getElementById("slider-wrap");
    const timeDisplay = document.getElementById("time-display");

    let currentSceneIdx = -1;

    function formatTime(s) {{
      const m = Math.floor(s / 60);
      const sec = Math.floor(s % 60);
      return `${{m.toString().padStart(2, "0")}}:${{sec.toString().padStart(2, "0")}}`;
    }}

    function updateScene(time) {{
      let activeIdx = scenes.findIndex(s => time >= s.start && time < s.end);
      if (activeIdx === -1) activeIdx = scenes.length - 1;

      if (activeIdx !== currentSceneIdx) {{
        scenes.forEach((s, idx) => {{
          const el = document.getElementById(s.id);
          if (idx === activeIdx) {{
            el.classList.add("active");
            gsap.fromTo(el, {{ opacity: 0, y: 30, scale: 0.98 }}, {{ opacity: 1, y: 0, scale: 1, duration: 0.8, ease: "power2.out" }});
          }} else {{
            el.classList.remove("active");
          }}
        }});
        currentSceneIdx = activeIdx;
      }}
    }}

    // Transport sync
    audio.addEventListener("timeupdate", () => {{
      const cur = audio.currentTime;
      const dur = audio.duration || 82.0;
      progressBar.style.width = `${{(cur / dur) * 100}}%`;
      timeDisplay.textContent = `${{formatTime(cur)}} / ${{formatTime(dur)}}`;
      updateScene(cur);
    }});

    audio.addEventListener("ended", () => {{
      playBtn.textContent = "▶";
    }});

    function togglePlay() {{
      if (audio.paused) {{
        audio.play().catch(e => console.log("Audio play error", e));
        playBtn.textContent = "⏸";
      }} else {{
        audio.pause();
        playBtn.textContent = "▶";
      }}
    }}

    playBtn.addEventListener("click", togglePlay);

    document.addEventListener("keydown", (e) => {{
      if (e.code === "Space") {{
        e.preventDefault();
        togglePlay();
      }} else if (e.code === "ArrowRight") {{
        audio.currentTime = Math.min(audio.currentTime + 5, audio.duration || 73);
      }} else if (e.code === "ArrowLeft") {{
        audio.currentTime = Math.max(audio.currentTime - 5, 0);
      }}
    }});

    sliderWrap.addEventListener("click", (e) => {{
      const rect = sliderWrap.getBoundingClientRect();
      const pos = (e.clientX - rect.left) / rect.width;
      const targetTime = pos * (audio.duration || 73.0);
      audio.currentTime = targetTime;
    }});

    muteBtn.addEventListener("click", () => {{
      audio.muted = !audio.muted;
      muteBtn.textContent = audio.muted ? "🔇" : "🔊";
    }});

    fsBtn.addEventListener("click", () => {{
      if (!document.fullscreenElement) {{
        document.documentElement.requestFullscreen().catch(err => {{}});
      }} else {{
        document.exitFullscreen();
      }}
    }});

    // Initial scene
    updateScene(0);
  </script>
</body>
</html>
"""

    player_path = os.path.join(ROOT, "assets/launch_video.html")
    desktop_player_path = os.path.expanduser("~/Desktop/Sutra_Launch_Presentation.html")

    with open(player_path, "w", encoding="utf-8") as f:
        f.write(html)
    try:
        with open(desktop_player_path, "w", encoding="utf-8") as f:
            f.write(html)
        print(f"✓ Desktop copy saved to: {desktop_player_path}")
    except Exception as e:
        print(f"  Note: Desktop write ({e}) skipped in sandbox.")

    print(f"✓ Master Interactive HTML Video Player written to: {player_path}")
    return player_path

if __name__ == "__main__":
    generate_player()
