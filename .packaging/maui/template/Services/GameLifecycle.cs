using System.Diagnostics;
using Microsoft.Maui.Controls;

namespace Hephaera.GameHost.Services;

public sealed class GameLifecycle(HybridWebView webView) : IDisposable
{
    private bool _active = true;
    private bool _loaded;
    private bool _disposed;

    public void SetActive(bool active)
    {
        if (_disposed || _active == active) return;
        _active = active;
        Notify();
    }

    public void PageLoaded()
    {
        if (_disposed) return;
        _loaded = true;
        Notify();
    }

    private async void Notify()
    {
        if (!_loaded || _disposed || webView.Handler is null) return;
        try
        {
            // Fixed script and finite wait: no game-provided native invocation.
            var script = _active
                ? "window.dispatchEvent(new CustomEvent('hephaera:lifecycle',{detail:{state:'resume'}}));"
                : "window.dispatchEvent(new CustomEvent('hephaera:lifecycle',{detail:{state:'suspend'}}));";
            await webView.EvaluateJavaScriptAsync(script).WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (Exception)
        {
            Debug.WriteLine("The web game lifecycle event could not be delivered; the game must also handle document visibility changes.");
        }
    }

    public void Dispose() => _disposed = true;
}
