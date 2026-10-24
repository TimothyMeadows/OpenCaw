using Bubo.LocalAgent.Abstractions;

namespace Bubo.LocalAgent.Runtime.Tools;

public sealed class ToolRegistry
{
    private readonly Dictionary<string, IAgentTool> _tools;
    private readonly IReadOnlyList<IAgentTool> _orderedTools;

    public ToolRegistry(IEnumerable<IAgentTool> tools)
    {
        _orderedTools = tools.ToArray();
        _tools = _orderedTools.ToDictionary(tool => tool.Name, StringComparer.OrdinalIgnoreCase);
    }

    public IReadOnlyCollection<string> ToolNames => _tools.Keys;

    public IReadOnlyList<IAgentTool> Tools => _orderedTools;

    public bool TryGet(string name, out IAgentTool tool)
    {
        return _tools.TryGetValue(name, out tool!);
    }

    public static ToolRegistry CreateDefault(
        ISandboxRunner? sandboxRunner = null,
        SandboxOptions? sandboxOptions = null)
    {
        return new ToolRegistry(new IAgentTool[]
        {
            new ReadFileTool(),
            new WriteFileTool(),
            new ListFilesTool(),
            new SearchTextTool(),
            new PatchFileTool(),
            new RunCommandTool(sandboxRunner, sandboxOptions),
            new GitStatusTool(sandboxRunner, sandboxOptions),
            new GitDiffTool(sandboxRunner, sandboxOptions),
            new GitApplyPatchTool(sandboxRunner, sandboxOptions)
        });
    }

    public static ToolRegistry CreateModelSafe(
        ISandboxRunner? sandboxRunner = null,
        SandboxOptions? sandboxOptions = null)
    {
        return new ToolRegistry(new IAgentTool[]
        {
            new ReadFileTool(),
            new WriteFileTool(),
            new ListFilesTool(),
            new SearchTextTool(),
            new PatchFileTool(),
            new GitStatusTool(sandboxRunner, sandboxOptions),
            new GitDiffTool(sandboxRunner, sandboxOptions),
            new GitApplyPatchTool(sandboxRunner, sandboxOptions)
        });
    }
}
