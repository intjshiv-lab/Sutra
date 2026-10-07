// Steve Jobs Craft - Monochrome Vector Glyphs (Zero Emojis)
const GLYPHS = {
  note: `<svg class="glyph-icon" viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>`,
  checklist: `<svg class="glyph-icon" viewBox="0 0 24 24"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`,
  link: `<svg class="glyph-icon" viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>`,
  file: `<svg class="glyph-icon" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`,
  voice: `<svg class="glyph-icon" viewBox="0 0 24 24"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/></svg>`
};

let allThreads = [];
let currentFilter = "all";
let searchQuery = "";

const invoke = window.__TAURI__?.core?.invoke || async function(cmd, args) {
  console.log(`[Mock IPC] ${cmd}:`, args);
  if (cmd === "list_threads") {
    return [
      { id: "1", title: "Review Q3 Architecture & Memory Benchmarks", cue_type: "note", notes: "Focus on zero-copy allocations and hotkey latency.", status: "waiting", anchor: { app_name: "Obsidian" } },
      { id: "2", title: "Fix cross-platform window transparency on Linux", cue_type: "checklist", notes: "[x] macOS\n[ ] Wayland\n[ ] Windows 11", status: "waiting", anchor: { app_name: "Code" } },
      { id: "3", title: "UniFFI Swift Binding Verification", cue_type: "link", notes: "Check release build symbols", status: "waiting", anchor: { app_name: "Terminal" } }
    ];
  }
  return {};
};

async function loadThreads() {
  try {
    allThreads = await invoke("list_threads", { status: "waiting" });
    renderThreads();
  } catch (err) {
    console.error("Failed to load threads:", err);
  }
}

function renderThreads() {
  const listEl = document.getElementById("threadList");
  const countEl = document.getElementById("activeCount");
  
  const filtered = allThreads.filter(t => {
    const matchesFilter = currentFilter === "all" || (t.anchor?.app_name && t.anchor.app_name.toLowerCase() === currentFilter.toLowerCase());
    const matchesQuery = !searchQuery || t.title.toLowerCase().includes(searchQuery.toLowerCase()) || (t.notes && t.notes.toLowerCase().includes(searchQuery.toLowerCase()));
    return matchesFilter && matchesQuery;
  });

  countEl.textContent = `${filtered.length} active`;

  if (filtered.length === 0) {
    listEl.innerHTML = `<div style="text-align:center; padding: 40px 20px; color: var(--text-muted); font-size: 12px;">No attention threads. Rest in the sanctuary.</div>`;
    return;
  }

  listEl.innerHTML = filtered.map(t => {
    const cueType = (t.cue_type || "note").toLowerCase();
    const glyph = GLYPHS[cueType] || GLYPHS.note;
    const appBadge = t.anchor?.app_name || "General";
    
    return `
      <div class="thread-card" data-id="${t.id}">
        <div class="thread-header">
          <div class="thread-title-wrap">
            ${glyph}
            <span class="thread-title">${escapeHtml(t.title)}</span>
          </div>
          <span class="thread-badge">${escapeHtml(appBadge)}</span>
        </div>
        ${t.notes ? `<div class="thread-notes">${escapeHtml(t.notes)}</div>` : ""}
        <div class="thread-actions">
          <button class="action-btn" onclick="snoozeThread('${t.id}')">Snooze</button>
          <button class="action-btn" onclick="completeThread('${t.id}')">Done</button>
        </div>
      </div>
    `;
  }).join("");
}

window.completeThread = async function(id) {
  await invoke("complete_thread", { threadId: id });
  allThreads = allThreads.filter(t => t.id !== id);
  renderThreads();
};

window.snoozeThread = async function(id) {
  await invoke("snooze_thread", { threadId: id, hours: 4 });
  allThreads = allThreads.filter(t => t.id !== id);
  renderThreads();
};

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// Search and Filter Listeners
document.getElementById("searchInput").addEventListener("input", (e) => {
  searchQuery = e.target.value.trim();
  renderThreads();
});

