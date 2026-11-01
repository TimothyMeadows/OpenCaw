using Microsoft.Maui.Controls;
using Microsoft.Maui.ApplicationModel;
using Microsoft.Maui.Storage;

namespace Hephaera.GameHost;

public sealed class App : Application
{
    public App()
    {
#if WINDOWS
        // Packaged applications cannot write beside their executable.
        Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", Path.Combine(FileSystem.AppDataDirectory, "WebView2"));
#endif
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        var page = new GamePage();
        var window = new Window(page) { Title = AppInfo.Current.Name };
        window.Activated += (_, _) => page.SetActive(true);
        window.Resumed += (_, _) => page.SetActive(true);
        window.Deactivated += (_, _) => page.SetActive(false);
        window.Stopped += (_, _) => page.SetActive(false);
        window.Destroying += (_, _) => page.Dispose();
        return window;
    }
}
