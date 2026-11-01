using Android.App;
using Android.Content.PM;

namespace Hephaera.GameHost;

[Activity(Theme = "@style/Maui.SplashTheme", MainLauncher = true, Exported = true,
    ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode |
        ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density)]
public sealed class MainActivity : Microsoft.Maui.MauiAppCompatActivity
{
}
