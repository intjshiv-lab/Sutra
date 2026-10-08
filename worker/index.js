/**
 * Sutra Commercial Licensing Gateway & Edge Operator Hub — Cloudflare Worker
 * 100% Serverless, Zero-Dependency Edge Authentication, User Directory & Telemetry
 */

const MASTER_SALT = "SUTRA_SOVEREIGN_2026_MASTER_SECRET_SALT_ARIADNE";

// Compute canonical SHA256 hex digest using Web Crypto API
async function sha256(text) {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

// Compute canonical 8-character activation code: XXXX-YYYY
async function computeActivationCode(deviceId) {
  const cleanId = deviceId.trim().toUpperCase();
  const payload = `${cleanId}:${MASTER_SALT}`;
  const digest = await sha256(payload);
  const raw = digest.slice(0, 8);
  return `${raw.slice(0, 4)}-${raw.slice(4, 8)}`;
}

// Sample in-memory directory store if KV is initializing
const fallbackUsers = new Map([
  ["ramesh@sutra.so", {
    name: "Ramesh Choudhary",
    email: "ramesh@sutra.so",
    deviceId: "SUTRA-DAFF-B792",
    status: "active",
    firstActivatedAt: "2026-10-08T08:00:00Z",
    lastSeenAt: new Date().toISOString(),
    appVersion: "1.0.0",
    maxSeats: 10,
    offlineActivated: false,
    notes: "Platform Owner & Architect"
  }]
]);

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json"
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // 1. Route: Health Check
    if (url.pathname === "/api/health" || url.pathname === "/health") {
      return new Response(JSON.stringify({
        status: "ok",
        service: "Sutra Sovereign Licensing & Operator Engine",
        version: "1.0.0"
      }), { headers: corsHeaders });
    }

    // 2. Route: Client Online Activation
    if (url.pathname === "/api/activate" && request.method === "POST") {
      try {
        const body = await request.json();
        const email = (body.email || "").trim().toLowerCase();
        const deviceId = (body.deviceId || "").trim().toUpperCase();
        const name = (body.name || "").trim() || email.split("@")[0];

        if (!email || !deviceId) {
          return new Response(JSON.stringify({
            status: "error",
            message: "Missing email or deviceId"
          }), { status: 400, headers: corsHeaders });
        }

        let entry = null;
        if (env.SUTRA_LICENSES) {
          entry = await env.SUTRA_LICENSES.get(`USER:${email}`, { type: "json" });
        } else {
          entry = fallbackUsers.get(email);
        }

        // Owner auto-whitelist fallback
        if (!entry && (email === "ramesh" || email === "owner" || email.endsWith("@sutra.so"))) {
          entry = {
            name: "Ramesh Choudhary",
            email: email,
            status: "active",
            maxSeats: 5,
            devices: [deviceId],
            firstActivatedAt: new Date().toISOString(),
            lastSeenAt: new Date().toISOString(),
            appVersion: body.appVersion || "1.0.0"
          };
        }

        if (!entry || entry.status !== "active") {
          return new Response(JSON.stringify({
            status: "pending_approval",
            message: "Email is not currently approved. Please contact Ramesh."
          }), { status: 403, headers: corsHeaders });
        }

        const devices = entry.devices || [];
        const maxSeats = entry.maxSeats || 2;

        if (!devices.includes(deviceId)) {
          if (devices.length >= maxSeats) {
            return new Response(JSON.stringify({
              status: "seat_limit_exceeded",
              message: `Maximum authorized devices (${maxSeats}) reached.`
            }), { status: 403, headers: corsHeaders });
          }
          devices.push(deviceId);
          entry.devices = devices;
        }

        entry.deviceId = deviceId;
        entry.lastSeenAt = new Date().toISOString();
        if (!entry.firstActivatedAt) {
          entry.firstActivatedAt = entry.lastSeenAt;
        }

        if (env.SUTRA_LICENSES) {
          await env.SUTRA_LICENSES.put(`USER:${email}`, JSON.stringify(entry));
        } else {
          fallbackUsers.set(email, entry);
        }

        const code = await computeActivationCode(deviceId);
        return new Response(JSON.stringify({
          status: "active",
          email: email,
          name: entry.name || name,
          deviceId: deviceId,
          code: code,
          message: "Device activated successfully"
        }), { status: 200, headers: corsHeaders });

      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 500,
          headers: corsHeaders
        });
      }
    }

    // 3. Route: Telemetry Heartbeat (Offline-to-Online Registration)
    if (url.pathname === "/api/heartbeat" && request.method === "POST") {
      try {
        const body = await request.json();
        const email = (body.email || "offline-user").trim().toLowerCase();
        const deviceId = (body.deviceId || "").trim().toUpperCase();
        const now = new Date().toISOString();

        if (deviceId) {
          let record = null;
          if (env.SUTRA_LICENSES) {
            record = await env.SUTRA_LICENSES.get(`USER:${email}`, { type: "json" });
          } else {
            record = fallbackUsers.get(email);
          }

          if (!record) {
            record = {
              name: body.name || "Customer",
              email: email,
              deviceId: deviceId,
              status: "active",
              firstActivatedAt: body.firstActivatedAt || now,
              lastSeenAt: now,
              appVersion: body.appVersion || "1.0.0",
              osVersion: body.osVersion || "macOS",
              offlineActivated: Boolean(body.offlineActivated),
              maxSeats: 2,
              devices: [deviceId]
            };
          } else {
            record.lastSeenAt = now;
            record.appVersion = body.appVersion || record.appVersion;
            record.osVersion = body.osVersion || record.osVersion;
            if (deviceId && !(record.devices || []).includes(deviceId)) {
              record.devices = record.devices || [];
              record.devices.push(deviceId);
            }
          }

          if (env.SUTRA_LICENSES) {
            await env.SUTRA_LICENSES.put(`USER:${email}`, JSON.stringify(record));
            await env.SUTRA_LICENSES.put(`DEVICE:${deviceId}`, email);
          } else {
            fallbackUsers.set(email, record);
          }
        }

        return new Response(JSON.stringify({ status: "recorded" }), {
          status: 200,
          headers: corsHeaders
        });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 500,
          headers: corsHeaders
        });
      }
    }

    // 4. Route: Diagnostic Logs Ingestion
    if (url.pathname === "/api/logs" && request.method === "POST") {
      try {
        const body = await request.json();
        const logId = `LOG:${Date.now()}`;
        const logRecord = {
          id: logId,
          email: body.email || "anonymous",
          deviceId: body.deviceId || "unknown",
          appVersion: body.appVersion || "1.0.0",
          osVersion: body.osVersion || "macOS",
          description: body.description || "User submitted diagnostic report",
          logContent: body.logs || "",
          submittedAt: new Date().toISOString()
        };

        if (env.SUTRA_LICENSES) {
          await env.SUTRA_LICENSES.put(logId, JSON.stringify(logRecord));
        }

        return new Response(JSON.stringify({
          status: "submitted",
          logId: logId,
          message: "Diagnostic log received by engineering team."
        }), { status: 200, headers: corsHeaders });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 500,
          headers: corsHeaders
        });
      }
    }

    // 5. Route: Admin Users JSON API
    if (url.pathname === "/api/admin/users" && request.method === "GET") {
      const auth = request.headers.get("Authorization") || url.searchParams.get("token") || "";
      const expected = env.ADMIN_SECRET || "SUTRA_ADMIN_SECRET_2026";

      if (auth !== `Bearer ${expected}` && auth !== expected) {
        return new Response(JSON.stringify({ status: "unauthorized" }), {
          status: 401,
          headers: corsHeaders
        });
      }

      let users = [];
      if (env.SUTRA_LICENSES) {
        const list = await env.SUTRA_LICENSES.list({ prefix: "USER:" });
        for (const key of list.keys) {
          const u = await env.SUTRA_LICENSES.get(key.name, { type: "json" });
          if (u) users.push(u);
        }
      } else {
        users = Array.from(fallbackUsers.values());
      }

      return new Response(JSON.stringify({
        status: "ok",
        totalUsers: users.length,
        users: users
      }), { status: 200, headers: corsHeaders });
    }

    // 6. Route: Admin Whitelist Management
    if (url.pathname === "/api/admin/whitelist" && request.method === "POST") {
      const auth = request.headers.get("Authorization") || "";
      const expected = env.ADMIN_SECRET || "SUTRA_ADMIN_SECRET_2026";

      if (auth !== `Bearer ${expected}`) {
        return new Response(JSON.stringify({ status: "unauthorized" }), {
          status: 401,
          headers: corsHeaders
        });
      }

      try {
        const body = await request.json();
        const email = (body.email || "").trim().toLowerCase();
        const name = (body.name || "").trim() || email.split("@")[0];
        const deviceId = (body.deviceId || "").trim().toUpperCase();
        const maxSeats = body.maxSeats || 2;
        const now = new Date().toISOString();

        if (!email) {
          return new Response(JSON.stringify({ status: "error", message: "Email required" }), {
            status: 400,
            headers: corsHeaders
          });
        }

        const devices = deviceId ? [deviceId] : [];
        const record = {
          name: name,
          email: email,
          status: "active",
          deviceId: deviceId || "Pending Login",
          devices: devices,
          maxSeats: maxSeats,
          firstActivatedAt: deviceId ? now : "Pending",
          lastSeenAt: now,
          appVersion: "1.0.0",
          notes: body.notes || "Whitelisted via Admin"
        };

        if (env.SUTRA_LICENSES) {
          await env.SUTRA_LICENSES.put(`USER:${email}`, JSON.stringify(record));
        } else {
          fallbackUsers.set(email, record);
        }

        let code = "";
        if (deviceId) {
          code = await computeActivationCode(deviceId);
        }

        return new Response(JSON.stringify({
          status: "whitelisted",
          name: name,
          email: email,
          deviceId: deviceId || "pending",
          activationCode: code
        }), { status: 200, headers: corsHeaders });

      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 500,
          headers: corsHeaders
        });
      }
    }

    // 7. Route: /admin Edge Web Dashboard (HTML)
    if (url.pathname === "/admin") {
      return renderAdminDashboard(request, env);
    }

    return new Response(JSON.stringify({ status: "not_found" }), {
      status: 404,
      headers: corsHeaders
    });
  }
};

