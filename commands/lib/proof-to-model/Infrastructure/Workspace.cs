using OpenCaw.ProofToModel.Application;
namespace OpenCaw.ProofToModel.Infrastructure;

// Public compatibility facade; guarded file mechanics are shared by native asset workflows.
public sealed class Workspace(string root) : OpenCaw.AssetProduction.Workspace(root), IWorkspace;
