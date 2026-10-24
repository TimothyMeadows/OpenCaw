using System.Buffers.Binary;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using OpenCaw.AssetProduction;
namespace OpenCaw.ModelAnimation.Application;

public static class MotionValidation
{
    public static string Text(JsonObject value, string key) => value[key] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text) ? text : throw new InvalidOperationException("Missing text field: " + key);
    public static JsonArray Array(JsonObject value, string key) => value[key] as JsonArray ?? throw new InvalidOperationException("Missing array: " + key);
    public static void Fields(JsonObject value, params string[] allowed)
    {
        foreach (var pair in value)
            if (!allowed.Contains(pair.Key, StringComparer.Ordinal))
                throw new InvalidOperationException("Unsupported field: " + pair.Key);
    }
    public static string Id(string id) => Regex.IsMatch(id, "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$") && id != ".." ? id : throw new InvalidOperationException("Unsafe identifier");
    public static void Hash(string hash)
    {
        if (!Regex.IsMatch(hash, "^[a-f0-9]{64}$"))
            throw new InvalidOperationException("Expected lowercase SHA-256");
    }
    public static string Relative(IWorkspace w, string path)
    {
        if (Path.IsPathRooted(path) || path.Contains('\\') || path.Split('/').Any(part => part is "" or "." or ".."))
            throw new InvalidOperationException("Expected normalized repository-relative path");
        var result = w.Relative(path);
        if (result != path)
            throw new InvalidOperationException("Path is not normalized");
        return result;
    }
    public static void NoExcludedProviders(JsonNode? node)
    {
        var providerKeys = new HashSet<string>(["provider", "vendor", "tool", "authoringtool", "sourceprovider", "sourcetool", "sourceorigin", "createdwith", "generator"], StringComparer.OrdinalIgnoreCase);
        var uriKeys = new HashSet<string>(["source", "sourceuri", "sourceurl", "url", "origin"], StringComparer.OrdinalIgnoreCase);
        void Visit(JsonNode? value, string key)
        {
            if (value is JsonObject obj)
                foreach (var pair in obj)
                    Visit(pair.Value, pair.Key.Replace("-", "").Replace("_", ""));
            else if (value is JsonArray list)
                foreach (var item in list)
                    Visit(item, key);
            else if (value is JsonValue val && val.TryGetValue<string>(out var text))
            {
                var product = providerKeys.Contains(key) && Regex.IsMatch(text, @"\b(adobe|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator)\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                var identity = uriKeys.Contains(key) && Regex.IsMatch(text, @"^\s*(adobe(?:\s+(?:mixamo|firefly|photoshop|illustrator|after\s+effects|substance(?:\s*3d|\s+painter|\s+designer)?))?|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator)\s*$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                var source = uriKeys.Contains(key) && Uri.TryCreate(text, UriKind.Absolute, out var uri) && Regex.IsMatch(uri.Host, @"(^|\.)(adobe\.com|adobe\.io|mixamo\.com|substance3d\.com)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                if (product || identity || source)
                    throw new InvalidOperationException("Excluded authoring/provider provenance is unsupported by this workflow");
            }
        }
        Visit(node, "");
    }
    public static double Number(JsonObject obj, string name, double minimum, double maximum)
    {
        if (obj[name] is not JsonValue value || value.GetValueKind() != JsonValueKind.Number || !double.TryParse(value.ToJsonString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var result) || !double.IsFinite(result) || result < minimum || result > maximum)
            throw new InvalidOperationException("Invalid bounded number: " + name);
        return result;
    }
    public static int Integer(JsonObject obj, string name, int minimum, int maximum)
    {
        if (obj[name] is not JsonValue value || !value.TryGetValue<int>(out var result) || result < minimum || result > maximum)
            throw new InvalidOperationException("Invalid bounded integer: " + name);
        return result;
    }
    static void Unique(JsonArray array, string key)
    {
        var ids = array.Select(node => Id(Text(node!.AsObject(), key))).ToArray();
        if (ids.Distinct(StringComparer.Ordinal).Count() != ids.Length)
            throw new InvalidOperationException("Duplicate " + key);
    }
    public static void Recipe(JsonObject recipe)
    {
        Fields(recipe, "schemaVersion", "profile", "fps", "requiredClips", "rig", "parts", "anchors", "clips", "states", "transitions", "parameters", "effects", "budgets", "review", "provenance", "coordinateSystem", "preparation");
        if (recipe["schemaVersion"]?.GetValue<int>() != 1 || Text(recipe, "profile") is not ("skinned" or "articulated" or "rigid"))
            throw new InvalidOperationException("Unknown motion recipe/profile");
        Integer(recipe, "fps", 1, 120);
        if (recipe["rig"] is not JsonObject || recipe["budgets"] is not JsonObject budget || recipe["review"] is not JsonObject review)
            throw new InvalidOperationException("Rig, budgets and review objects required");
        foreach (var key in new[] { "requiredClips", "parts", "anchors", "clips", "states", "transitions", "parameters", "effects" })
            _ = Array(recipe, key);
        Unique(Array(recipe, "clips"), "id");
        Unique(Array(recipe, "anchors"), "id");
        Unique(Array(recipe, "states"), "id");
        Unique(Array(recipe, "parameters"), "id");
        Unique(Array(recipe, "effects"), "id");
        var clips = Array(recipe, "clips").Select(node => Text(node!.AsObject(), "id")).ToHashSet(StringComparer.Ordinal);
        var states = Array(recipe, "states").Select(node => Text(node!.AsObject(), "id")).ToHashSet(StringComparer.Ordinal);
        var required = Array(recipe, "requiredClips").Select(node => Id(node!.GetValue<string>())).ToArray();
        if (required.Distinct().Count() != required.Length || required.Any(id => !clips.Contains(id)))
            throw new InvalidOperationException("Required clips must exist exactly once");
        foreach (var state in Array(recipe, "states").Select(node => node!.AsObject()))
            if (state["clip"] is JsonValue clip && !clips.Contains(clip.GetValue<string>()))
                throw new InvalidOperationException("State references missing clip");
        foreach (var transition in Array(recipe, "transitions").Select(node => node!.AsObject()))
        {
            if (!states.Contains(Text(transition, "from")) || !states.Contains(Text(transition, "to")))
                throw new InvalidOperationException("Transition references unknown state");
            _ = Text(transition, "trigger");
            Number(transition, "duration", 0, 30);
        }
        foreach (var parameter in Array(recipe, "parameters").Select(node => node!.AsObject()))
        {
            _ = Text(parameter, "unit");
            var min = Number(parameter, "min", -1e9, 1e9);
            var max = Number(parameter, "max", min, 1e9);
            Number(parameter, "default", min, max);
        }
        Integer(budget, "maxTriangles", 1, 100_000_000);
        Integer(budget, "maxBones", 0, 10000);
        Integer(budget, "maxInfluences", 0, 8);
        Integer(budget, "maxMaterials", 1, 10000);
        Number(budget, "maxTextureBytes", 1, 64L * 1024 * 1024 * 1024);
        Number(budget, "maxRuntimeBytes", 1, 64L * 1024 * 1024 * 1024);
        Integer(budget, "maxClips", 1, 1000);
        Number(budget, "maxClipSeconds", .01, 3600);
        Integer(budget, "maxSamples", 1, 1_000_000);
        Integer(budget, "maxPreviewFrames", 1, 10000);
        Integer(budget, "maxAttempts", 1, 100);
        Integer(budget, "timeoutSeconds", 1, 86400);
        Number(budget, "maxLogBytes", 1024, 1024L * 1024 * 1024);
        if (clips.Count > budget["maxClips"]!.GetValue<int>())
            throw new InvalidOperationException("Clip inventory exceeds budget");
        if (Text(recipe, "profile") == "skinned" && (budget["maxBones"]!.GetValue<int>() < 1 || budget["maxInfluences"]!.GetValue<int>() < 1))
            throw new InvalidOperationException("Skinned profile requires bone and influence budgets");
        foreach (var clip in Array(recipe, "clips").Select(node => node!.AsObject()))
        {
            _ = Text(clip, "role");
            if (clip["loop"] is not JsonValue loop || !loop.TryGetValue<bool>(out _))
                throw new InvalidOperationException("Explicit clip loop policy required");
            if (Text(clip, "rootMotion") is not ("in-place" or "extract"))
                throw new InvalidOperationException("Explicit root-motion policy required");
            var first = Integer(clip, "startFrame", 0, 1_000_000);
            var last = Integer(clip, "endFrame", first + 1, 1_000_000);
            if ((last - first) / (double)recipe["fps"]!.GetValue<int>() > budget["maxClipSeconds"]!.GetValue<double>())
                throw new InvalidOperationException("Clip duration exceeds budget");
            _ = Array(clip, "channels");
            _ = Array(clip, "markers");
        }
        _ = Text(review, "renderer");
        Integer(review, "fps", 1, 120);
        _ = review["resolution"] as JsonArray ?? throw new InvalidOperationException("Review resolution required");
        _ = Array(review, "cameras");
        NoExcludedProviders(recipe);
    }
    public static JsonObject Glb(string absolutePath, long maximumBytes = 1073741824)
    {
        var size = new FileInfo(absolutePath).Length;
        if (size < 24 || size > maximumBytes)
            throw new InvalidOperationException("GLB size outside limits");
        using var stream = File.OpenRead(absolutePath);
        using var reader = new BinaryReader(stream);
        if (reader.ReadUInt32() != 0x46546c67 || reader.ReadUInt32() != 2 || reader.ReadUInt32() != size)
            throw new InvalidOperationException("Invalid GLB container");
        var length = reader.ReadUInt32();
        if (reader.ReadUInt32() != 0x4e4f534a || length < 2 || length > 8 * 1024 * 1024 || length > size - 20)
            throw new InvalidOperationException("Invalid GLB JSON chunk");
        var glb = JsonNode.Parse(reader.ReadBytes((int)length))?.AsObject() ?? throw new InvalidOperationException("Missing GLB document");
        if (glb["asset"]?["version"]?.GetValue<string>() != "2.0" || glb["meshes"] is not JsonArray meshes || !meshes.Any(mesh => mesh?["primitives"] is JsonArray primitives && primitives.Count > 0))
            throw new InvalidOperationException("GLB has no actual mesh");
        foreach (var name in new[] { "buffers", "images" })
            foreach (var value in glb[name]?.AsArray() ?? [])
                if (value?["uri"] is JsonValue uri && !uri.GetValue<string>().StartsWith("data:", StringComparison.Ordinal))
                    throw new InvalidOperationException("External GLB dependencies must be packed before motion production");
        if (glb["asset"]?["generator"] is JsonValue generator)
            NoExcludedProviders(new JsonObject { ["generator"] = generator.DeepClone() });
        return glb;
    }
}