document.querySelectorAll(".chip").forEach(chip => {
  chip.addEventListener("click", () => {
    document.querySelectorAll(".chip").forEach(c => c.classList.remove("active"));
    chip.classList.add("active");
    currentFilter = chip.getAttribute("data-app");
    renderThreads();
  });
});

// Vertical Grab Handle Dragging
const dragHandle = document.getElementById("dragHandle");
let isDragging = false;
let startY = 0;
let initialHeight = 460;

dragHandle.addEventListener("mousedown", (e) => {
  isDragging = true;
  startY = e.clientY;
  initialHeight = window.innerHeight;
  document.body.style.cursor = "ns-resize";
});

window.addEventListener("mousemove", (e) => {
  if (!isDragging) return;
  const deltaY = e.clientY - startY;
  const newHeight = Math.max(380, Math.min(800, initialHeight + deltaY));
  
  if (window.__TAURI__?.window?.getCurrentWindow) {
    const win = window.__TAURI__.window.getCurrentWindow();
    win.setSize(new window.__TAURI__.dpi.LogicalSize(460, newHeight));
  }
});

window.addEventListener("mouseup", () => {
  if (isDragging) {
    isDragging = false;
    document.body.style.cursor = "default";
  }
});

// Double-click toggle between 460 and 680
dragHandle.addEventListener("dblclick", () => {
  const targetH = window.innerHeight >= 600 ? 460 : 680;
  if (window.__TAURI__?.window?.getCurrentWindow) {
    const win = window.__TAURI__.window.getCurrentWindow();
    win.setSize(new window.__TAURI__.dpi.LogicalSize(460, targetH));
  }
});

// Initialize on DOM ready
document.addEventListener("DOMContentLoaded", () => {
  initOnboardingGate();
  loadThreads();
});

// Gated First-Run Setup Flow
const ONBOARDING_STEPS = [
  {
    tag: "STEP 1 OF 3",
    title: "System Auto-Start",
    desc: "Allow Sutra to launch automatically on Windows login so your cognitive threads are restored instantly in under 5 milliseconds.",
    statusText: "Windows Startup Registry Integration",
    btnText: "Enable & Continue"
  },
  {
    tag: "STEP 2 OF 3",
    title: "Context Sniffing",
    desc: "Grant focus detection so Sutra can associate open documents, VS Code files, and browser tabs with your attention cues.",
    statusText: "Win32 UI Automation Focus Sniffer",
    btnText: "Grant Focus Sniffing"
  },
  {
    tag: "STEP 3 OF 3",
    title: "Keyboard Mastery",
    desc: "Global hotkeys registered:\n• Alt + Space : Quick Cue HUD\n• Alt + S : Sanctuary\n• Alt + A : Floating Bar",
    statusText: "Low-Level Keystroke Dispatcher Active",
    btnText: "Enter Sanctuary"
  }
];

let currentStep = 0;

function initOnboardingGate() {
  const onboarded = localStorage.getItem("sutra_onboarded_v1");
  if (!onboarded) {
    document.getElementById("onboardingModal").style.display = "flex";
    renderOnboardingStep();
  }
}

function renderOnboardingStep() {
  const step = ONBOARDING_STEPS[currentStep];
  document.getElementById("onboardingStepTag").textContent = step.tag;
  document.getElementById("onboardingTitle").textContent = step.title;
  document.getElementById("onboardingDesc").textContent = step.desc;
  document.getElementById("onboardingActionBox").querySelector("span").textContent = step.statusText;
  document.getElementById("onboardingNextBtn").textContent = step.btnText;
}

document.getElementById("onboardingNextBtn")?.addEventListener("click", () => {
  currentStep++;
  if (currentStep < ONBOARDING_STEPS.length) {
    renderOnboardingStep();
  } else {
    localStorage.setItem("sutra_onboarded_v1", "true");
    const modal = document.getElementById("onboardingModal");
    modal.style.transition = "opacity 0.2s ease";
    modal.style.opacity = "0";
    setTimeout(() => { modal.style.display = "none"; }, 200);
  }
});
