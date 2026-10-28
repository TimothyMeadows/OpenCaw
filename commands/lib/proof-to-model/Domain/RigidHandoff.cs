using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace OpenCaw.ProofToModel.Domain;

/// <summary>Closed authored rigid HIGH/LOW handoffs; no engine or human-acceptance selector.</summary>
public static class RigidHandoff
{
    public const int MaximumBytes = 524288;
    public const int MaximumReviewBytes = 65536;
    public static JsonObject Parse(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes) throw new InvalidOperationException("Rigid handoff size must be 1..524288 bytes");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 20 });
        var root = document.RootElement;
        FinishingSettings.Fields(root, "rigid handoff", "schemaVersion", "profile", "coordinateFrame", "sourceRawSha256", "preparedGlb", "preparedGlbSha256", "sourceToPreparedMatrix", "authoringEvidence", "authoringEvidenceSha256", "parts");
        FinishingSettings.Integer(root.GetProperty("schemaVersion"), "handoff schemaVersion", 1, 1);
        Literal(root.GetProperty("profile"), "profile", "articulated");
        Literal(root.GetProperty("coordinateFrame"), "coordinateFrame", "opencaw-proof-z-up");
        Digest(root.GetProperty("sourceRawSha256"), "sourceRawSha256");
        Digest(root.GetProperty("preparedGlbSha256"), "preparedGlbSha256");
        Digest(root.GetProperty("authoringEvidenceSha256"), "authoringEvidenceSha256");
        RelativePath(root.GetProperty("preparedGlb"), "preparedGlb", ".glb");
        RelativePath(root.GetProperty("authoringEvidence"), "authoringEvidence", ".json");
        Matrix(root.GetProperty("sourceToPreparedMatrix"));
        var parts = root.GetProperty("parts");
        if (parts.ValueKind != JsonValueKind.Array || parts.GetArrayLength() is < 1 or > 128)
            throw new InvalidOperationException("Rigid handoff requires 1..128 parts");
        var parents = new Dictionary<string, string?>(StringComparer.Ordinal);
        var objects = new HashSet<string>(StringComparer.Ordinal);
        var budgets = new List<long>();
        var bakeGroups = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var part in parts.EnumerateArray())
        {
            FinishingSettings.Fields(part, "rigid part", "id", "parentId", "pivot", "highObject", "lowObject", "maxTriangles", "maxVertexSurfaceErrorMetres", "materialMode", "bakeGroup", "collision", "collisionReason");
            var id = Identifier(part.GetProperty("id"), "part id");
            var parent = part.GetProperty("parentId");
            var parentId = parent.ValueKind == JsonValueKind.Null ? null : Identifier(parent, "parentId");
            if (!parents.TryAdd(id, parentId)) throw new InvalidOperationException("Duplicate rigid part id");
            Vector(part.GetProperty("pivot"), "pivot");
            foreach (var key in new[] { "highObject", "lowObject" })
            {
                var name = Text(part.GetProperty(key), key, 256);
                if (!objects.Add(name)) throw new InvalidOperationException("Every HIGH/LOW mesh name must be unique and disjoint");
            }
            budgets.Add(FinishingSettings.Integer(part.GetProperty("maxTriangles"), "maxTriangles", 4, 8_000_000));
            FinishingSettings.Number(part.GetProperty("maxVertexSurfaceErrorMetres"), "maxVertexSurfaceErrorMetres", 0, 1, exclusiveMinimum: true);
            var material = Text(part.GetProperty("materialMode"), "materialMode", 20);
            var group = part.GetProperty("bakeGroup");
            if (material == "preserve")
            {
                if (group.ValueKind != JsonValueKind.Null) throw new InvalidOperationException("Preserved geometry must not declare an atlas bake group");
            }
            else if (material == "bake")
            {
                var groupId = Identifier(group, "bakeGroup");
                if (bakeGroups.TryGetValue(groupId, out var existing) && existing != groupId)
                    throw new InvalidOperationException("Distinct bakeGroup ids must not alias atlas filenames by case");
                bakeGroups[groupId] = groupId;
            }
            else throw new InvalidOperationException("materialMode must explicitly select preserve or bake");
            if (part.GetProperty("collision").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new InvalidOperationException("collision applicability must be an explicit boolean");
            Text(part.GetProperty("collisionReason"), "collisionReason", 4096);
        }
        foreach (var id in parents.Keys)
        {
            var visited = new HashSet<string>(StringComparer.Ordinal);
            string? cursor = id;
            while (cursor is not null)
            {
                if (!visited.Add(cursor)) throw new InvalidOperationException("Rigid parent hierarchy contains a cycle");
                if (!parents.TryGetValue(cursor, out cursor)) throw new InvalidOperationException("Rigid parentId does not name a declared part");
            }
        }
        var result = JsonNode.Parse(bytes)!.AsObject();
        result["schemaVersion"] = 1;
        for (var index = 0; index < budgets.Count; index++) result["parts"]![index]!["maxTriangles"] = budgets[index];
        return result;
    }

    public static JsonObject ParseReview(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumReviewBytes) throw new InvalidOperationException("Rigid review size must be 1..65536 bytes");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 8 });
        var root = document.RootElement;
        FinishingSettings.Fields(root, "rigid preparation review", "schemaVersion", "kind", "decision", "human", "reviewer", "reason", "sourceRawSha256", "preparedGlbSha256", "handoffSha256", "authoringEvidenceSha256");
        FinishingSettings.Integer(root.GetProperty("schemaVersion"), "review schemaVersion", 1, 1);
        Literal(root.GetProperty("kind"), "kind", "rigid-preparation");
        Literal(root.GetProperty("decision"), "decision", "approved");
        if (root.GetProperty("human").ValueKind != JsonValueKind.False)
            throw new InvalidOperationException("Rigid preparation review is explicitly technical, not human runtime approval");
        Text(root.GetProperty("reviewer"), "reviewer", 256);
        Text(root.GetProperty("reason"), "reason", 4096);
        Digest(root.GetProperty("sourceRawSha256"), "sourceRawSha256");
        Digest(root.GetProperty("preparedGlbSha256"), "preparedGlbSha256");
        Digest(root.GetProperty("handoffSha256"), "handoffSha256");
        Digest(root.GetProperty("authoringEvidenceSha256"), "authoringEvidenceSha256");
        var result = JsonNode.Parse(bytes)!.AsObject();
        result["schemaVersion"] = 1;
        return result;
    }

    public static JsonObject ParseAuthoring(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes) throw new InvalidOperationException("Rigid authoring evidence size must be 1..524288 bytes");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 });
        var root = document.RootElement;
        FinishingSettings.Fields(root, "rigid authoring evidence", "schemaVersion", "kind", "sourceRawSha256", "preparedGlbSha256", "sources", "repairs");
        FinishingSettings.Integer(root.GetProperty("schemaVersion"), "authoring schemaVersion", 1, 1);
        Literal(root.GetProperty("kind"), "kind", "rigid-part-authoring");
        Digest(root.GetProperty("sourceRawSha256"), "sourceRawSha256");
        Digest(root.GetProperty("preparedGlbSha256"), "preparedGlbSha256");
        var sources = root.GetProperty("sources");
        if (sources.ValueKind != JsonValueKind.Array || sources.GetArrayLength() is < 1 or > 64)
            throw new InvalidOperationException("Authoring sources must contain 1..64 dependencies");
        var paths = new HashSet<string>(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        foreach (var source in sources.EnumerateArray())
        {
            FinishingSettings.Fields(source, "authoring source", "path", "sha256", "role");
            if (!paths.Add(RelativePath(source.GetProperty("path"), "source path", "")))
                throw new InvalidOperationException("Authoring source paths must be unique");
            Digest(source.GetProperty("sha256"), "source sha256");
            Text(source.GetProperty("role"), "source role", 4096);
        }
        var repairs = root.GetProperty("repairs");
        if (repairs.ValueKind != JsonValueKind.Array || repairs.GetArrayLength() is < 1 or > 128)
            throw new InvalidOperationException("Authoring repairs must describe 1..128 parts");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var counts = new List<(long High, long Low)>();
        foreach (var repair in repairs.EnumerateArray())
        {
            FinishingSettings.Fields(repair, "authoring repair", "partId", "sourceKind", "sourceDescription", "highTriangles", "lowTriangles", "intentionalChanges");
            if (!ids.Add(Identifier(repair.GetProperty("partId"), "repair partId")))
                throw new InvalidOperationException("Authoring repairs must name every part exactly once");
            if (Text(repair.GetProperty("sourceKind"), "sourceKind", 32) is not ("reconstruction-part" or "authored-detail"))
                throw new InvalidOperationException("sourceKind must distinguish reconstruction parts from authored details");
            Text(repair.GetProperty("sourceDescription"), "sourceDescription", 4096);
            Text(repair.GetProperty("intentionalChanges"), "intentionalChanges", 4096);
            counts.Add((FinishingSettings.Integer(repair.GetProperty("highTriangles"), "highTriangles", 1, long.MaxValue),
                        FinishingSettings.Integer(repair.GetProperty("lowTriangles"), "lowTriangles", 1, long.MaxValue)));
        }
        var result = JsonNode.Parse(bytes)!.AsObject();
        result["schemaVersion"] = 1;
        for (var index = 0; index < counts.Count; index++)
        {
            result["repairs"]![index]!["highTriangles"] = counts[index].High;
            result["repairs"]![index]!["lowTriangles"] = counts[index].Low;
        }
        return result;
    }

    internal static string Text(JsonElement value, string name, int maximum)
    {
        if (value.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(value.GetString())
            || value.GetString()!.Length > maximum || value.GetString()!.Any(char.IsControl))
            throw new InvalidOperationException(name + " requires a nonempty bounded string without control characters");
        return value.GetString()!;
    }
    static void Literal(JsonElement value, string name, string expected)
    {
        if (Text(value, name, 80) != expected) throw new InvalidOperationException(name + " must be " + expected);
    }
    static string Identifier(JsonElement value, string name)
    {
        var id = Text(value, name, 80);
        if (!Regex.IsMatch(id, @"\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z", RegexOptions.CultureInvariant))
            throw new InvalidOperationException(name + " requires a safe ASCII identifier");
        return id;
    }
    internal static string Digest(JsonElement value, string name)
    {
        var digest = Text(value, name, 64);
        if (!Regex.IsMatch(digest, @"\A[a-f0-9]{64}\z", RegexOptions.CultureInvariant))
            throw new InvalidOperationException(name + " requires an exact lowercase SHA256");
        return digest;
    }
    internal static string RelativePath(JsonElement value, string name, string extension)
    {
        var path = Text(value, name, 4096);
        if (path.Contains('\\') || path.Contains(':') || Path.IsPathRooted(path)
            || path.Split('/').Any(segment => segment is "" or "." or ".." || segment.EndsWith(' ') || segment.EndsWith('.')
                || segment.IndexOfAny(['<', '>', '"', '|', '?', '*']) >= 0
                || Regex.IsMatch(segment, @"^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$)(\.|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
            || !path.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(name + " requires a normalized project-relative " + extension + " path without aliases");
        return path;
    }
    static double[] Vector(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() != 3)
            throw new InvalidOperationException(name + " requires three finite components");
        return value.EnumerateArray().Select(x => FinishingSettings.Number(x, name, -1e9, 1e9)).ToArray();
    }
    static void Matrix(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() != 4)
            throw new InvalidOperationException("sourceToPreparedMatrix requires a finite affine 4x4 matrix");
        var rows = value.EnumerateArray().Select(row =>
        {
            if (row.ValueKind != JsonValueKind.Array || row.GetArrayLength() != 4)
                throw new InvalidOperationException("sourceToPreparedMatrix requires four components per row");
            return row.EnumerateArray().Select(x => FinishingSettings.Number(x, "matrix", -1e9, 1e9)).ToArray();
        }).ToArray();
        if (!rows[3].SequenceEqual(new double[] { 0, 0, 0, 1 })) throw new InvalidOperationException("sourceToPreparedMatrix must be affine");
        var d = rows[0][0] * (rows[1][1] * rows[2][2] - rows[1][2] * rows[2][1])
              - rows[0][1] * (rows[1][0] * rows[2][2] - rows[1][2] * rows[2][0])
              + rows[0][2] * (rows[1][0] * rows[2][1] - rows[1][1] * rows[2][0]);
        if (!double.IsFinite(d) || d <= 0) throw new InvalidOperationException("sourceToPreparedMatrix requires positive nonsingular orientation");
    }
}
