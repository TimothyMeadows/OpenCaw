using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Application;
using OpenCaw.ModelAnimation.Infrastructure;
using OpenCaw.ModelAnimation.Domain;
try
{
    if (args.Length == 0 || args.Contains("--help") || args[0] == "help")
    {
        Console.WriteLine("model-to-animation <init|doctor|inspect|prepare|rig|author|retarget|bake|export|review|record|validate|status|promote> --root ROOT --baseline-root BASELINE [options]\ninit: --task ID --asset ID --version ID --actor NAME --model GLB --rights JSON --recipe JSON --blender ABSOLUTE_EXE [--editable-source BLEND] [--source-metadata JSON]\nOther commands: --manifest TASK_LOCAL_MANIFEST\nauthor: [--revision JSON] revises one existing clip and preserves other actual actions\nretarget: --motion-source GLB --mapping JSON (owned/licensed compatible source, explicit bone/clip mapping)\nrecord: --kind rig|motion|independent|human --reviewer NAME --evidence TASK_LOCAL_JSON\nstatus returns current approvalFingerprints. Human runtime acceptance binds effective engine, current export hashes and runtime-test/runtime-capture/performance-profile evidence.\npromote: --destination assets/models/NEW_DESTINATION\nUses existing Blender4.5LTS and fixed audited scripts; no installer, hosted provider or Adobe integrations. Native guards are not an OS sandbox.");
        return 0;
    }
    var options = new Dictionary<string, string>(StringComparer.Ordinal);
    var allowed = new HashSet<string>(["root", "baseline-root", "task", "asset", "version", "actor", "model", "rights", "recipe", "blender", "editable-source", "source-metadata", "manifest", "motion-source", "mapping", "kind", "reviewer", "evidence", "destination", "revision"], StringComparer.Ordinal);
    for (var i = 1; i < args.Length; i++)
    {
        if (!args[i].StartsWith("--", StringComparison.Ordinal) || i + 1 >= args.Length || args[i + 1].StartsWith("--", StringComparison.Ordinal))
            throw new InvalidOperationException("Expected --option value");
        var key = args[i][2..];
        if (!allowed.Contains(key) || !options.TryAdd(key, args[++i]))
            throw new InvalidOperationException("Unknown/duplicate option: " + key);
    }
    var commandOptions = new HashSet<string>(["root", "baseline-root", "manifest"], StringComparer.Ordinal);
    string[] specific = args[0] switch
    {
        "init" => ["task", "asset", "version", "actor", "model", "rights", "recipe", "blender", "editable-source", "source-metadata"],
        "author" => ["revision"],
        "retarget" => ["motion-source", "mapping"],
        "record" => ["kind", "reviewer", "evidence"],
        "promote" => ["destination"],
        "doctor" or "inspect" or "prepare" or "rig" or "bake" or "export" or "review" or "validate" or "status" => [],
        _ => throw new InvalidOperationException("Unknown command: " + args[0])
    };
    commandOptions.UnionWith(specific);
    foreach (var key in options.Keys)
        if (!commandOptions.Contains(key))
            throw new InvalidOperationException("Option --" + key + " does not apply to " + args[0]);
    var workspace = new Workspace(options.GetValueOrDefault("root", Directory.GetCurrentDirectory()));
    var process = new NativeProcess();
    var baseline = options.GetValueOrDefault("baseline-root") ?? throw new InvalidOperationException("Use the canonical wrapper or supply --baseline-root");
    var task = options.GetValueOrDefault("task") ?? (options.TryGetValue("manifest", out var manifest) ? workspace.Load<Manifest>(MotionValidation.Relative(workspace, manifest)).Task : throw new InvalidOperationException("Supply --task at init or --manifest afterward"));
    var pipeline = new Pipeline(workspace, options, process, new CanonicalEngineResolver(workspace, baseline, process, MotionValidation.Id(task)));
    using var cancellation = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; cancellation.Cancel(); };
    await pipeline.Execute(args[0], cancellation.Token);
    return 0;
}
catch (Exception e) { Console.Error.WriteLine(e.Message); return 1; }
