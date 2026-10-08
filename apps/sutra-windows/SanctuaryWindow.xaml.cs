using System;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SutraWindows
{
    public sealed partial class SanctuaryWindow : Window
    {
        private bool _isTodayExpanded = false;

        private string _currentStatus = "waiting";

        public SanctuaryWindow()
        {
            this.InitializeComponent();
            RefreshThreads();
        }

        public void RefreshThreads()
        {
            var json = App.Bridge.List(_currentStatus);
            // Parse JSON and populate UI
            using var doc = JsonDocument.Parse(json);
            var count = doc.RootElement.GetArrayLength();
            CountBadge.Text = $"{count}";
        }

        private void OnArchiveToggleClick(object sender, RoutedEventArgs e)
        {
            _currentStatus = (_currentStatus == "waiting") ? "done" : "waiting";
            ArchiveToggleBtn.Content = (_currentStatus == "done") ? "← Active" : "Archive";
            RefreshThreads();
        }

        private void OnSearchTextChanged(object sender, TextChangedEventArgs e)
        {
            var q = SearchBox.Text?.Trim();
            if (string.IsNullOrEmpty(q))
            {
                RefreshThreads();
            }
            else
            {
                var json = App.Bridge.Search(q);
                // Filter items
            }
        }

        private void OnToggleTodayAccordion(object sender, RoutedEventArgs e)
        {
            _isTodayExpanded = !_isTodayExpanded;
            TodayItemsList.Visibility = _isTodayExpanded ? Visibility.Visible : Visibility.Collapsed;
        }

        private void OnAddCueClick(object sender, RoutedEventArgs e)
        {
            App.ShowQuickCue();
        }
    }
}
