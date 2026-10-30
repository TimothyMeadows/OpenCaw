using Android.Webkit;
using Microsoft.Maui.Controls;

namespace OpenCaw.GameHost.Services;

public static class GameWebViewPolicy
{
    public static void Configure(WebViewInitializingEventArgs args)
    {
        var settings = args.PlatformArgs?.Settings ?? throw new InvalidOperationException("Missing Android web settings.");
        settings.JavaScriptCanOpenWindowsAutomatically = false;
        settings.SetSupportMultipleWindows(false);
        settings.AllowFileAccess = false;
        settings.AllowContentAccess = false;
        settings.MixedContentMode = MixedContentHandling.NeverAllow;
    }

    public static IDisposable Attach(WebViewInitializedEventArgs args, Action loaded)
    {
        var native = args.PlatformArgs?.Sender ?? throw new InvalidOperationException("Missing Android WebView instance.");
        native.Tag = new LoadedCallback(loaded);
        return new Policy(native);
    }

    internal sealed class LoadedCallback(Action action) : Java.Lang.Object
    {
        public void Invoke() => action();
    }

    private sealed class Policy(global::Android.Webkit.WebView native) : IDisposable
    {
        public void Dispose() => native.Tag = null;
    }
}
