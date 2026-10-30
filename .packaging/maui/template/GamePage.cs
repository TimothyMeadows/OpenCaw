using System.Reflection;
using Microsoft.Maui.Controls;
using OpenCaw.GameHost.Services;

namespace OpenCaw.GameHost;

public sealed class GamePage : ContentPage, IDisposable
{
    private readonly HybridWebView _webView;
    private readonly GameLifecycle _lifecycle;
    private IDisposable? _nativePolicy;
    private bool _disposed;

    public GamePage()
    {
        Padding = 0;
        SafeAreaEdges = new Microsoft.Maui.SafeAreaEdges(Microsoft.Maui.SafeAreaRegions.Container);
        BackgroundColor = Colors.Black;
        NavigationPage.SetHasNavigationBar(this, false);
        var entry = typeof(GamePage).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Single(value => value.Key == "OpenCawDefaultFile").Value;
        _webView = new HybridWebView { HybridRoot = "wwwroot", DefaultFile = entry };
        _lifecycle = new GameLifecycle(_webView);
        _webView.WebViewInitializing += WebViewInitializing;
        _webView.WebViewInitialized += WebViewInitialized;
        Content = _webView;
        // No SetInvokeJavaScriptTarget or native command dispatcher is registered.
    }

    private static void WebViewInitializing(object? sender, WebViewInitializingEventArgs args) => GameWebViewPolicy.Configure(args);

    private void WebViewInitialized(object? sender, WebViewInitializedEventArgs args)
    {
        _nativePolicy?.Dispose();
        _nativePolicy = GameWebViewPolicy.Attach(args, _lifecycle.PageLoaded);
    }

    public void SetActive(bool active) => _lifecycle.SetActive(active);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _webView.WebViewInitializing -= WebViewInitializing;
        _webView.WebViewInitialized -= WebViewInitialized;
        _nativePolicy?.Dispose();
        _lifecycle.Dispose();
        _webView.Handler?.DisconnectHandler();
    }
}
