using Android.Webkit;
using Microsoft.Maui.Handlers;
using Microsoft.Maui.Platform;
using Hephaera.GameHost.Services;

namespace Hephaera.GameHost.Platforms.Android;

public sealed class GameHybridWebViewHandler : HybridWebViewHandler
{
    protected override void ConnectHandler(global::Android.Webkit.WebView platformView)
    {
        // The base handler installs its own client and starts the local entry load.
        // Replace it here, rather than in Initialized, so MAUI cannot overwrite it.
        base.ConnectHandler(platformView);
        platformView.SetWebViewClient(new GuardedClient(this));
    }

    private sealed class GuardedClient(HybridWebViewHandler handler) : MauiHybridWebViewClient(handler)
    {
        public override bool ShouldOverrideUrlLoading(global::Android.Webkit.WebView? view, IWebResourceRequest? request)
            => !GameNavigationPolicy.IsLocal(request?.Url?.ToString(), "https");

        [Obsolete("Required for Android's legacy navigation callback.")]
        public override bool ShouldOverrideUrlLoading(global::Android.Webkit.WebView? view, string? url)
            => !GameNavigationPolicy.IsLocal(url, "https");

        public override WebResourceResponse? ShouldInterceptRequest(global::Android.Webkit.WebView? view, IWebResourceRequest? request)
        {
            // Android does not call ShouldOverrideUrlLoading for POST. Deny
            // foreign main-frame requests here regardless of the HTTP method.
            if (request?.IsForMainFrame == true && !GameNavigationPolicy.IsLocal(request.Url?.ToString(), "https"))
            {
                return new WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
                    new Dictionary<string, string> { ["Cache-Control"] = "no-store" },
                    new MemoryStream(Array.Empty<byte>()));
            }
            // Keep MAUI's actual packaged-asset handling and normal subresource
            // loading; this guard does not establish a network sandbox.
            return base.ShouldInterceptRequest(view, request);
        }

        public override void OnPageFinished(global::Android.Webkit.WebView? view, string? url)
        {
            base.OnPageFinished(view, url);
            if (GameNavigationPolicy.IsLocal(url, "https") && view?.Tag is GameWebViewPolicy.LoadedCallback callback)
                callback.Invoke();
        }
    }
}
