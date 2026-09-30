using System;
using Microsoft.UI.Xaml;
using WinRT.Interop;

namespace SutraWindows
{
    public partial class App : Application
    {
        public static SutraBridge Bridge { get; private set; } = null!;
        public static QuickCueWindow? QuickCueWin { get; private set; }
        public static SanctuaryWindow? SanctuaryWin { get; private set; }

        private TrayIconManager? _tray;
        private HotKeyManager? _hotkeys;
        private Window? _hiddenHostWindow;

        public App()
        {
            this.InitializeComponent();
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            Bridge = new SutraBridge();

            // Create windows
            QuickCueWin = new QuickCueWindow();
            SanctuaryWin = new SanctuaryWindow();

            // Set up hidden host window for tray & hotkeys
            _hiddenHostWindow = new Window();
            var hwnd = WindowNative.GetWindowHandle(_hiddenHostWindow);

            _tray = new TrayIconManager(hwnd, IntPtr.Zero, "Sutra (Active)");
            _hotkeys = new HotKeyManager(hwnd);
        }

        public static void ShowQuickCue()
        {
            QuickCueWin?.Activate();
        }

        public static void ShowSanctuary()
        {
            SanctuaryWin?.Activate();
        }
    }
}