/**
 * Renders the Edge-Hosted Admin Dashboard in Ramesh Terracotta Design
 */
async function renderAdminDashboard(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") || request.headers.get("x-admin-token") || "";
  const expected = env.ADMIN_SECRET || "SUTRA_ADMIN_SECRET_2026";

  let users = [];
  if (env.SUTRA_LICENSES) {
    const list = await env.SUTRA_LICENSES.list({ prefix: "USER:" });
    for (const k of list.keys) {
      const u = await env.SUTRA_LICENSES.get(k.name, { type: "json" });
      if (u) users.push(u);
    }
  } else {
    users = Array.from(fallbackUsers.values());
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sutra Sovereign Operator Hub</title>
  <style>
    :root {
      --ink: #1d1d1f;
      --ink-soft: #3a3a3c;
      --ink-muted: #6e6e73;
      --ink-faint: #8e8e93;
      --surface: #ffffff;
      --surface-warm: #faf9f7;
      --rule: #d2d0cc;
      --rule-light: #e8e6e1;
      --accent: #b3562a;
      --accent-bg: #fdf5f0;
      --accent-dark: #8c3d1a;
      --code-bg: #292524;
      --code-fg: #e7e5e4;
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif;
      font-size: 11pt; line-height: 1.6; color: var(--ink); background: var(--surface);
      max-width: 1040px; margin: 0 auto; padding: 24px;
    }
    .header {
      display: flex; justify-content: space-between; align-items: center;
      padding-bottom: 20px; border-bottom: 2px solid var(--accent); margin-bottom: 28px;
    }
    .brand h1 { font-family: Georgia, serif; font-size: 22pt; font-weight: 400; color: var(--ink); }
    .brand p { font-size: 9pt; color: var(--ink-muted); text-transform: uppercase; letter-spacing: 1.5px; }
    .auth-badge {
      font-size: 8.5pt; font-weight: 600; padding: 6px 12px; border-radius: 4px;
      background: var(--accent-bg); color: var(--accent); border: 1px solid var(--accent);
    }
    .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 28px; }
    .stat-card {
      background: var(--surface-warm); border: 1px solid var(--rule); border-radius: 6px; padding: 18px;
    }
    .stat-card .label { font-size: 8.5pt; text-transform: uppercase; letter-spacing: 1.2px; color: var(--ink-muted); }
    .stat-card .val { font-family: Georgia, serif; font-size: 24pt; color: var(--accent); margin-top: 4px; }
    .section-title { font-family: Georgia, serif; font-size: 14pt; font-style: italic; color: var(--ink-soft); margin-bottom: 14px; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 30px; font-size: 9.5pt; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--rule-light); text-align: left; }
    th { font-size: 8pt; text-transform: uppercase; letter-spacing: 1px; color: var(--ink-muted); background: var(--surface-warm); border-bottom: 1px solid var(--rule); }
    .badge-active { display: inline-block; padding: 2px 6px; border-radius: 3px; font-size: 7.5pt; font-weight: 600; background: #e6f4ea; color: #137333; }
    .badge-pending { display: inline-block; padding: 2px 6px; border-radius: 3px; font-size: 7.5pt; font-weight: 600; background: #fef7e0; color: #b06000; }
    .action-panel {
      background: var(--surface-warm); border: 1px solid var(--rule); border-radius: 6px; padding: 20px; margin-bottom: 30px;
    }
    .form-row { display: flex; gap: 12px; margin-top: 10px; }
    input, button { padding: 9px 12px; border-radius: 4px; border: 1px solid var(--rule); font-family: inherit; font-size: 9pt; }
    input { flex: 1; outline: none; }
    input:focus { border-color: var(--accent); }
    button { background: var(--accent); color: #fff; font-weight: 600; cursor: pointer; border: 1px solid var(--accent); }
    button:hover { background: var(--accent-dark); }
    .footer { text-align: center; font-size: 8pt; color: var(--ink-faint); margin-top: 40px; padding-top: 16px; border-top: 1px solid var(--rule); }
  </style>
</head>
<body>
  <div class="header">
    <div class="brand">
      <h1>Sutra Sovereign Operator Hub</h1>
      <p>Commercial Customer Directory &amp; Edge Licensing Control</p>
    </div>
    <div class="auth-badge">👑 Administrator: Ramesh</div>
  </div>

  <div class="stats-grid">
    <div class="stat-card">
      <div class="label">Total Customers</div>
      <div class="val">${users.length}</div>
    </div>
    <div class="stat-card">
      <div class="label">Active Devices</div>
      <div class="val">${users.reduce((acc, u) => acc + (u.devices ? u.devices.length : 1), 0)}</div>
    </div>
    <div class="stat-card">
      <div class="label">App Version</div>
      <div class="val">v1.0.0</div>
    </div>
    <div class="stat-card">
      <div class="label">Cloud Gateway</div>
      <div class="val">100% Free</div>
    </div>
  </div>

  <div class="action-panel">
    <div class="section-title">Whitelist a New Customer</div>
    <form id="addForm" onsubmit="handleWhitelist(event)">
      <div class="form-row">
        <input id="userName" placeholder="Full Name (e.g. Arjun Sharma)" required />
        <input id="userEmail" type="email" placeholder="Customer Email" required />
        <input id="userDevice" placeholder="Device ID (Optional, e.g. SUTRA-8B12-44FA)" />
        <button type="submit">+ Whitelist Buyer</button>
      </div>
    </form>
    <div id="resultMsg" style="font-size: 9pt; margin-top: 8px; color: var(--accent); font-weight: 600;"></div>
  </div>

  <div class="section-title">Customer Directory (${users.length} Licensed Accounts)</div>
  <table>
    <thead>
      <tr>
        <th>Customer Name</th>
        <th>Email Address</th>
        <th>Bound Device ID</th>
        <th>First Activated</th>
        <th>Last Seen</th>
        <th>Version</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${users.map(u => `
        <tr>
          <td><strong>${u.name || "Customer"}</strong></td>
          <td><code>${u.email}</code></td>
          <td><code>${u.deviceId || (u.devices && u.devices[0]) || "Pending Login"}</code></td>
          <td>${u.firstActivatedAt ? new Date(u.firstActivatedAt).toLocaleString() : "Pending"}</td>
          <td>${u.lastSeenAt ? new Date(u.lastSeenAt).toLocaleString() : "Never"}</td>
          <td>${u.appVersion || "1.0.0"}</td>
          <td><span class="${u.status === 'active' ? 'badge-active' : 'badge-pending'}">${(u.status || "active").toUpperCase()}</span></td>
        </tr>
      `).join("")}
    </tbody>
  </table>

  <div class="action-panel">
    <div class="section-title">App Update &amp; Maintenance Protocol</div>
    <p style="font-size: 9pt; color: var(--ink-soft); margin-bottom: 6px;">
      <strong>Zero Data Loss Guarantee:</strong> Sutra separates user databases (<code>~/.sutra/sutra.db</code>) from the app bundle (<code>/Applications/Sutra.app</code>).
    </p>
    <p style="font-size: 9pt; color: var(--ink-soft);">
      To update users to future versions, simply publish a new <code>Sutra-Installer.dmg</code>. When they drag the new app to <code>/Applications</code> and click <em>Replace</em>, their entire thread history, tags, and license remain 100% intact!
    </p>
  </div>

  <div class="footer">
    Sutra Sovereign Engineering Hub • Edge Operator Console • Created by Ramesh
  </div>

  <script>
    async function handleWhitelist(e) {
      e.preventDefault();
      const name = document.getElementById('userName').value.trim();
      const email = document.getElementById('userEmail').value.trim();
      const deviceId = document.getElementById('userDevice').value.trim();
      const resEl = document.getElementById('resultMsg');

      resEl.textContent = 'Contacting Cloudflare edge...';

      try {
        const res = await fetch('/api/admin/whitelist', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${expected}'
          },
          body: JSON.stringify({ name, email, deviceId, maxSeats: 2 })
        });
        const data = await res.json();
        if (data.status === 'whitelisted') {
          resEl.textContent = '✓ Successfully whitelisted ' + email + (data.activationCode ? ' • Offline Code: ' + data.activationCode : '');
          setTimeout(() => location.reload(), 1500);
        } else {
          resEl.textContent = 'Error: ' + (data.message || 'Failed to whitelist');
        }
      } catch (err) {
        resEl.textContent = 'Network error: ' + err.message;
      }
    }
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" }
  });
}
