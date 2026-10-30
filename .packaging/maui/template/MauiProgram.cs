using Microsoft.Maui.Controls.Hosting;
using Microsoft.Maui.Hosting;

namespace OpenCaw.GameHost;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder().UseMauiApp<App>();
#if ANDROID
        builder.ConfigureMauiHandlers(handlers => handlers.AddHandler<Microsoft.Maui.Controls.HybridWebView, Platforms.Android.GameHybridWebViewHandler>());
#endif
        return builder.Build();
    }
}
