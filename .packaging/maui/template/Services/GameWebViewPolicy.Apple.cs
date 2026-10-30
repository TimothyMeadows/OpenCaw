#if IOS || MACCATALYST
using Foundation;
using Microsoft.Maui.Controls;
using WebKit;

namespace OpenCaw.GameHost.Services;

public static class GameWebViewPolicy
{
    public static void Configure(WebViewInitializingEventArgs args)
    {
        var config = args.PlatformArgs?.Configuration ?? throw new InvalidOperationException("Missing Apple WebView configuration.");
        config.Preferences.JavaScriptCanOpenWindowsAutomatically = false;
        config.AllowsInlineMediaPlayback = true;
        // Keep the system's media user-action behavior; game audio must still
        // handle AudioContext unlock and resumption on its actual target.
        config.MediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.All;
    }

    public static IDisposable Attach(WebViewInitializedEventArgs args, Action loaded)
    {
        var native = args.PlatformArgs?.Sender ?? throw new InvalidOperationException("Missing Apple WKWebView instance.");
        return new Policy(native, loaded);
    }

    private sealed class Policy : IDisposable
    {
        private readonly WKWebView _view;
        private readonly Navigation _navigation;
        private readonly Ui _ui;
        public Policy(WKWebView view, Action loaded)
        {
            _view = view;
            _navigation = new Navigation(loaded);
            _ui = new Ui();
            _view.NavigationDelegate = _navigation;
            _view.UIDelegate = _ui;
            _view.ScrollView.ScrollEnabled = false;
            _view.ScrollView.Bounces = false;
        }
        public void Dispose()
        {
            _view.NavigationDelegate = null;
            _view.UIDelegate = null;
            _navigation.Dispose();
            _ui.Dispose();
        }
    }

    private sealed class Navigation(Action loaded) : WKNavigationDelegate
    {
        public override void DecidePolicy(WKWebView webView, WKNavigationAction action, Action<WKNavigationActionPolicy> decisionHandler)
        {
            var allowed = action.TargetFrame is not null && GameNavigationPolicy.IsLocal(action.Request.Url?.AbsoluteString, "app");
            decisionHandler(allowed ? WKNavigationActionPolicy.Allow : WKNavigationActionPolicy.Cancel);
        }
        public override void DidFinishNavigation(WKWebView webView, WKNavigation? navigation)
        {
            if (GameNavigationPolicy.IsLocal(webView.Url?.AbsoluteString, "app")) loaded();
        }
    }

    private sealed class Ui : WKUIDelegate
    {
        public override WKWebView? CreateWebView(WKWebView webView, WKWebViewConfiguration configuration, WKNavigationAction action, WKWindowFeatures features) => null;
    }
}
#endif
