using System;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace SutraWindows
{
    /// <summary>
    /// Sovereign Hardware-Bound Licensing & Activation Engine for SutraWindows.
    /// Provides 100% cryptographic and telemetry parity with SutraMac.
    /// </summary>
    public sealed class LicenseManager
    {
        private static readonly Lazy<LicenseManager> _instance = new(() => new LicenseManager());
        public static LicenseManager Shared => _instance.Value;

        // Canonical master salt used for HMAC-SHA256 device key generation across macOS and Windows
        public const string MasterSalt = "SUTRA_SOVEREIGN_2026_MASTER_SECRET_SALT_ARIADNE";
        public const string DefaultEndpoint = "https://sutra-licensing.workers.dev";

        private static readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(8) };

        public static string LicenseDirectory =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sutra");

        public static string LicensePath =>
            Path.Combine(LicenseDirectory, ".license");

        public static string LicenseMetaPath =>
            Path.Combine(LicenseDirectory, ".license_meta");

        public LicenseManager() { }

        /// <summary>
        /// Extracts Windows Machine GUID via native registry (HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid)
        /// Guaranteed unique per Windows OS installation, non-elevated read access.
        /// </summary>
        public string GetHardwareUUID()
        {
            try
            {
                var val = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography", "MachineGuid", null);
                if (val is string guid && !string.IsNullOrWhiteSpace(guid))
                {
                    return guid.Trim().ToUpperInvariant();
                }
            }
            catch
            {
                // Fallback handled below
            }

            // Fallback for non-standard environments
            return ("WIN-" + Environment.MachineName + "-" + Environment.UserName).ToUpperInvariant();
        }

        /// <summary>
        /// Computes user-facing readable Device ID (e.g., SUTRA-D4F1-8B2A)
        /// Identical SHA-256 algorithm to macOS
        /// </summary>
        public string GetDeviceID()
        {
            var rawUUID = GetHardwareUUID();
            var digest = ComputeSha256("DEVICE:" + rawUUID);
            var prefix = digest.Length >= 8 ? digest[..8].ToUpperInvariant() : digest.ToUpperInvariant();
            var p1 = prefix[..4];
            var p2 = prefix.Substring(4, 4);
            return $"SUTRA-{p1}-{p2}";
        }

        /// <summary>
        /// Generates canonical 8-character activation code for a given device ID
        /// </summary>
        public static string ComputeActivationCode(string deviceId)
        {
            var cleanId = deviceId.Trim().ToUpperInvariant();
            var payload = $"{cleanId}:{MasterSalt}";
            var digest = ComputeSha256(payload);
            var prefix = digest.Length >= 8 ? digest[..8].ToUpperInvariant() : digest.ToUpperInvariant();
            var c1 = prefix[..4];
            var c2 = prefix.Substring(4, 4);
            return $"{c1}-{c2}";
        }

        /// <summary>
        /// Verifies whether the provided code is valid for this specific machine
        /// </summary>
        public bool Verify(string code)
        {
            if (string.IsNullOrWhiteSpace(code)) return false;
            var cleanInput = code.Replace("-", "").Replace(" ", "").Trim().ToUpperInvariant();
            var expected = ComputeActivationCode(GetDeviceID()).Replace("-", "");
            return string.Equals(cleanInput, expected, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Checks if this Windows machine is currently activated
        /// </summary>
        public bool IsActivated()
        {
            try
            {
                if (!File.Exists(LicensePath)) return false;
                var savedCode = File.ReadAllText(LicensePath, Encoding.UTF8).Trim();
                return Verify(savedCode);
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Activates and persists the license code to disk (%USERPROFILE%\.sutra\.license)
        /// </summary>
        public bool Activate(string code)
        {
            if (Verify(code))
            {
                try
                {
                    Directory.CreateDirectory(LicenseDirectory);
                    var formatted = code.Trim().ToUpperInvariant();
                    File.WriteAllText(LicensePath, formatted, Encoding.UTF8);
                    return true;
                }
                catch
                {
                    return false;
                }
            }
            return false;
        }

        /// <summary>
        /// Online activation via Cloudflare Worker Licensing Gateway
        /// </summary>
        public async Task<(bool success, string message)> ActivateOnlineAsync(string email, string endpoint = DefaultEndpoint)
        {
            try
            {
                var cleanEmail = email.Trim().ToLowerInvariant();
                var deviceId = GetDeviceID();

                var payload = new
                {
                    email = cleanEmail,
                    deviceId = deviceId,
                    systemInfo = $"Windows ({Environment.OSVersion.VersionString})",
                    appVersion = "1.0.0"
                };

                var jsonStr = JsonSerializer.Serialize(payload);
                using var content = new StringContent(jsonStr, Encoding.UTF8, "application/json");

                var response = await _httpClient.PostAsync($"{endpoint}/api/activate", content);
                var respBytes = await response.Content.ReadAsByteArrayAsync();
                using var doc = JsonDocument.Parse(respBytes);
                var root = doc.RootElement;

                if (root.TryGetProperty("status", out var statusProp) && statusProp.GetString() == "active")
                {
                    if (root.TryGetProperty("code", out var codeProp))
                    {
                        var code = codeProp.GetString() ?? "";
                        if (Activate(code))
                        {
                            return (true, "Device activated successfully");
                        }
                    }
                }

                var msg = root.TryGetProperty("message", out var msgProp)
                    ? msgProp.GetString()
                    : "Account not whitelisted. Contact Ramesh for access.";

                return (false, msg ?? "Account not whitelisted");
            }
            catch (Exception ex)
            {
                return (false, $"Network error: {ex.Message}");
            }
        }

        /// <summary>
        /// Sends an idempotent background telemetry heartbeat once connected to the internet
        /// Rate-limited to once every 6 hours
        /// </summary>
        public async Task SendHeartbeatIfNeededAsync(string endpoint = DefaultEndpoint)
        {
            try
            {
                var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

                if (File.Exists(LicenseMetaPath))
                {
                    var text = File.ReadAllText(LicenseMetaPath).Trim();
                    if (long.TryParse(text, out var lastPing) && (now - lastPing) < 21600)
                    {
                        return; // Rate limit 6 hours
                    }
                }

                var payload = new
                {
                    deviceId = GetDeviceID(),
                    email = Environment.UserName,
                    appVersion = "1.0.0",
                    osVersion = Environment.OSVersion.VersionString,
                    offlineActivated = false
                };

                var jsonStr = JsonSerializer.Serialize(payload);
                using var content = new StringContent(jsonStr, Encoding.UTF8, "application/json");

                var resp = await _httpClient.PostAsync($"{endpoint}/api/heartbeat", content);
                if (resp.IsSuccessStatusCode)
                {
                    Directory.CreateDirectory(LicenseDirectory);
                    File.WriteAllText(LicenseMetaPath, now.ToString(), Encoding.UTF8);
                }
            }
            catch
            {
                // Silent fail for offline/transient conditions
            }
        }

        private static string ComputeSha256(string raw)
        {
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(raw));
            var sb = new StringBuilder(bytes.Length * 2);
            foreach (var b in bytes)
            {
                sb.Append(b.ToString("x2"));
            }
            return sb.ToString();
        }
    }
}
