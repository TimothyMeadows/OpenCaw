using System.Buffers.Binary;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Domain;
namespace OpenCaw.ModelAction.Application;

public static class ActionValidation
{
    public static string Text(JsonObject obj, string key) => obj[key] is JsonValue value && value.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text) ? text : throw new InvalidOperationException("Missing text: " + key);
    public static JsonArray Array(JsonObject obj, string key) => obj[key] as JsonArray ?? throw new InvalidOperationException("Missing array: " + key);
    public static void Fields(JsonObject obj, params string[] allowed)
    {
        foreach (var item in obj) if (!allowed.Contains(item.Key, StringComparer.Ordinal)) throw new InvalidOperationException("Unsupported field: " + item.Key);
    }
    public static string Id(string value) => Regex.IsMatch(value, "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$") && value != ".." ? value : throw new InvalidOperationException("Unsafe identifier");
    public static void Hash(string value) { if (!Regex.IsMatch(value, "^[a-f0-9]{64}$")) throw new InvalidOperationException("Expected lowercase SHA-256"); }
    public static string Relative(IWorkspace workspace, string value)
    {
        if (Path.IsPathRooted(value) || value.Contains('\\') || value.Split('/').Any(part => part is "" or "." or "..")) throw new InvalidOperationException("Expected normalized repository-relative path");
        if (workspace.Relative(value) != value) throw new InvalidOperationException("Path is not normalized");
        return value;
    }
    public static double Number(JsonObject obj, string key, double min, double max)
    {
        if (obj[key] is not JsonValue val || val.GetValueKind() != System.Text.Json.JsonValueKind.Number || !double.TryParse(val.ToJsonString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number) || number < min || number > max) throw new InvalidOperationException("Invalid bounded number: " + key);
        return number;
    }
    public static int Integer(JsonObject obj, string key, int min, int max)
    {
        if (obj[key] is not JsonValue val || !val.TryGetValue<int>(out var number) || number < min || number > max) throw new InvalidOperationException("Invalid bounded integer: " + key);
        return number;
    }
    public static long VerificationBytes(JsonObject budget)
    {
        if (!budget.ContainsKey("maxVerificationBytes")) return ActionVerificationBudget.DefaultBytes;
        if (budget["maxVerificationBytes"] is not JsonValue value || value.GetValueKind() != System.Text.Json.JsonValueKind.Number ||
            !long.TryParse(value.ToJsonString(), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var bytes) ||
            bytes < 1024 || bytes > ActionVerificationBudget.MaximumBytes)
            throw new InvalidOperationException("Invalid bounded integer: maxVerificationBytes");
        return bytes;
    }
    public static void Unique(JsonArray values, string field)
    {
        var names = values.Select(value => Id(Text(value!.AsObject(), field))).ToArray();
        if (names.Length != names.Distinct(StringComparer.Ordinal).Count()) throw new InvalidOperationException("Duplicate " + field);
    }
    public static void NoExcludedOrigins(JsonNode? value)
    {
        var tools = new HashSet<string>(["provider", "vendor", "tool", "authoringtool", "sourceprovider", "sourcetool", "sourceorigin", "createdwith", "generator"], StringComparer.OrdinalIgnoreCase);
        var sources = new HashSet<string>(["source", "sourceuri", "sourceurl", "url", "origin"], StringComparer.OrdinalIgnoreCase);
        const string names = @"adobe(?:\s+(?:mixamo|firefly|photoshop|illustrator|after\s+effects|substance(?:\s*3d|\s+painter|\s+designer)?))?|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator";
        void Visit(JsonNode? node, string key)
        {
            if (node is JsonObject obj) foreach (var item in obj) Visit(item.Value, item.Key.Replace("-", "").Replace("_", ""));
            else if (node is JsonArray list) foreach (var item in list) Visit(item, key);
            else if (node is JsonValue val && val.TryGetValue<string>(out var text))
            {
                var excluded = tools.Contains(key) && Regex.IsMatch(text, @"\b(" + names + @")\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                excluded |= sources.Contains(key) && Regex.IsMatch(text, @"^\s*(" + names + @")\s*$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                excluded |= sources.Contains(key) && Uri.TryCreate(text, UriKind.Absolute, out var uri) && Regex.IsMatch(uri.Host, @"(^|\.)(adobe\.com|adobe\.io|mixamo\.com|substance3d\.com)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                if (excluded) throw new InvalidOperationException("Excluded authoring/provider provenance is unsupported");
            }
        }
        Visit(value, "");
    }
    public static JsonObject Glb(string path)
    {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length < 28 || BinaryPrimitives.ReadUInt32LittleEndian(bytes) != 0x46546c67 || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(4)) != 2 || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(8)) != bytes.Length) throw new InvalidOperationException("Invalid self-contained GLB2");
        var length = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(12)));
        if (length < 2 || length > bytes.Length - 20 || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(16)) != 0x4e4f534a) throw new InvalidOperationException("Missing GLB JSON chunk");
        var root = JsonNode.Parse(bytes.AsSpan(20, length))!.AsObject();
        if (root["asset"]?["version"]?.GetValue<string>() != "2.0") throw new InvalidOperationException("Unsupported glTF asset");
        NoExcludedOrigins(root["asset"]);
        foreach (var group in new[] { "buffers", "images" })
            if (root[group] is JsonArray resources && resources.Any(node => node?["uri"] is not null)) throw new InvalidOperationException("GLB external/data URI dependencies are unsupported");
        if (root["meshes"] is not JsonArray meshes || meshes.Count == 0 || root["nodes"] is not JsonArray nodes || nodes.Count == 0) throw new InvalidOperationException("GLB has no actual mesh hierarchy");
        if (root["animations"] is not JsonArray animations || animations.Count == 0) throw new InvalidOperationException("GLB has no animation");
        var names = animations.Select(node => Text(node!.AsObject(), "name")).ToArray();
        if (names.Length != names.Distinct(StringComparer.Ordinal).Count()) throw new InvalidOperationException("Ambiguous GLB animations");
        foreach (var animation in animations)
            if (animation?["channels"] is not JsonArray channels || channels.Count == 0 || animation["samplers"] is not JsonArray samplers || samplers.Count == 0) throw new InvalidOperationException("Empty GLB animation");
        return root;
    }
    public static void Source(JsonObject motion, JsonObject glb)
    {
        if (Text(motion, "schemaVersion") != "opencaw-motion-package/v1" || Text(motion, "profile") is not ("skinned" or "articulated" or "rigid")) throw new InvalidOperationException("Reviewed motion package/profile required");
        NoExcludedOrigins(motion);
        Unique(Array(motion, "clips"), "id"); Unique(Array(motion, "anchors"), "id");
        var animations = Array(glb, "animations").Select(node => Text(node!.AsObject(), "name")).ToHashSet(StringComparer.Ordinal);
        foreach (var clip in Array(motion, "clips").Select(node => node!.AsObject()))
        {
            Hash(Text(clip, "motionSha256")); Number(clip, "duration", .000001, 3600);
            if (!animations.Contains(Text(clip, "action"))) throw new InvalidOperationException("Source clip has no actual GLB animation binding");
        }
        var nodeNames = Array(glb, "nodes").Where(node => node?["name"] is not null).Select(node => node!["name"]!.GetValue<string>()).ToArray();
        foreach (var anchor in Array(motion, "anchors").Select(node => node!.AsObject()))
            if (nodeNames.Count(name => name == Text(anchor, "node")) != 1) throw new InvalidOperationException("Source anchor must resolve exactly once in actual GLB");
        if (motion["rig"] is not JsonObject rig || string.IsNullOrWhiteSpace(Text(rig, "id"))) throw new InvalidOperationException("Source rig/hierarchy identity required");
        if (Text(motion, "profile") == "skinned" && (glb["skins"] is not JsonArray skins || skins.Count == 0)) throw new InvalidOperationException("Skinned source has no actual GLB skin");
    }
}
