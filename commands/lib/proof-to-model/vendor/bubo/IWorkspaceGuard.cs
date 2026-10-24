namespace Bubo.LocalAgent.Abstractions;

public interface IWorkspaceGuard
{
    string WorkspaceRoot { get; }

    string ResolveInsideWorkspace(string path);

    bool IsInsideWorkspace(string path);
}
