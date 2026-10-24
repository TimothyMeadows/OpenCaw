using Bubo.LocalAgent.Runtime;

namespace Bubo.LocalAgent.Runtime.Tests;

public sealed class WorkspaceGuardTests
{
    [Fact]
    public void ResolveInsideWorkspaceAcceptsRelativeChildPath()
    {
        var workspace = CreateWorkspace();
        var guard = new WorkspaceGuard(workspace);

        var resolved = guard.ResolveInsideWorkspace("src/example.txt");

        Assert.StartsWith(workspace, resolved, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ResolveInsideWorkspaceRejectsTraversalOutsideWorkspace()
    {
        var workspace = CreateWorkspace();
        var guard = new WorkspaceGuard(workspace);

        Assert.Throws<UnauthorizedAccessException>(
            () => guard.ResolveInsideWorkspace(Path.Combine("..", "outside.txt")));
    }

    [Fact]
    public void ResolveInsideWorkspaceRejectsGitMetadata()
    {
        var workspace = CreateWorkspace();
        var guard = new WorkspaceGuard(workspace);

        Assert.Throws<UnauthorizedAccessException>(
            () => guard.ResolveInsideWorkspace(Path.Combine(".git", "config")));
    }

    [Fact]
    public void ResolveExistingFileInsideWorkspaceRejectsSymlinkLeaf()
    {
        var workspace = CreateWorkspace();
        var target = Path.Combine(workspace, "target.txt");
        var link = Path.Combine(workspace, "link.txt");
        File.WriteAllText(target, "secret");

        try
        {
            File.CreateSymbolicLink(link, target);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            return;
        }

        var guard = new WorkspaceGuard(workspace);

        Assert.Throws<UnauthorizedAccessException>(
            () => guard.ResolveExistingFileInsideWorkspace("link.txt"));
    }

    [Fact]
    public void ResolveWritableFileInsideWorkspaceRejectsSymlinkParent()
    {
        var workspace = CreateWorkspace();
        var realDirectory = Directory.CreateDirectory(Path.Combine(workspace, "real"));
        var linkDirectory = Path.Combine(workspace, "link-dir");

        try
        {
            Directory.CreateSymbolicLink(linkDirectory, realDirectory.FullName);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            return;
        }

        var guard = new WorkspaceGuard(workspace);

        Assert.Throws<UnauthorizedAccessException>(
            () => guard.ResolveWritableFileInsideWorkspace(Path.Combine("link-dir", "file.txt")));
    }

    [Fact]
    public void ResolveSandboxWorkingDirectoryRejectsSubdirectory()
    {
        var workspace = CreateWorkspace();
        Directory.CreateDirectory(Path.Combine(workspace, "src"));
        var guard = new WorkspaceGuard(workspace);

        Assert.Throws<UnauthorizedAccessException>(
            () => guard.ResolveSandboxWorkingDirectoryInsideWorkspace("src"));
    }

    private static string CreateWorkspace()
    {
        var workspace = Path.Combine(
            Path.GetTempPath(),
            "bubo-tests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workspace);
        return Path.GetFullPath(workspace);
    }
}
