using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace SutraWindows
{
    public sealed partial class QuickCueWindow : Window
    {
        private long _scheduledDueAt = 0;

        public QuickCueWindow()
        {
            this.InitializeComponent();
            this.SystemBackdrop = new DesktopAcrylicBackdrop();
        }

        private void OnScheduleTodayClick(object sender, RoutedEventArgs e)
        {
            var today = DateTime.Today;
            _scheduledDueAt = new DateTimeOffset(today).ToUnixTimeMilliseconds();
            ScheduleBtn.Content = "Today";
        }

        private void OnSchedulePickDateClick(object sender, RoutedEventArgs e)
        {
            // Set tomorrow as placeholder for date picker
            var tomorrow = DateTime.Today.AddDays(1);
            _scheduledDueAt = new DateTimeOffset(tomorrow).ToUnixTimeMilliseconds();
            ScheduleBtn.Content = tomorrow.ToString("MMM d");
        }

        private void OnScheduleClearClick(object sender, RoutedEventArgs e)
        {
            _scheduledDueAt = 0;
            ScheduleBtn.Content = "Schedule";
        }

        private void OnInputKeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                CommitThread();
            }
            else if (e.Key == Windows.System.VirtualKey.Escape)
            {
                this.Hide();
            }
        }

        private void OnCommitClick(object sender, RoutedEventArgs e)
        {
            CommitThread();
        }

        private void CommitThread()
        {
            var title = TitleInput.Text?.Trim();
            if (string.IsNullOrEmpty(title)) return;

            var notes = NotesInput.Text?.Trim();

            App.Bridge.Capture(
                title: title,
                notes: notes,
                cueType: "note",
                appName: "Windows",
                url: null,
                filePath: null,
                lineNumber: 0,
                dueAt: _scheduledDueAt
            );

            // Reset inputs & dismiss
            TitleInput.Text = "";
            NotesInput.Text = "";
            _scheduledDueAt = 0;
            ScheduleBtn.Content = "Schedule";
            this.Hide();
        }

        public void Hide()
        {
            // WinUI 3 Window visibility management
            this.AppWindow.Hide();
        }
    }
}
