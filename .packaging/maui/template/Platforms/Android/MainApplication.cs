using Android.App;
using Android.Runtime;

namespace OpenCaw.GameHost;

[Application]
public sealed class MainApplication(IntPtr handle, JniHandleOwnership ownership) : Microsoft.Maui.MauiApplication(handle, ownership)
{
    protected override Microsoft.Maui.Hosting.MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();
}
