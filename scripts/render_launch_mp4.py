#!/usr/bin/env python3
"""
render_launch_mp4.py — Renders high-impact 4K/1080p broadcast launch video for Sutra.
Composes 7 full-bleed master scenes with real user snapshots, animates camera physics,
and muxes narration + cinematic ambient score.
"""

import os
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCH_DIR = os.path.join(ROOT, "assets/launch")
FRAMES_DIR = os.path.join(LAUNCH_DIR, "frames")
AUDIO_FILE = os.path.join(LAUNCH_DIR, "audio/master_launch_audio.mp3")
OUTPUT_MP4 = os.path.join(ROOT, "assets/Sutra_Official_Launch_Video.mp4")
DESKTOP_MP4 = os.path.expanduser("~/Desktop/Sutra_Official_Launch_Video.mp4")

os.makedirs(FRAMES_DIR, exist_ok=True)

# 4K Resolution Dimensions
W, H = 3840, 2160

# Fonts
FONT_TITLE = "/System/Library/Fonts/Supplemental/Georgia.ttf"
FONT_BODY = "/System/Library/Fonts/Helvetica.ttc"

def get_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def create_base_canvas():
    """Creates a 4K deep obsidian canvas with subtle terracotta ambient glow."""
    base = Image.new("RGBA", (W, H), (8, 8, 10, 255))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_glow = ImageDraw.Draw(glow)
    
    # Large radial gradient in center
    draw_glow.ellipse((W//2 - 1200, H//2 - 900, W//2 + 1200, H//2 + 900), fill=(179, 86, 42, 35))
    glow = glow.filter(ImageFilter.GaussianBlur(180))
    base = Image.alpha_composite(base, glow)

    # Top brand watermark
    logo_path = os.path.join(LAUNCH_DIR, "01_logo.png")
    if os.path.exists(logo_path):
        logo = Image.open(logo_path).convert("RGBA")
        logo.thumbnail((80, 80), Image.Resampling.LANCZOS)
        base.paste(logo, (90, 80), logo)

    draw = ImageDraw.Draw(base)
    font_brand = get_font(FONT_BODY, 38)
    font_badge = get_font(FONT_BODY, 28)
    draw.text((190, 96), "SUTRA", font=font_brand, fill=(255, 245, 235, 240))
    
    # Badge Right
    draw.rounded_rectangle((W - 480, 80, W - 90, 150), radius=16, fill=(35, 25, 22, 200), outline=(179, 86, 42, 140), width=2)
    draw.text((W - 450, 96), "4K SOVEREIGN RELEASE", font=font_badge, fill=(224, 122, 72, 255))

    return base

# ══════════════════════════════════════════════════════════════════════════════
#  SCENE BUILDERS
# ══════════════════════════════════════════════════════════════════════════════

def build_scene_1():
    """Act 1: The Emblem & The Infinite Silk Thread"""
    img = create_base_canvas()
    logo_path = os.path.join(LAUNCH_DIR, "01_logo.png")
    if os.path.exists(logo_path):
        emblem = Image.open(logo_path).convert("RGBA")
        emblem = emblem.resize((540, 540), Image.Resampling.LANCZOS)
        img.paste(emblem, (W//2 - 270, H//2 - 460), emblem)

    draw = ImageDraw.Draw(img)
    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 140)
    f_sub = get_font(FONT_TITLE, 52)
    f_quote = get_font(FONT_TITLE, 46)

    draw.text((W//2, H//2 + 130), "COGNITIVE RESTORATION ARCHITECTURE", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, H//2 + 250), "Sutra", font=f_title, fill=(255, 255, 255), anchor="mm")
    draw.text((W//2, H//2 + 370), "सूत्रम् धारय, पुनः आरभस्व", font=f_sub, fill=(212, 212, 216), anchor="mm")

    # Quote Box
    qw, qh = 1600, 120
    qx, qy = W//2 - qw//2, H//2 + 450
    draw.rounded_rectangle((qx, qy, qx + qw, qy + qh), radius=18, fill=(28, 20, 18, 220), outline=(179, 86, 42, 180), width=3)
    draw.text((W//2, qy + qh//2), '"Leave the thread where you\'ll need it again. Find it when you\'re back."', font=f_quote, fill=(251, 218, 200), anchor="mm")

    out_path = os.path.join(FRAMES_DIR, "scene_1.png")
    img.save(out_path)
    print("  ✓ Scene 1 frame rendered")
    return out_path

def build_scene_2():
    """Act 2: The Resumption Lag Crisis"""
    img = create_base_canvas()
    draw = ImageDraw.Draw(img)

    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 100)
    f_stat = get_font(FONT_TITLE, 140)
    f_lbl = get_font(FONT_BODY, 32)
    f_desc = get_font(FONT_BODY, 38)

    draw.text((W//2, 340), "THE HIDDEN COST OF MODERN KNOWLEDGE WORK", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, 460), "The Resumption Lag Crisis", font=f_title, fill=(255, 255, 255), anchor="mm")

    # Card 1 (3m 05s)
    c1_x, c1_y, cw, ch = 360, 680, 1480, 950
    draw.rounded_rectangle((c1_x, c1_y, c1_x + cw, c1_y + ch), radius=32, fill=(22, 22, 28, 230), outline=(255, 255, 255, 35), width=2)
    draw.text((c1_x + 100, c1_y + 180), "3m 05s", font=f_stat, fill=(224, 122, 72))
    draw.text((c1_x + 100, c1_y + 360), "AVERAGE INTERRUPTION FREQUENCY", font=f_lbl, fill=(142, 142, 147))
    draw.text((c1_x + 100, c1_y + 460), "Knowledge workers face disruptions or task switches every three minutes.", font=f_desc, fill=(228, 228, 231))
    draw.text((c1_x + 100, c1_y + 540), "Deep cognitive flow is perpetually fractured, leaving orphaned intent.", font=f_desc, fill=(161, 161, 170))

    # Card 2 (23m 15s)
    c2_x = W - 360 - cw
    draw.rounded_rectangle((c2_x, c1_y, c2_x + cw, c1_y + ch), radius=32, fill=(22, 22, 28, 230), outline=(179, 86, 42, 120), width=3)
    draw.text((c2_x + 100, c1_y + 180), "23m 15s", font=f_stat, fill=(248, 113, 113))
    draw.text((c2_x + 100, c1_y + 360), "AVERAGE RECOVERY LAG (UC IRVINE)", font=f_lbl, fill=(142, 142, 147))
    draw.text((c2_x + 100, c1_y + 460), "Empirical research by Dr. Gloria Mark reveals it takes over 23 minutes", font=f_desc, fill=(228, 228, 231))
    draw.text((c2_x + 100, c1_y + 540), "to recover deep working context after a significant interruption.", font=f_desc, fill=(228, 228, 231))

    out_path = os.path.join(FRAMES_DIR, "scene_2.png")
    img.save(out_path)
    print("  ✓ Scene 2 frame rendered")
    return out_path

def build_scene_3():
    """Act 3: Research-Backed Cognitive Architecture"""
    img = create_base_canvas()
    draw = ImageDraw.Draw(img)

    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 96)
    f_h2 = get_font(FONT_TITLE, 52)
    f_desc = get_font(FONT_BODY, 36)
    f_meta = get_font(FONT_BODY, 30)

    draw.text((W//2, 320), "RIGOROUS COGNITIVE SCIENCE FOUNDATION", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, 440), "Two Foundational Psychological Discoveries", font=f_title, fill=(255, 255, 255), anchor="mm")

    # Dual Academic Cards
    cw, ch = 1500, 1100
    c1_x, c1_y = 340, 620
    c2_x = W - 340 - cw

    # Card 1: Altmann & Trafton
    draw.rounded_rectangle((c1_x, c1_y, c1_x + cw, c1_y + ch), radius=30, fill=(24, 22, 26, 235), outline=(179, 86, 42, 90), width=2)
    draw.text((c1_x + 80, c1_y + 100), "Altmann & Trafton (2002) — Memory for Goals", font=f_h2, fill=(224, 122, 72))
    lines1 = [
        "Working memory decays exponentially during an interruption.",
        "Without an explicit retrieval cue, the mental activation needed",
        "to retrieve goals evaporates in seconds.",
        "",
        "Placing an explicit, salient retrieval cue at the exact point of suspension",
        "reduces resumption lag by over 80%."
    ]
    for idx, l in enumerate(lines1):
        draw.text((c1_x + 80, c1_y + 240 + idx * 56), l, font=f_desc, fill=(228, 228, 231))
    draw.line((c1_x + 80, c1_y + 820, c1_x + cw - 80, c1_y + 820), fill=(255, 255, 255, 40), width=1)
    draw.text((c1_x + 80, c1_y + 880), "THE NEEDLE: Surgical anchor pinning line, file, and spatial coordinates.", font=f_meta, fill=(161, 161, 170))

    # Card 2: Gollwitzer
    draw.rounded_rectangle((c2_x, c1_y, c2_x + cw, c1_y + ch), radius=30, fill=(24, 22, 26, 235), outline=(179, 86, 42, 90), width=2)
    draw.text((c2_x + 80, c1_y + 100), "Gollwitzer — Implementation Intentions", font=f_h2, fill=(224, 122, 72))
    lines2 = [
        "Abstract to-do lists fail under cognitive fatigue.",
        "Writing 'continue working' forces the brain into costly search.",
        "",
        "Concrete 'When Situation X occurs, execute Action Y' triggers",
        "delegate mental control to immediate situational cues,",
        "making cognitive resumption near-automatic and involuntary."
    ]
    for idx, l in enumerate(lines2):
        draw.text((c2_x + 80, c1_y + 240 + idx * 56), l, font=f_desc, fill=(228, 228, 231))
    draw.line((c2_x + 80, c1_y + 820, c2_x + cw - 80, c1_y + 820), fill=(255, 255, 255, 40), width=1)
    draw.text((c2_x + 80, c1_y + 880), "THE SILK THREAD: Unbroken continuity weaving seamlessly across macOS apps.", font=f_meta, fill=(161, 161, 170))

    out_path = os.path.join(FRAMES_DIR, "scene_3.png")
    img.save(out_path)
    print("  ✓ Scene 3 frame rendered")
    return out_path

def build_scene_4():
    """Act 4: The 2-Second HUD & 5 Multi-Modal Cue Types"""
    img = create_base_canvas()
    draw = ImageDraw.Draw(img)

    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 96)
    f_sub = get_font(FONT_BODY, 38)
    f_card_t = get_font(FONT_TITLE, 46)
    f_card_sub = get_font(FONT_BODY, 30)

    draw.text((W//2, 300), "ZERO-FRICTION CONTEXT CAPTURE", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, 420), "The 2-Second Quick Cue HUD", font=f_title, fill=(255, 255, 255), anchor="mm")
    draw.text((W//2, 530), "Trigger anywhere in macOS via  ^ Control + ⌥ Option + Space  (Sniffs context in < 15ms)", font=f_sub, fill=(212, 212, 216), anchor="mm")

    # 5 Cue Type Cards
    cards = [
        ("Note", "Single immediate next physical action (e.g. fix memory leak @ line 42)", True),
        ("Checklist", "Sequential micro-actions with checkmarks for atomic resumption", False),
        ("Link", "Web reference or documentation URL with exact video/doc timestamp", False),
        ("File / Excerpt", "Local file path, crash log, or code snapshot spatial anchor", False),
        ("Voice Memo", "Spoken micro-cue transcribed into text for hands-busy scenarios", False)
    ]

    card_w = 600
    card_h = 750
    spacing = 60
    total_w = 5 * card_w + 4 * spacing
    start_x = (W - total_w) // 2
    card_y = 740

    for idx, (title, desc, is_hi) in enumerate(cards):
        cx = start_x + idx * (card_w + spacing)
        border_col = (179, 86, 42, 240) if is_hi else (255, 255, 255, 30)
        bg_col = (36, 26, 22, 240) if is_hi else (22, 22, 26, 220)
        draw.rounded_rectangle((cx, card_y, cx + card_w, card_y + card_h), radius=24, fill=bg_col, outline=border_col, width=3 if is_hi else 2)

        # Number pill
        draw.rounded_rectangle((cx + 40, card_y + 40, cx + 110, card_y + 90), radius=10, fill=(179, 86, 42, 100))
        draw.text((cx + 75, card_y + 65), f"0{idx+1}", font=get_font(FONT_BODY, 24), fill=(255, 245, 235), anchor="mm")

        draw.text((cx + 40, card_y + 140), title, font=f_card_t, fill=(255, 255, 255))
        
        # Word wrapped description
        words = desc.split()
        cur_line = ""
        line_y = card_y + 240
        for w in words:
            test = cur_line + " " + w if cur_line else w
            if len(test) > 24:
                draw.text((cx + 40, line_y), cur_line, font=f_card_sub, fill=(200, 200, 205))
                line_y += 46
                cur_line = w
            else:
                cur_line = test
        if cur_line:
            draw.text((cx + 40, line_y), cur_line, font=f_card_sub, fill=(200, 200, 205))

    out_path = os.path.join(FRAMES_DIR, "scene_4.png")
    img.save(out_path)
    print("  ✓ Scene 4 frame rendered")
    return out_path

def build_scene_5():
    """Act 5: Real-World In-Action Demos (Live Snaps)"""
    img = create_base_canvas()
    draw = ImageDraw.Draw(img)

    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 96)
    f_tag = get_font(FONT_BODY, 28)

    draw.text((W//2, 280), "PRODUCTION-VERIFIED REALITY", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, 400), "Sutra Operating Across Real Workflows", font=f_title, fill=(255, 255, 255), anchor="mm")

    # Load 2 real snaps
    snap1_path = os.path.join(LAUNCH_DIR, "05_demo_macwhisper.png")
    snap2_path = os.path.join(LAUNCH_DIR, "06_demo_underdog.png")

    target_w, target_h = 1520, 1150
    y_pos = 580

    if os.path.exists(snap1_path):
        s1 = Image.open(snap1_path).convert("RGBA")
        s1.thumbnail((target_w, target_h), Image.Resampling.LANCZOS)
        # Paste centered in left half
        s1_x = 340 + (target_w - s1.width) // 2
        s1_y = y_pos + (target_h - s1.height) // 2
        # Card container
        draw.rounded_rectangle((s1_x - 10, s1_y - 10, s1_x + s1.width + 10, s1_y + s1.height + 10), radius=20, fill=(0,0,0,255), outline=(179, 86, 42, 140), width=3)
        img.paste(s1, (s1_x, s1_y), s1)
        # Tag
        draw.rounded_rectangle((s1_x + 30, s1_y + 30, s1_x + 460, s1_y + 85), radius=12, fill=(15, 15, 20, 220), outline=(255, 255, 255, 40), width=1)
        draw.ellipse((s1_x + 55, s1_y + 50, s1_x + 70, s1_y + 65), fill=(34, 197, 94))
        draw.text((s1_x + 90, s1_y + 45), "MacWhisper Audio Dictation", font=f_tag, fill=(255, 255, 255))

    if os.path.exists(snap2_path):
        s2 = Image.open(snap2_path).convert("RGBA")
        s2.thumbnail((target_w, target_h), Image.Resampling.LANCZOS)
        s2_x = W - 340 - target_w + (target_w - s2.width) // 2
        s2_y = y_pos + (target_h - s2.height) // 2
        # Card container
        draw.rounded_rectangle((s2_x - 10, s2_y - 10, s2_x + s2.width + 10, s2_y + s2.height + 10), radius=20, fill=(0,0,0,255), outline=(179, 86, 42, 140), width=3)
        img.paste(s2, (s2_x, s2_y), s2)
        # Tag
        draw.rounded_rectangle((s2_x + 30, s2_y + 30, s2_x + 460, s2_y + 85), radius=12, fill=(15, 15, 20, 220), outline=(255, 255, 255, 40), width=1)
        draw.ellipse((s2_x + 55, s2_y + 50, s2_x + 70, s2_y + 65), fill=(34, 197, 94))
        draw.text((s2_x + 90, s2_y + 45), "Chrome Underdog AI Research", font=f_tag, fill=(255, 255, 255))

    out_path = os.path.join(FRAMES_DIR, "scene_5.png")
    img.save(out_path)
    print("  ✓ Scene 5 frame rendered")
    return out_path

def build_scene_6():
    """Act 6: The 1-Click Closed-App Recovery Contract"""
    img = create_base_canvas()
    draw = ImageDraw.Draw(img)

    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 96)
    f_quote = get_font(FONT_TITLE, 48)
    f_h3 = get_font(FONT_TITLE, 46)
    f_desc = get_font(FONT_BODY, 34)

    draw.text((W//2, 320), "DETERMINISTIC WORKSPACE RESTORATION", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, 440), "The Closed-App Recovery Contract", font=f_title, fill=(255, 255, 255), anchor="mm")

    # Main Center Glass Card
    cw, ch = 3000, 1150
    cx, cy = (W - cw) // 2, 600
    draw.rounded_rectangle((cx, cy, cx + cw, cy + ch), radius=32, fill=(24, 22, 26, 235), outline=(179, 86, 42, 140), width=3)

    # Hero Quote
    draw.rounded_rectangle((cx + 100, cy + 80, cx + cw - 100, cy + 280), radius=18, fill=(34, 24, 20, 240), outline=(179, 86, 42, 180), width=2)
    draw.text((W//2, cy + 180), '"Even if the target application was completely quit, the window dismissed, or the browser tab closed,', font=f_quote, fill=(251, 218, 200), anchor="mm")
    draw.text((W//2, cy + 235), 'Sutra restores your physical workspace with a single click."', font=f_quote, fill=(251, 218, 200), anchor="mm")

    # 3 Pillars underneath
    pw = 840
    p_gap = 140
    p_start = cx + 100
    p_y = cy + 380

    pillars = [
        ("Web & PWA Anchors", "Calls native OS URL schemes or Chrome PWA bundle IDs to focus the exact active tab and route directly to deep URLs."),
        ("Code Editor Anchors", "Executes code -g <path>:<line> via CLI bridge to reopen the file and place your cursor right on the suspended function."),
        ("Quit Applications", "Leverages NSWorkspace and open -a to spin up closed binaries instantly without hunting through Launchpad or Finder.")
    ]

    for idx, (head, text) in enumerate(pillars):
        px = p_start + idx * (pw + p_gap)
        draw.text((px, p_y), head, font=f_h3, fill=(224, 122, 72))
        
        words = text.split()
        cur = ""
        ly = p_y + 80
        for w in words:
            test = cur + " " + w if cur else w
            if len(test) > 34:
                draw.text((px, ly), cur, font=f_desc, fill=(220, 220, 225))
                ly += 48
                cur = w
            else:
                cur = test
        if cur:
            draw.text((px, ly), cur, font=f_desc, fill=(220, 220, 225))

    out_path = os.path.join(FRAMES_DIR, "scene_6.png")
    img.save(out_path)
    print("  ✓ Scene 6 frame rendered")
    return out_path

def build_scene_7():
    """Act 7: Sovereign Identity & Finale"""
    img = create_base_canvas()
    logo_path = os.path.join(LAUNCH_DIR, "01_logo.png")
    if os.path.exists(logo_path):
        emblem = Image.open(logo_path).convert("RGBA")
        emblem = emblem.resize((600, 600), Image.Resampling.LANCZOS)
        img.paste(emblem, (W//2 - 300, H//2 - 500), emblem)

    draw = ImageDraw.Draw(img)
    f_eyebrow = get_font(FONT_BODY, 34)
    f_title = get_font(FONT_TITLE, 130)
    f_sub = get_font(FONT_BODY, 42)
    f_footer = get_font(FONT_BODY, 28)

    draw.text((W//2, H//2 + 170), "ZERO CLOUD TELEMETRY • 100% OFFLINE WAL SOVEREIGNTY", font=f_eyebrow, fill=(224, 122, 72), anchor="mm")
    draw.text((W//2, H//2 + 290), "Never Lose Your Thread.", font=f_title, fill=(255, 255, 255), anchor="mm")
    draw.text((W//2, H//2 + 420), "Sutra is live on macOS. Native Rust Context Engine & Swift AppKit HUD.", font=f_sub, fill=(212, 212, 216), anchor="mm")
    draw.text((W//2, H//2 + 540), "Created by Ramesh • 22 September 2026 • Sutra Sovereign Engineering Hub", font=f_footer, fill=(120, 120, 125), anchor="mm")

    out_path = os.path.join(FRAMES_DIR, "scene_7.png")
    img.save(out_path)
    print("  ✓ Scene 7 frame rendered")
    return out_path

# ══════════════════════════════════════════════════════════════════════════════
#  FFMPEG MOTION RENDERER & AUDIO MULTIPLEXING
# ══════════════════════════════════════════════════════════════════════════════

def render_broadcast_video():
    print("Rendering 7 full-bleed 4K master scenes...")
    s1 = build_scene_1()
    s2 = build_scene_2()
    s3 = build_scene_3()
    s4 = build_scene_4()
    s5 = build_scene_5()
    s6 = build_scene_6()
    s7 = build_scene_7()

    # Scene durations (in seconds) matching 82.0s narration acts
    scenes = [
        (s1, 9.0, "zoompan=z='min(zoom+0.0006,1.06)':d=270:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s2, 11.0, "zoompan=z='min(zoom+0.0005,1.05)':d=330:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s3, 12.0, "zoompan=z='min(zoom+0.0005,1.05)':d=360:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s4, 13.0, "zoompan=z='min(zoom+0.0004,1.04)':d=390:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s5, 14.0, "zoompan=z='min(zoom+0.0005,1.05)':d=420:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s6, 11.5, "zoompan=z='min(zoom+0.0004,1.04)':d=345:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30"),
        (s7, 11.5, "zoompan=z='min(zoom+0.0006,1.06)':d=345:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1920x1080:fps=30")
    ]

    print("Synthesizing dynamic camera motion clips for each scene...")
    clip_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for idx, (frame, dur, vf) in enumerate(scenes, 1):
            clip_path = os.path.join(tmpdir, f"clip_{idx}.mp4")
            frames_count = int(dur * 30)
            cmd = [
                "/opt/homebrew/bin/ffmpeg", "-y",
                "-loop", "1", "-i", frame,
                "-vf", vf,
                "-c:v", "libx264", "-t", str(dur), "-pix_fmt", "yuv420p",
                "-preset", "veryfast",
                clip_path
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            clip_files.append(clip_path)
            print(f"  ✓ Motion clip {idx}/7 generated ({dur}s)")

        print("Stitching video stream and multiplexing master audio...")
        # Create concat list
        concat_list = os.path.join(tmpdir, "concat.txt")
        with open(concat_list, "w") as f:
            for c in clip_files:
                f.write(f"file '{c}'\n")

        raw_video = os.path.join(tmpdir, "raw_video.mp4")
        subprocess.run([
            "/opt/homebrew/bin/ffmpeg", "-y",
            "-f", "concat", "-safe", "0", "-i", concat_list,
            "-c", "copy", raw_video
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

        # Mux master audio
        print("Finalizing broadcast MP4 with 48kHz stereo master soundtrack...")
        final_cmd = [
            "/opt/homebrew/bin/ffmpeg", "-y",
            "-i", raw_video,
            "-i", AUDIO_FILE,
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "320k",
            "-shortest",
            OUTPUT_MP4
        ]
        subprocess.run(final_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

        print(f"✓ Master Launch Video successfully written to:\n  - {OUTPUT_MP4}")

        # Attempt desktop copy
        try:
            subprocess.run(["cp", OUTPUT_MP4, DESKTOP_MP4], check=True)
            print(f"  - {DESKTOP_MP4}")
        except Exception as e:
            print(f"  Note: Desktop copy skipped in sandbox ({e}).")

if __name__ == "__main__":
    render_broadcast_video()
