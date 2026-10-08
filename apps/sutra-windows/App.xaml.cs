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
        public static ActivationWindow? ActivationWin { get; private set; }

        private TrayIconManager? _tray;
        private HotKeyManager? _hotkeys;
        private Window? _hiddenHostWindow;

        public App()
        {
            this.InitializeComponent();
        }

        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern IntPtr LoadImage(IntPtr hinst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            // Hardware-Bound Licensing Gate
            if (!LicenseManager.Shared.IsActivated())
            {
                ActivationWin = new ActivationWindow(onActivationSuccess: () =>
                {
                    StartApplicationServices();
                });
                ActivationWin.Activate();
                return;
            }

            StartApplicationServices();
        }

        private void StartApplicationServices()
        {
            Bridge = new SutraBridge();

            // Create windows
            QuickCueWin = new QuickCueWindow();
            SanctuaryWin = new SanctuaryWindow();

            // Set up hidden host window for tray & hotkeys
            _hiddenHostWindow = new Window();
            var hwnd = WindowNative.GetWindowHandle(_hiddenHostWindow);

            // Load Sutra icon for tray
            var icoPath = System.IO.Path.Combine(AppContext.BaseDirectory, "app.ico");
            IntPtr hIcon = IntPtr.Zero;
            if (System.IO.File.Exists(icoPath))
            {
                hIcon = LoadImage(IntPtr.Zero, icoPath, 1 /* IMAGE_ICON */, 16, 16, 0x00000010 /* LR_LOADFROMFILE */);
            }

            _tray = new TrayIconManager(hwnd, hIcon, "Sutra (Active)");
            _hotkeys = new HotKeyManager(hwnd);

            // Dispatch idempotent background telemetry heartbeat
            _ = LicenseManager.Shared.SendHeartbeatIfNeededAsync();
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
