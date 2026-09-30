using System;
using System.Runtime.InteropServices;

namespace SutraWindows
{
    public sealed class HotKeyManager : IDisposable
    {
        public const int WM_HOTKEY = 0x0312;

        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;
        public const uint MOD_WIN = 0x0008;
        public const uint MOD_NOREPEAT = 0x4000;

        public const uint VK_SPACE = 0x20;
        public const uint VK_S = 0x53;
        public const uint VK_W = 0x57;

        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private IntPtr _hwnd;

        public const int HOTKEY_QUICK_CUE = 9001; // Ctrl+Alt+Space
        public const int HOTKEY_SANCTUARY = 9002; // Ctrl+Alt+S
        public const int HOTKEY_WAKE_BAR  = 9003; // Ctrl+Alt+W

        public HotKeyManager(IntPtr hwnd)
        {
            _hwnd = hwnd;
            // ⌃⌥Space -> Quick Cue HUD
            RegisterHotKey(_hwnd, HOTKEY_QUICK_CUE, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_SPACE);
            // ⌃⌥S -> Sanctuary Popover
            RegisterHotKey(_hwnd, HOTKEY_SANCTUARY, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_S);
            // ⌃⌥W -> Floating Wake Bar
            RegisterHotKey(_hwnd, HOTKEY_WAKE_BAR,  MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_W);
        }

        public void Dispose()
        {
            UnregisterHotKey(_hwnd, HOTKEY_QUICK_CUE);
            UnregisterHotKey(_hwnd, HOTKEY_SANCTUARY);
            UnregisterHotKey(_hwnd, HOTKEY_WAKE_BAR);
        }
    }
}
