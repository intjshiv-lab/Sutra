using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;

namespace SutraWindows
{
    public sealed partial class ActivationWindow : Window
    {
        private readonly Action? _onActivationSuccess;

        public ActivationWindow(Action? onActivationSuccess = null)
        {
            this.InitializeComponent();
            this.SystemBackdrop = new DesktopAcrylicBackdrop();
            _onActivationSuccess = onActivationSuccess;

            // Display hardware device ID
            DeviceIdText.Text = LicenseManager.Shared.GetDeviceID();
        }

        private void OnCopyDeviceClick(object sender, RoutedEventArgs e)
        {
            try
            {
                var package = new DataPackage();
                package.SetText(DeviceIdText.Text);
                Clipboard.SetContent(package);
                CopyButton.Content = "Copied!";
                Task.Delay(2000).ContinueWith(_ =>
                {
                    DispatcherQueue.TryEnqueue(() => CopyButton.Content = "Copy ID");
                });
            }
            catch
            {
                // Clipboard fallback
            }
        }

        private async void OnActivateOnlineClick(object sender, RoutedEventArgs e)
        {
            await RunOnlineActivationAsync();
        }

        private async void OnEmailKeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                await RunOnlineActivationAsync();
            }
        }

        private async Task RunOnlineActivationAsync()
        {
            var email = EmailInput.Text?.Trim();
            if (string.IsNullOrWhiteSpace(email))
            {
                SetStatus("Please enter your registered email address.", isError: true);
                return;
            }

            SetLoading(true);
            SetStatus("Contacting Cloudflare licensing gateway...", isError: false);

            var (success, message) = await LicenseManager.Shared.ActivateOnlineAsync(email);

            SetLoading(false);

            if (success)
            {
                SetStatus("Activation successful! Launching Sutra...", isError: false);
                await Task.Delay(1000);
                CloseAndResume();
            }
            else
            {
                SetStatus(message, isError: true);
            }
        }

        private void OnUnlockOfflineClick(object sender, RoutedEventArgs e)
        {
            RunOfflineUnlock();
        }

        private void OnCodeKeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                RunOfflineUnlock();
            }
        }

        private void RunOfflineUnlock()
        {
            var code = CodeInput.Text?.Trim();
            if (string.IsNullOrWhiteSpace(code))
            {
                SetStatus("Please enter an 8-digit unlock code.", isError: true);
                return;
            }

            if (LicenseManager.Shared.Activate(code))
            {
                SetStatus("Code verified! Launching Sutra...", isError: false);
                Task.Delay(800).ContinueWith(_ =>
                {
                    DispatcherQueue.TryEnqueue(CloseAndResume);
                });
            }
            else
            {
                SetStatus("Invalid unlock code for this hardware device.", isError: true);
            }
        }

        private void SetLoading(bool isLoading)
        {
            ProgressIndicator.IsActive = isLoading;
            ProgressIndicator.Visibility = isLoading ? Visibility.Visible : Visibility.Collapsed;
            ActivateOnlineBtn.IsEnabled = !isLoading;
            UnlockOfflineBtn.IsEnabled = !isLoading;
        }

        private void SetStatus(string message, bool isError)
        {
            StatusLabel.Text = message;
            StatusLabel.Foreground = (SolidColorBrush)Application.Current.Resources[isError ? "SutraAccentBrush" : "SutraTextPrimary"];
        }

        private void CloseAndResume()
        {
            this.Close();
            _onActivationSuccess?.Invoke();
        }
    }
}
