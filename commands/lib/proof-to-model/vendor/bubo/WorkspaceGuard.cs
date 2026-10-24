using Bubo.LocalAgent.Abstractions;

namespace Bubo.LocalAgent.Runtime;

public sealed class WorkspaceGuard : IWorkspaceGuard
{
    private static readonly char[] DirectorySeparators =
    {
        Path.DirectorySeparatorChar,
        Path.AltDirectorySeparatorChar
    };

    private readonly string _workspaceRootWithSeparator;
    private readonly StringComparison _pathComparison;

    public WorkspaceGuard(string workspaceRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(workspaceRoot);

        WorkspaceRoot = Path.GetFullPath(workspaceRoot);
        _workspaceRootWithSeparator = EnsureTrailingSeparator(WorkspaceRoot);
        _pathComparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
    }

    public string WorkspaceRoot { get; }

    public string ResolveInsideWorkspace(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var fullPath = Path.GetFullPath(Path.IsPathRooted(path)
            ? path
            : Path.Combine(WorkspaceRoot, path));

        if (!IsInsideWorkspace(fullPath))
        {
            throw new UnauthorizedAccessException(
                $"Path resolves outside the workspace: {path}");
        }

        RejectReservedPath(fullPath, path);
        return fullPath;
    }

    public string ResolveExistingFileInsideWorkspace(string path)
    {
        var fullPath = ResolveInsideWorkspace(path);
        RejectReparsePointSegments(fullPath, includeTarget: true);
        return fullPath;
    }

    public string ResolveExistingDirectoryInsideWorkspace(string path)
    {
        var fullPath = ResolveInsideWorkspace(path);
        RejectReparsePointSegments(fullPath, includeTarget: true);
        return fullPath;
    }

    public string ResolveSandboxWorkingDirectoryInsideWorkspace(string path)
    {
        var fullPath = ResolveExistingDirectoryInsideWorkspace(path);
        if (!string.Equals(fullPath, WorkspaceRoot, _pathComparison))
        {
            throw new UnauthorizedAccessException(
                $"Sandbox command working directory must be the workspace root: {path}");
        }

        return fullPath;
    }

    public string ResolveWritableFileInsideWorkspace(string path)
    {
        var fullPath = ResolveInsideWorkspace(path);
        RejectReparsePointSegments(Path.GetDirectoryName(fullPath) ?? WorkspaceRoot, includeTarget: true);
        if (File.Exists(fullPath) || Directory.Exists(fullPath))
        {
            RejectReparsePointSegments(fullPath, includeTarget: true);
        }

        return fullPath;
    }

    public bool IsInsideWorkspace(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var fullPath = Path.GetFullPath(Path.IsPathRooted(path)
            ? path
            : Path.Combine(WorkspaceRoot, path));

        return string.Equals(fullPath, WorkspaceRoot, _pathComparison) ||
               fullPath.StartsWith(_workspaceRootWithSeparator, _pathComparison);
    }

    private void RejectReservedPath(string fullPath, string originalPath)
    {
        var relativePath = Path.GetRelativePath(WorkspaceRoot, fullPath);
        if (relativePath == ".")
        {
            return;
        }

        var firstSegment = relativePath.Split(DirectorySeparators, StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault();
        if (string.Equals(firstSegment, ".git", _pathComparison))
        {
            throw new UnauthorizedAccessException(
                $"Path targets reserved Git metadata inside the workspace: {originalPath}");
        }
    }

    private void RejectReparsePointSegments(string fullPath, bool includeTarget)
    {
        var relativePath = Path.GetRelativePath(WorkspaceRoot, fullPath);
        if (relativePath == ".")
        {
            RejectIfReparsePoint(WorkspaceRoot);
            return;
        }

        var current = WorkspaceRoot;
        var segments = relativePath.Split(DirectorySeparators, StringSplitOptions.RemoveEmptyEntries);
        for (var index = 0; index < segments.Length; index++)
        {
            var isTarget = index == segments.Length - 1;
            if (isTarget && !includeTarget)
            {
                return;
            }

            current = Path.Combine(current, segments[index]);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                return;
            }

            RejectIfReparsePoint(current);
        }
    }

    private static void RejectIfReparsePoint(string path)
    {
        var attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new UnauthorizedAccessException(
                $"Path contains a symlink or reparse point inside the workspace: {path}");
        }
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return path.EndsWith(Path.DirectorySeparatorChar) ||
               path.EndsWith(Path.AltDirectorySeparatorChar)
            ? path
            : path + Path.DirectorySeparatorChar;
    }
}
