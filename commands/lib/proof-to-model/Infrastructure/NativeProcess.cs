using OpenCaw.ProofToModel.Application;
namespace OpenCaw.ProofToModel.Infrastructure;

// Preserve the proof runtime API while sharing bounded owned-process execution.
public sealed class NativeProcess : OpenCaw.AssetProduction.NativeProcess, INativeProcess;
