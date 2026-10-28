using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static OpenCaw.ModelAction.Application.ActionValidation;
namespace OpenCaw.ModelAction.Application;

public static class ActionCompiler
{
    static readonly Dictionary<string, (double Min, double Max, bool Integer)> Bounds = new(StringComparer.Ordinal)
    {
        ["maxActions"] = (1, 64, true), ["maxStepsPerAction"] = (1, 256, true), ["maxExpandedSteps"] = (1, 2048, true),
        ["maxActionSeconds"] = (1, 3600, false), ["maxEffects"] = (1, 256, true), ["maxParticles"] = (1, 65536, true),
        ["maxFrames"] = (1, 1000000, true), ["maxReviewFrames"] = (1, 10000, true), ["maxRuntimeBytes"] = (1024, 1073741824, true),
        ["timeoutSeconds"] = (1, 86400, true), ["maxLogBytes"] = (1024, 1073741824, true), ["maxAttempts"] = (1, 100, true)
    };
    public static JsonObject Compile(JsonObject recipe, JsonObject motion, string asset, string version)
    {
        Fields(recipe, "schemaVersion", "fps", "actions", "targets", "budgets", "review", "provenance");
        if (recipe["schemaVersion"]?.GetValue<int>() != 1) throw new InvalidOperationException("Unknown action recipe schema");
        NoExcludedOrigins(recipe);
        var fps = Integer(recipe, "fps", 1, 120);
        var budget = recipe["budgets"]?.AsObject() ?? throw new InvalidOperationException("Explicit action budgets required");
        Fields(budget, [.. Bounds.Keys, "maxVerificationBytes"]);
        foreach (var (key, bound) in Bounds)
            if (bound.Integer) Integer(budget, key, (int)bound.Min, (int)bound.Max); else Number(budget, key, bound.Min, bound.Max);
        var effectiveBudget = budget.DeepClone().AsObject();
        effectiveBudget["maxVerificationBytes"] = VerificationBytes(budget);
        var review = recipe["review"]?.AsObject() ?? throw new InvalidOperationException("Explicit action review required");
        Fields(review, "fps", "resolution", "cameras", "targets");
        Integer(review, "fps", 1, 60);
        if (review["resolution"] is not JsonArray resolution || resolution.Count != 2 || resolution.Any(node => node is not JsonValue val || !val.TryGetValue<int>(out var n) || n < 32 || n > 2048)) throw new InvalidOperationException("Review resolution must be two bounded integers");
        var cameras = Array(review, "cameras").Select(node => node?.GetValue<string>() ?? "").ToArray();
        if (cameras.Length == 0 || cameras.Length > 5 || cameras.Distinct().Count() != cameras.Length || cameras.Any(name => name is not ("front" or "three-quarter" or "right" or "left" or "back"))) throw new InvalidOperationException("Unknown/empty/duplicate review cameras");
        var previewTargets = review["targets"]?.AsObject() ?? throw new InvalidOperationException("Explicit review target map required");
        var targets = Array(recipe, "targets"); Unique(targets, "id");
        var targetNames = targets.Select(node => Text(node!.AsObject(), "id")).ToHashSet(StringComparer.Ordinal);
        foreach (var target in targets.Select(node => node!.AsObject()))
        {
            Fields(target, "id", "mode", "maxDistance");
            if (Text(target, "mode") != "fixed-world-point") throw new InvalidOperationException("Only fixed-world-point target snapshots are supported");
            Number(target, "maxDistance", .001, 100000);
        }
        foreach (var pair in previewTargets)
            if (!targetNames.Contains(pair.Key) || pair.Value is not JsonArray point || point.Count != 3 || point.Any(node => node is not JsonValue val || !val.TryGetValue<double>(out var n) || !double.IsFinite(n) || Math.Abs(n) > 1e6)) throw new InvalidOperationException("Invalid preview target coordinates");
        var source = Array(motion, "clips").Select(node => node!.AsObject()).ToDictionary(clip => Text(clip, "id"), StringComparer.Ordinal);
        var anchors = Array(motion, "anchors").Select(node => Text(node!.AsObject(), "id")).ToHashSet(StringComparer.Ordinal);
        var definitions = Array(recipe, "actions"); Unique(definitions, "id");
        if (definitions.Count is < 1 || definitions.Count > budget["maxActions"]!.GetValue<int>()) throw new InvalidOperationException("Action count exceeds explicit budget");
        var actions = new JsonArray(); var used = new HashSet<string>(StringComparer.Ordinal); long frames = 0; var totalSteps = 0;
        foreach (var definition in definitions.Select(node => node!.AsObject()))
        {
            Fields(definition, "id", "role", "steps", "cues");
            var id = Id(Text(definition, "id")); _ = Text(definition, "role");
            var steps = Array(definition, "steps"); Unique(steps, "id");
            if (steps.Count is < 1 || steps.Count > budget["maxStepsPerAction"]!.GetValue<int>()) throw new InvalidOperationException("Step count exceeds budget");
            var expanded = new JsonArray(); var markers = new JsonArray(); var occurrenceMap = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
            foreach (var step in steps.Select(node => node!.AsObject()))
            {
                Fields(step, "id", "clip", "from", "to", "rate", "repeat", "blendIn");
                var clipName = Id(Text(step, "clip"));
                if (!source.TryGetValue(clipName, out var clip)) throw new InvalidOperationException("Missing reviewed source clip: " + clipName);
                if (Text(clip, "rootMotion") != "in-place") throw new InvalidOperationException("Action composition requires in-place clips; author an in-place counterpart or select an explicit engine movement adapter");
                used.Add(clipName);
                var from = Number(step, "from", 0, 3600); var to = Number(step, "to", 0, Number(clip, "duration", .000001, 3600));
                if (to <= from) throw new InvalidOperationException("Clip trim must have positive duration");
                var rate = Number(step, "rate", .1, 4); var repeat = Integer(step, "repeat", 1, 16);
                var blend = Number(step, "blendIn", 0, 30); var span = (to - from) / rate;
                for (var occurrence = 0; occurrence < repeat; occurrence++)
                {
                    var previous = expanded.LastOrDefault()?.AsObject();
                    if (previous is null && blend != 0) throw new InvalidOperationException("First expanded step must have zero blendIn");
                    if (previous is not null && (blend >= span - 1e-9 || blend >= previous["end"]!.GetValue<double>() - previous["start"]!.GetValue<double>() - 1e-9)) throw new InvalidOperationException("Blend must leave a positive nonoverlapped span in both adjacent steps");
                    var start = previous is null ? 0 : previous["end"]!.GetValue<double>() - blend; var end = start + span;
                    if (expanded.Count >= 2 && start < expanded[^2]!["end"]!.GetValue<double>() - 1e-7) throw new InvalidOperationException("Triple clip overlap is unsupported");
                    if (Math.Abs(start * fps - Math.Round(start * fps)) > 1e-5 || Math.Abs(end * fps - Math.Round(end * fps)) > 1e-5) throw new InvalidOperationException("Step timing is not frame aligned; choose compatible trims/rates/blends or bake FPS");
                    var item = new JsonObject { ["id"] = Text(step, "id"), ["clip"] = clipName, ["occurrence"] = occurrence, ["start"] = start, ["end"] = end, ["sourceStart"] = from, ["sourceEnd"] = to, ["rate"] = rate, ["blendIn"] = blend, ["motionSha256"] = Text(clip, "motionSha256") };
                    occurrenceMap.Add(Text(step, "id") + ":" + occurrence, item);
                    var stepIndex = expanded.Count; expanded.Add(item);
                    markers.Add(new JsonObject { ["id"] = "s" + stepIndex + "-enter", ["at"] = start, ["name"] = "step-enter", ["step"] = Text(step, "id"), ["occurrence"] = occurrence });
                    markers.Add(new JsonObject { ["id"] = "s" + stepIndex + "-exit", ["at"] = end, ["name"] = "step-exit", ["step"] = Text(step, "id"), ["occurrence"] = occurrence });
                    if (clip["markers"] is JsonArray sourceMarkers)
                        foreach (var (marker, number) in sourceMarkers.Select((node, index) => (node!.AsObject(), index)))
                        {
                            var time = Number(marker, "time", 0, clip["duration"]!.GetValue<double>());
                            if (time >= from - 1e-7 && time <= to + 1e-7)
                                markers.Add(new JsonObject { ["id"] = "s" + stepIndex + "-m" + number, ["at"] = start + (time - from) / rate, ["name"] = Text(marker, "event"), ["step"] = Text(step, "id"), ["occurrence"] = occurrence });
                        }
                }
            }
            totalSteps += expanded.Count;
            if (totalSteps > budget["maxExpandedSteps"]!.GetValue<int>()) throw new InvalidOperationException("Expanded step budget exceeded");
            var duration = expanded[^1]!["end"]!.GetValue<double>();
            if (duration > budget["maxActionSeconds"]!.GetValue<double>()) throw new InvalidOperationException("Action duration budget exceeded");
            frames += checked((long)Math.Round(duration * fps) + 1);
            var cueDefinitions = Array(definition, "cues"); Unique(cueDefinitions, "id");
            if (cueDefinitions.Count > budget["maxEffects"]!.GetValue<int>()) throw new InvalidOperationException("Effect budget exceeded");
            double ResolveAddress(JsonObject address)
            {
                Fields(address, "step", "occurrence", "offset", "marker");
                var key = Text(address, "step") + ":" + Integer(address, "occurrence", 0, 15);
                if (!occurrenceMap.TryGetValue(key, out var item)) throw new InvalidOperationException("Cue references a missing step occurrence");
                if ((address["offset"] is null) == (address["marker"] is null)) throw new InvalidOperationException("Cue address requires exactly offset or source marker");
                if (address["offset"] is not null) return item["start"]!.GetValue<double>() + Number(address, "offset", 0, item["end"]!.GetValue<double>() - item["start"]!.GetValue<double>());
                var candidates = (source[Text(item, "clip")]["markers"] as JsonArray ?? []).Select(node => node!.AsObject())
                    .Where(marker => Text(marker, "event") == Text(address, "marker") && Number(marker, "time", 0, 3600) >= item["sourceStart"]!.GetValue<double>() - 1e-7 && marker["time"]!.GetValue<double>() <= item["sourceEnd"]!.GetValue<double>() + 1e-7).ToArray();
                if (candidates.Length != 1) throw new InvalidOperationException("Cue marker must occur exactly once within the source trim");
                return item["start"]!.GetValue<double>() + (candidates[0]["time"]!.GetValue<double>() - item["sourceStart"]!.GetValue<double>()) / item["rate"]!.GetValue<double>();
            }
            var cues = new JsonArray(); var capacity = 0;
            foreach (var cue in cueDefinitions.Select(node => node!.AsObject()))
            {
                var type = Text(cue, "type");
                if (type is not ("orb" or "particles" or "projectile")) throw new InvalidOperationException("Unknown bounded presentation effect");
                Fields(cue, type == "particles" ? ["id", "type", "anchor", "start", "end", "color", "radius", "capacity", "rate", "seed"] : type == "projectile" ? ["id", "type", "anchor", "start", "end", "color", "radius", "target"] : ["id", "type", "anchor", "start", "end", "color", "radius"]);
                if (!anchors.Contains(Text(cue, "anchor"))) throw new InvalidOperationException("Cue anchor is not an actual reviewed source anchor");
                if (!Regex.IsMatch(Text(cue, "color"), "^#[a-fA-F0-9]{6}$")) throw new InvalidOperationException("Effect color must be #RRGGBB");
                Number(cue, "radius", .001, 10);
                var start = ResolveAddress(cue["start"]!.AsObject()); var end = ResolveAddress(cue["end"]!.AsObject());
                if (end <= start || end > duration + 1e-7) throw new InvalidOperationException("Effect lifetime must be positive and within the action");
                var compiled = cue.DeepClone().AsObject(); compiled["start"] = start; compiled["end"] = end;
                if (type == "particles")
                {
                    capacity += Integer(cue, "capacity", 1, budget["maxParticles"]!.GetValue<int>());
                    Number(cue, "rate", 0, 1000); Integer(cue, "seed", 0, int.MaxValue);
                }
                if (type == "projectile" && (!targetNames.Contains(Text(cue, "target")) || previewTargets[Text(cue, "target")] is null)) throw new InvalidOperationException("Projectile requires a declared fixed target and explicit technical preview target");
                cues.Add(compiled);
            }
            if (capacity > budget["maxParticles"]!.GetValue<int>()) throw new InvalidOperationException("Per-action aggregate particle capacity exceeds budget");
            if (markers.Count + expanded.Count * 2 + cues.Count * 2 > 8192) throw new InvalidOperationException("Action boundary inventory exceeds bounded engine subdivision capacity");
            var ordered = markers.Select(node => node!.AsObject()).OrderBy(marker => marker["at"]!.GetValue<double>()).ThenBy(marker => Text(marker, "id"), StringComparer.Ordinal).Select(node => node.DeepClone()).ToArray();
            actions.Add(new JsonObject { ["id"] = id, ["role"] = Text(definition, "role"), ["clip"] = id, ["duration"] = duration, ["steps"] = expanded, ["cues"] = cues, ["markers"] = new JsonArray(ordered) });
        }
        if (frames > budget["maxFrames"]!.GetValue<int>()) throw new InvalidOperationException("Aggregate action bake frame budget exceeded");
        long previewFrames = 0;
        foreach (var action in actions.Select(node => node!.AsObject()))
        {
            var duration = action["duration"]!.GetValue<double>();
            var samples = new HashSet<double>();
            void Add(double time) => samples.Add(Math.Round(time, 9, MidpointRounding.ToEven));
            Add(0); Add(duration);
            for (var index = 0; index <= Math.Ceiling(duration * review["fps"]!.GetValue<int>()); index++) Add(Math.Min(duration, (double)index / review["fps"]!.GetValue<int>()));
            foreach (var step in Array(action, "steps")) { Add(step!["start"]!.GetValue<double>()); Add(step["end"]!.GetValue<double>()); }
            foreach (var cue in Array(action, "cues")) { Add(cue!["start"]!.GetValue<double>()); Add(cue["end"]!.GetValue<double>()); }
            foreach (var marker in Array(action, "markers")) Add(marker!["at"]!.GetValue<double>());
            previewFrames += samples.Count * cameras.Length;
        }
        if (previewFrames > budget["maxReviewFrames"]!.GetValue<int>()) throw new InvalidOperationException("Complete technical review exceeds frame budget");
        if (previewFrames * resolution[0]!.GetValue<int>() * resolution[1]!.GetValue<int>() > 1073741824) throw new InvalidOperationException("Complete technical review exceeds fixed pixel budget");
        if (used.Sum(name => (long)Math.Round(source[name]["duration"]!.GetValue<double>() * fps) + 1) > budget["maxFrames"]!.GetValue<int>()) throw new InvalidOperationException("Complete source inspection exceeds frame budget");
        var ancestry = new JsonArray(used.Order(StringComparer.Ordinal).Select(name => (JsonNode)new JsonObject { ["id"] = name, ["motionSha256"] = Text(source[name], "motionSha256") }).ToArray());
        return new JsonObject { ["schemaVersion"] = "opencaw-action-package/v1", ["asset"] = Id(asset), ["version"] = Id(version), ["profile"] = Text(motion, "profile"), ["fps"] = fps,
            ["rig"] = motion["rig"]!.DeepClone(), ["coordinateSystem"] = new JsonObject { ["runtimeUp"] = "+Y", ["runtimeForward"] = "+Z" },
            ["sourceMotion"] = new JsonObject { ["rigId"] = Text(motion["rig"]!.AsObject(), "id"), ["clips"] = ancestry }, ["anchors"] = motion["anchors"]!.DeepClone(), ["targets"] = targets.DeepClone(), ["budgets"] = effectiveBudget, ["actions"] = actions, ["verification"] = new JsonObject { ["status"] = "pending" } };
    }
}
