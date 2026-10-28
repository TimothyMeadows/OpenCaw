using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Application;
using OpenCaw.ModelAction.Domain;
using OpenCaw.ModelAction.Infrastructure;

try
{
    if (args.Length == 0 || args.Contains("--help") || args[0] == "help")
    {
        Console.WriteLine("model-to-action <init|doctor|inspect|compose|export|review|record|validate|status|promote> --root ROOT --baseline-root BASELINE [options]\ninit: --task ID --asset ID --version ID --actor NAME --motion-package PROJECT_JSON --recipe PROJECT_JSON --source-review TASK_JSON --blender ABSOLUTE_EXE\nOther commands: --manifest TASK_LOCAL_MANIFEST\nrecord: --kind action|independent|human --reviewer NAME --evidence TASK_JSON\npromote: --destination assets/models/NEW_DESTINATION\nSource review is an explicit source-motion human assertion binding exact package/model/rig/used clip hashes. Action/runtime acceptance remains separate. Fixed Blender4.5 scripts only; no installer, Adobe, hosted provider or gameplay authority. Native guards are not an OS sandbox.");
        return 0;
    }
    var options = new Dictionary<string, string>(StringComparer.Ordinal);
    var allowed = new HashSet<string>(["root", "baseline-root", "manifest"], StringComparer.Ordinal);
    string[] specific = args[0] switch
    {
        "init" => ["task", "asset", "version", "actor", "motion-package", "recipe", "source-review", "blender"],
        "record" => ["kind", "reviewer", "evidence"], "promote" => ["destination"],
        "doctor" or "inspect" or "compose" or "export" or "review" or "validate" or "status" => [],
        _ => throw new InvalidOperationException("Unknown action command")
    };
    allowed.UnionWith(specific);
    for (var index = 1; index < args.Length; index++)
    {
        if (!args[index].StartsWith("--", StringComparison.Ordinal) || index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal)) throw new InvalidOperationException("Expected --option value");
        var key = args[index][2..];
        if (!allowed.Contains(key) || !options.TryAdd(key, args[++index])) throw new InvalidOperationException("Unknown/duplicate action option: " + key);
    }
    var workspace = new Workspace(options.GetValueOrDefault("root", Directory.GetCurrentDirectory()));
    var baseline = options.GetValueOrDefault("baseline-root") ?? throw new InvalidOperationException("Use canonical wrapper or supply --baseline-root");
    var task = options.GetValueOrDefault("task") ?? (options.TryGetValue("manifest", out var manifest) ? workspace.Load<Manifest>(ActionValidation.Relative(workspace, manifest)).Task : throw new InvalidOperationException("Supply --task or --manifest"));
    var process = new NativeProcess();
    using var cancellation = new CancellationTokenSource();
    Console.CancelKeyPress += (_, eventArgs) => { eventArgs.Cancel = true; cancellation.Cancel(); };
    await new Pipeline(workspace, options, process, new EngineResolver(workspace, baseline, process, ActionValidation.Id(task))).Execute(args[0], cancellation.Token);
    return 0;
}
catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
