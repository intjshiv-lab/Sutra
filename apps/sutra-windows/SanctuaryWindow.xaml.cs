using System;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SutraWindows
{
    public sealed partial class SanctuaryWindow : Window
    {
        private bool _isTodayExpanded = false;

        public SanctuaryWindow()
        {
            this.InitializeComponent();
            RefreshThreads();
        }

        public void RefreshThreads()
        {
            var json = App.Bridge.List("waiting");
            // Parse JSON and populate UI
            using var doc = JsonDocument.Parse(json);
            var count = doc.RootElement.GetArrayLength();
            CountBadge.Text = $"● {count} Waiting";
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
