using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Infrastructure;
var options = new Dictionary<string, string>(StringComparer.Ordinal);
try
{
    if (args.Length == 0 || args.Contains("--help") || args[0] == "help")
    {
        Console.WriteLine("proof-to-model <init|doctor|setup|preprocess|reconstruct|finish|review|record|validate|status|promote> --root ROOT --manifest PATH [options]\ninit: --task ID --asset ID --version ID --proof FILE --rights FILE --recipe FILE --toolchain FILE --actor NAME [--brief JSON] [--proof-metadata JSON] [--library-search JSON] [--reuse-manifest FILE]\nrecord: --kind proof|preprocessing|independent|human|rigging|animation --reviewer NAME --evidence JSON [--artifact STAGED_DERIVATIVE_GLB --source MATCHING_BLEND]\nstatus prints current approvalFingerprints; review receipt JSON requires kind/reviewer/decision=approved/fingerprint/reason; proof and human also require human:true. CLI records explicit assertions, does not authenticate humans.\nsetup is dry-run; --execute additionally requires per-file licenseAccepted and rights evidence.\nfinish/review: [--blender ABSOLUTE_PATH] [--baseline-root TRUSTED_BASELINE] [--timeout SECONDS]\npromote: --destination assets/models/... (requires fresh independent + human evidence)");
        return 0;
    }
    for (int i = 1; i < args.Length; i++)
    {
        if (!args[i].StartsWith("--"))
            throw new InvalidOperationException("Expected option: " + args[i]);
        var key = args[i][2..];
        if (!options.TryAdd(key, i + 1 < args.Length && !args[i + 1].StartsWith("--") ? args[++i] : "true"))
            throw new InvalidOperationException("Duplicate option: " + key);
    }
    var allowed = new HashSet<string>(["root", "manifest", "task", "asset", "version", "actor", "proof", "rights", "recipe", "toolchain", "proof-metadata", "brief", "selection", "library-search", "reuse-manifest", "kind", "reviewer", "evidence", "artifact", "source", "destination", "blender", "baseline-root", "timeout", "gpu", "execute"], StringComparer.Ordinal);
    foreach (var key in options.Keys)
        if (!allowed.Contains(key))
            throw new InvalidOperationException("Unknown option: --" + key);
    var root = options.GetValueOrDefault("root", Directory.GetCurrentDirectory());
    var app = new Pipeline(new Workspace(root), options, new NativeProcess(), new AlphaProcessor());
    using var cancel = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; cancel.Cancel(); };
    await app.Execute(args[0], cancel.Token);
    return 0;
}
catch (Exception e) { Console.Error.WriteLine(e.Message); return 1; }
