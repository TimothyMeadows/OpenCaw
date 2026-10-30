using Microsoft.Maui.Controls;
using Microsoft.Maui.Storage;
using Microsoft.Web.WebView2.Core;

namespace OpenCaw.GameHost.Services;

public static class GameWebViewPolicy
{
    public static void Configure(WebViewInitializingEventArgs args)
    {
        if (args.PlatformArgs is not null)
            args.PlatformArgs.UserDataFolder = Path.Combine(FileSystem.AppDataDirectory, "WebView2");
    }

    public static IDisposable Attach(WebViewInitializedEventArgs args, Action loaded)
    {
        var core = args.PlatformArgs?.Sender ?? throw new InvalidOperationException("Missing Windows WebView2 instance.");
        return new Policy(core, loaded);
    }

    private sealed class Policy : IDisposable
    {
        private readonly CoreWebView2 _core;
        private readonly Action _loaded;
        public Policy(CoreWebView2 core, Action loaded)
        {
            _core = core;
            _loaded = loaded;
            _core.Settings.AreDevToolsEnabled = false;
            _core.NavigationStarting += Starting;
            _core.NavigationCompleted += Completed;
            _core.NewWindowRequested += NewWindow;
            _core.DownloadStarting += Download;
            _core.PermissionRequested += Permission;
        }
        private static void Starting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs args) => args.Cancel = !GameNavigationPolicy.IsLocal(args.Uri, "https");
        private void Completed(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args) { if (args.IsSuccess) _loaded(); }
        private static void NewWindow(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs args) => args.Handled = true;
        private static void Download(CoreWebView2 sender, CoreWebView2DownloadStartingEventArgs args) => args.Cancel = true;
        private static void Permission(CoreWebView2 sender, CoreWebView2PermissionRequestedEventArgs args) => args.State = CoreWebView2PermissionState.Deny;
        public void Dispose()
        {
            _core.NavigationStarting -= Starting;
            _core.NavigationCompleted -= Completed;
            _core.NewWindowRequested -= NewWindow;
            _core.DownloadStarting -= Download;
            _core.PermissionRequested -= Permission;
        }
    }
}
