namespace Bubo.LocalAgent.Abstractions;

public interface IAgentTool
{
    string Name { get; }

    string Description { get; }

    Task<ToolResult> InvokeAsync(ToolRequest request, CancellationToken cancellationToken);
}
