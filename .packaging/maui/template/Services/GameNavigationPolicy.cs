namespace Hephaera.GameHost.Services;

public static class GameNavigationPolicy
{
    public static bool IsLocal(string? address, string expectedScheme)
    {
        return Uri.TryCreate(address, UriKind.Absolute, out var uri)
            && string.Equals(uri.Scheme, expectedScheme, StringComparison.OrdinalIgnoreCase)
            && string.Equals(uri.Host, "0.0.0.1", StringComparison.OrdinalIgnoreCase)
            && uri.IsDefaultPort
            && string.IsNullOrEmpty(uri.UserInfo);
    }
}
