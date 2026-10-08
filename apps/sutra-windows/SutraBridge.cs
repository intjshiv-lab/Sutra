using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace SutraWindows
{
    public sealed class SutraBridge : IDisposable
    {
        private const string DllName = "sutra_ffi.dll";

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern IntPtr sutra_db_open(string path);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        private static extern void sutra_db_close(IntPtr handle);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern IntPtr sutra_capture(
            IntPtr handle,
            string title,
            string? notes,
            string cueType,
            string? appName,
            string? url,
            string? filePath,
            int lineNumber,
            long dueAt
        );

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern IntPtr sutra_list(IntPtr handle, string? status);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern IntPtr sutra_search(IntPtr handle, string query);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern int sutra_update_status(IntPtr handle, string id, string newStatus);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern int sutra_snooze(IntPtr handle, string id, long hours);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        private static extern void sutra_free_string(IntPtr ptr);

        private IntPtr _handle;

        public SutraBridge()
        {
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var dbDir = Path.Combine(userProfile, ".sutra");
            Directory.CreateDirectory(dbDir);
            var dbPath = Path.Combine(dbDir, "sutra.db");

            _handle = sutra_db_open(dbPath);
            if (_handle == IntPtr.Zero)
            {
                throw new InvalidOperationException($"Failed to open Sutra SQLite database at {dbPath}");
            }
        }

        public string? Capture(string title, string? notes, string cueType, string? appName, string? url, string? filePath, int lineNumber = 0, long dueAt = 0)
        {
            var ptr = sutra_capture(_handle, title, notes, cueType, appName, url, filePath, lineNumber, dueAt);
            return ReadAndFree(ptr);
        }

        public string List(string? status = null)
        {
            var ptr = sutra_list(_handle, status);
            return ReadAndFree(ptr) ?? "[]";
        }

        public string Search(string query)
        {
            var ptr = sutra_search(_handle, query);
            return ReadAndFree(ptr) ?? "[]";
        }

        public bool UpdateStatus(string id, string newStatus)
        {
            return sutra_update_status(_handle, id, newStatus) == 0;
        }

        public bool Snooze(string id, long hours = 4)
        {
            return sutra_snooze(_handle, id, hours) == 0;
        }

        private static string? ReadAndFree(IntPtr ptr)
        {
            if (ptr == IntPtr.Zero) return null;
            try
            {
                return Marshal.PtrToStringUTF8(ptr);
            }
            finally
            {
                sutra_free_string(ptr);
            }
        }

        public void Dispose()
        {
            if (_handle != IntPtr.Zero)
            {
                sutra_db_close(_handle);
                _handle = IntPtr.Zero;
            }
        }
    }
}
