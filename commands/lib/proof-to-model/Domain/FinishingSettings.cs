using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace OpenCaw.ProofToModel.Domain;

/// <summary>Explicit, bounded finishing-only choices; never reconstruction settings or a fallback.</summary>
public static class FinishingSettings
{
    public const int MaximumBytes = 65536;
    public const long MaximumEstimatedVoxels = 2_000_000_000;
    public const int MaximumPreparedTriangles = 20_000_000;
    public const int MaximumCoordinateScale = 1024;
    public const int MaximumSimplificationTriangles = 8_000_000;
    public const int MaximumProtectedRegions = 128;

    public static JsonObject Parse(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes)
            throw new InvalidOperationException("Finishing settings must contain 1..65536 bytes");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidOperationException("finishing settings must be an object");
        var version = Integer(root.GetProperty("schemaVersion"), "schemaVersion", 1, 2);
        if (version == 2) return ParseRigid(bytes, root);
        var hasQuadriFlow = root.TryGetProperty("quadriFlow", out var quadriFlow);
        Fields(root, "finishing settings", hasQuadriFlow
            ? ["schemaVersion", "topologyPreparation", "collision", "quadriFlow"]
            : ["schemaVersion", "topologyPreparation", "collision"]);
        Integer(root.GetProperty("schemaVersion"), "schemaVersion", 1, 1);
        var topology = root.GetProperty("topologyPreparation");
        switch (Method(topology, "topologyPreparation"))
        {
            case "none": Fields(topology, "topologyPreparation", "method"); break;
            case "voxel-remesh":
                Fields(topology, "topologyPreparation", "method", "voxelSize", "maxEstimatedVoxels", "maxPreparedTriangles");
                Number(topology.GetProperty("voxelSize"), "voxelSize", 0, 1, exclusiveMinimum: true);
                Integer(topology.GetProperty("maxEstimatedVoxels"), "maxEstimatedVoxels", 1, MaximumEstimatedVoxels);
                Integer(topology.GetProperty("maxPreparedTriangles"), "maxPreparedTriangles", 4, MaximumPreparedTriangles);
                break;
            default: throw new InvalidOperationException("Unknown topologyPreparation method; select none or voxel-remesh explicitly");
        }
        var collision = root.GetProperty("collision");
        switch (Method(collision, "collision"))
        {
            case "exact-hull": Fields(collision, "collision", "method"); break;
            case "kdop-26":
                Fields(collision, "collision", "method", "padding", "maxVolumeRatio");
                Number(collision.GetProperty("padding"), "padding", 0, 1);
                Number(collision.GetProperty("maxVolumeRatio"), "maxVolumeRatio", 1, 100);
                break;
            default: throw new InvalidOperationException("Unknown collision method; select exact-hull or kdop-26 explicitly");
        }
        int? coordinateScale = null;
        int? simplificationTriangles = null;
        if (hasQuadriFlow)
        {
            if (quadriFlow.ValueKind != JsonValueKind.Object)
                throw new InvalidOperationException("quadriFlow must be an object");
            var hasSimplification = quadriFlow.TryGetProperty("simplification", out var simplification);
            Fields(quadriFlow, "quadriFlow", hasSimplification
                ? ["coordinateScale", "simplification"] : ["coordinateScale"]);
            coordinateScale = (int)Integer(quadriFlow.GetProperty("coordinateScale"), "coordinateScale", 1, MaximumCoordinateScale);
            if ((coordinateScale.Value & (coordinateScale.Value - 1)) != 0)
                throw new InvalidOperationException("coordinateScale must explicitly select a power of two inside 1..1024");
            if (hasSimplification)
                simplificationTriangles = Simplification(simplification);
        }
        var result = JsonNode.Parse(bytes)!.AsObject();
        if (coordinateScale is { } selected)
            result["quadriFlow"]!["coordinateScale"] = selected;
        if (simplificationTriangles is { } triangles)
            result["quadriFlow"]!["simplification"]!["targetTriangles"] = triangles;
        return result;
    }

    static JsonObject ParseRigid(byte[] bytes, JsonElement root)
    {
        Fields(root, "rigid finishing settings", "schemaVersion", "method", "topologyPreparation", "collision", "rigidParts", "resources");
        if (Method(root, "rigid finishing settings") != "rigid-parts")
            throw new InvalidOperationException("Settings v2 must explicitly select rigid-parts");
        var preparation = root.GetProperty("topologyPreparation");
        Fields(preparation, "rigid topologyPreparation", "method");
        if (Method(preparation, "rigid topologyPreparation") != "none")
            throw new InvalidOperationException("Rigid parts require reviewed prepared HIGH/LOW pairs, not an implicit topology repair");
        var collision = root.GetProperty("collision");
        switch (Method(collision, "collision"))
        {
            case "exact-hull": Fields(collision, "collision", "method"); break;
            case "kdop-26":
                var hasFrame = collision.TryGetProperty("frame", out var frame);
                Fields(collision, "collision", hasFrame
                    ? ["method", "padding", "maxVolumeRatio", "frame"]
                    : ["method", "padding", "maxVolumeRatio"]);
                if (hasFrame && (frame.ValueKind != JsonValueKind.String || frame.GetString() is not ("world" or "principal-axes-v1")))
                    throw new InvalidOperationException("Unknown explicit k-DOP frame");
                Number(collision.GetProperty("padding"), "padding", 0, 1);
                Number(collision.GetProperty("maxVolumeRatio"), "maxVolumeRatio", 1, 100);
                break;
            default: throw new InvalidOperationException("Unknown explicit collision method");
        }
        var parts = root.GetProperty("rigidParts");
        var hasUvAtlas = parts.TryGetProperty("uvAtlas", out var uvAtlas);
        var requiredParts = new[] { "handoff", "handoffSha256", "reviewEvidence", "reviewEvidenceSha256", "maxLod0Triangles", "maxGlbBytes" };
        var hasImportNormals = parts.TryGetProperty("importNormals", out var importNormals);
        var hasSourceTopology = parts.TryGetProperty("sourceTopology", out var sourceTopology);
        var allowedParts = new List<string>(requiredParts);
        if (hasUvAtlas) allowedParts.Add("uvAtlas");
        if (hasImportNormals) allowedParts.Add("importNormals");
        if (hasSourceTopology) allowedParts.Add("sourceTopology");
        var hasLods = parts.TryGetProperty("lods", out var lods);
        if (hasLods) allowedParts.Add("lods");
        Fields(parts, "rigidParts", allowedParts.ToArray());
        if (hasSourceTopology)
        {
            if (!hasLods)
                throw new InvalidOperationException("sourceTopology requires explicitly selected source-preserving lods; legacy decimation cannot preserve its owner graph");
            Fields(sourceTopology, "rigidParts.sourceTopology", "method", "receipt", "receiptSha256");
            if (Method(sourceTopology, "rigidParts.sourceTopology") != "reviewed-source-corners-v1")
                throw new InvalidOperationException("sourceTopology must explicitly select reviewed-source-corners-v1");
            RigidHandoff.RelativePath(sourceTopology.GetProperty("receipt"), "sourceTopology receipt", ".json");
            RigidHandoff.Digest(sourceTopology.GetProperty("receiptSha256"), "sourceTopology receiptSha256");
        }
        if (hasLods)
        {
            if (lods.ValueKind != JsonValueKind.Object)
                throw new InvalidOperationException("rigidParts.lods must be an object");
            var hasContactPolicy = lods.TryGetProperty("contactPolicy", out var contactPolicy);
            Fields(lods, "rigidParts.lods", hasContactPolicy
                ? ["method", "maxVertexSurfaceErrorMetres", "contactPolicy"]
                : ["method", "maxVertexSurfaceErrorMetres"]);
            if (Method(lods, "rigidParts.lods") != "original-component-finite-collapse-v1")
                throw new InvalidOperationException("lods must explicitly select original-component-finite-collapse-v1");
            if (hasContactPolicy)
            {
                if (contactPolicy.ValueKind != JsonValueKind.String || contactPolicy.GetString() != "protected-contact-rings-v1")
                    throw new InvalidOperationException("contactPolicy must explicitly select protected-contact-rings-v1");
                if (!hasSourceTopology)
                    throw new InvalidOperationException("contactPolicy requires explicitly reviewed sourceTopology; coordinates are not owner identities");
            }
            var errors = lods.GetProperty("maxVertexSurfaceErrorMetres");
            if (errors.ValueKind != JsonValueKind.Array || errors.GetArrayLength() is < 1 or > 8)
                throw new InvalidOperationException("LOD error bounds must explicitly contain 1..8 world-metre limits");
            foreach (var error in errors.EnumerateArray())
                Number(error, "LOD maxVertexSurfaceErrorMetres", 0, 1, exclusiveMinimum: true);
        }
        if (hasImportNormals)
        {
            Fields(importNormals, "rigidParts.importNormals", "method");
            if (Method(importNormals, "rigidParts.importNormals") != "stored-corner-fan-v1")
                throw new InvalidOperationException("importNormals must explicitly select stored-corner-fan-v1");
        }
        RigidHandoff.RelativePath(parts.GetProperty("handoff"), "handoff", ".json");
        RigidHandoff.Digest(parts.GetProperty("handoffSha256"), "handoffSha256");
        RigidHandoff.RelativePath(parts.GetProperty("reviewEvidence"), "reviewEvidence", ".json");
        RigidHandoff.Digest(parts.GetProperty("reviewEvidenceSha256"), "reviewEvidenceSha256");
        var lod0 = Integer(parts.GetProperty("maxLod0Triangles"), "maxLod0Triangles", 4, 8_000_000);
        var glb = Integer(parts.GetProperty("maxGlbBytes"), "maxGlbBytes", 1024, 2_147_483_648);
        long? marginPixels = null;
        long? repairedTriangles = null;
        if (hasUvAtlas)
        {
            var hasRepair = uvAtlas.TryGetProperty("triangleRepair", out var repair);
            Fields(uvAtlas, "rigidParts.uvAtlas", hasRepair
                ? ["method", "islandMarginPixels", "triangleRepair"] : ["method", "islandMarginPixels"]);
            if (hasRepair)
            {
                Fields(repair, "uvAtlas.triangleRepair", "method", "minCellPixels", "maxTriangles");
                if (Method(repair, "uvAtlas.triangleRepair") != "density-preserving-isolated-cells-v1")
                    throw new InvalidOperationException("UV repair must explicitly select density-preserving-isolated-cells-v1");
                Integer(repair.GetProperty("minCellPixels"), "UV repair minCellPixels", 4, 4);
                repairedTriangles = Integer(repair.GetProperty("maxTriangles"), "UV repair maxTriangles", 1, 16384);
            }
            if (Method(uvAtlas, "rigidParts.uvAtlas") != "smart-project-pixels")
                throw new InvalidOperationException("uvAtlas must explicitly select smart-project-pixels");
            marginPixels = Integer(uvAtlas.GetProperty("islandMarginPixels"), "islandMarginPixels", 1, 64);
        }
        var resources = root.GetProperty("resources");
        Fields(resources, "resources", "maxPrivateBytes");
        var memory = Integer(resources.GetProperty("maxPrivateBytes"), "maxPrivateBytes", 67_108_864, 68_719_476_736);
        var result = JsonNode.Parse(bytes)!.AsObject();
        result["schemaVersion"] = 2;
        result["rigidParts"]!["maxLod0Triangles"] = lod0;
        result["rigidParts"]!["maxGlbBytes"] = glb;
        if (marginPixels is { } pixels)
            result["rigidParts"]!["uvAtlas"]!["islandMarginPixels"] = pixels;
        if (repairedTriangles is { } repairLimit)
        {
            result["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["minCellPixels"] = 4L;
            result["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"] = repairLimit;
        }
        result["resources"]!["maxPrivateBytes"] = memory;
        return result;
    }

    public static void ValidateLodRecipe(JsonObject settings, int recipeLodCount)
    {
        if (settings["rigidParts"]?["lods"] is not JsonObject lods) return;
        if (recipeLodCount is < 1 or > 8 || lods["maxVertexSurfaceErrorMetres"]!.AsArray().Count != recipeLodCount)
            throw new InvalidOperationException("LOD error bounds must match the authoritative recipe.lodRatios count");
    }

    public static void ValidateUvAtlasRecipe(JsonObject settings, double textureSize)
    {
        if (settings["rigidParts"]?["uvAtlas"] is not JsonObject atlas) return;
        if (!double.IsFinite(textureSize) || textureSize <= 0
            || atlas["islandMarginPixels"]!.GetValue<long>() > textureSize / 8)
            throw new InvalidOperationException("uvAtlas islandMarginPixels must not exceed recipe.textureSize/8");
        if (atlas["triangleRepair"] is not null)
        {
            if (textureSize > 8192 || Math.Truncate(textureSize) != textureSize
                || (((long)textureSize & ((long)textureSize - 1)) != 0))
                throw new InvalidOperationException("Selected density-preserving triangle repair requires a positive power-of-two textureSize at most8192");
            var blockPixels = 1L;
            while (blockPixels < 4 + 2 * atlas["islandMarginPixels"]!.GetValue<long>()) blockPixels *= 2;
            if (blockPixels > textureSize)
                throw new InvalidOperationException("Selected density-preserving triangle repair cell and margins must fit the texture");
        }
    }

    static int Simplification(JsonElement value)
    {
        Fields(value, "quadriFlow.simplification", "method", "targetTriangles", "maxVertexSurfaceErrorMetres", "protectedRegions");
        if (Method(value, "quadriFlow.simplification") != "collapse")
            throw new InvalidOperationException("quadriFlow.simplification method must explicitly select collapse");
        var triangles = (int)Integer(value.GetProperty("targetTriangles"), "targetTriangles", 4, MaximumSimplificationTriangles);
        Number(value.GetProperty("maxVertexSurfaceErrorMetres"), "maxVertexSurfaceErrorMetres", 0, 1, exclusiveMinimum: true);
        // The fixed producer must preserve every original prepared vertex inside these
        // inclusive world-metre boxes exactly once, with its identity and stored local
        // coordinates bit-identical and the source transform unchanged.
        // Native parsing validates the declarations; producer evidence proves retention
        // independently of the triangle, component/topology and vertex/surface-error guards.
        var regions = value.GetProperty("protectedRegions");
        if (regions.ValueKind != JsonValueKind.Array || regions.GetArrayLength() > MaximumProtectedRegions)
            throw new InvalidOperationException("protectedRegions must be an explicit array of 0..128 world-metre boxes");
        var identifiers = new HashSet<string>(StringComparer.Ordinal);
        foreach (var region in regions.EnumerateArray())
        {
            Fields(region, "protected region", "id", "min", "max");
            var idValue = region.GetProperty("id");
            if (idValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Protected region id must be a safe ASCII identifier");
            var id = idValue.GetString()!;
            if (id.Length is < 1 or > 80 || !char.IsAsciiLetterOrDigit(id[0])
                || id.Skip(1).Any(character => !char.IsAsciiLetterOrDigit(character) && character is not '.' and not '_' and not '-')
                || !identifiers.Add(id))
                throw new InvalidOperationException("Protected region ids must be unique, ordinal safe ASCII identifiers of 1..80 characters");
            var minimum = WorldVector(region.GetProperty("min"), "protected region min");
            var maximum = WorldVector(region.GetProperty("max"), "protected region max");
            if (minimum.Where((component, axis) => component >= maximum[axis]).Any())
                throw new InvalidOperationException("Protected region min must be strictly below max on every world-metre axis");
        }
        return triangles;
    }
    static double[] WorldVector(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() != 3)
            throw new InvalidOperationException(name + " must contain exactly three finite world-metre numbers");
        return value.EnumerateArray().Select(component => Number(component, name, -1e9, 1e9)).ToArray();
    }

    internal static void Fields(JsonElement value, string name, params string[] expected)
    {
        if (value.ValueKind != JsonValueKind.Object)
            throw new InvalidOperationException(name + " must be an object");
        var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in value.EnumerateObject())
            if (!keys.Add(field.Name) || !expected.Contains(field.Name, StringComparer.Ordinal))
                throw new InvalidOperationException("Unknown or duplicate " + name + " field: " + field.Name);
        if (keys.Count != expected.Length)
            throw new InvalidOperationException(name + " requires exactly: " + string.Join(", ", expected));
    }
    static string Method(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty("method", out var method) || method.ValueKind != JsonValueKind.String)
            throw new InvalidOperationException(name + " requires an explicit string method");
        return method.GetString()!;
    }
    internal static double Number(JsonElement value, string name, double minimum, double maximum, bool exclusiveMinimum = false)
    {
        if (value.ValueKind != JsonValueKind.Number || !double.TryParse(value.GetRawText(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number)
            || !double.IsFinite(number) || (exclusiveMinimum ? number <= minimum : number < minimum) || number > maximum)
            throw new InvalidOperationException(name + " must be a finite JSON number inside " + (exclusiveMinimum ? "(" : "[") + minimum + "," + maximum + "]");
        return number;
    }
    internal static long Integer(JsonElement value, string name, long minimum, long maximum)
    {
        // Normalize exact base-ten digits. Floating conversion can round a
        // fractional residue into an allowed integer or underflow it to zero.
        if (value.ValueKind != JsonValueKind.Number)
            throw new InvalidOperationException(name + " must be a JSON integer");
        var raw = value.GetRawText();
        var negative = raw[0] == '-';
        var unsigned = negative ? raw[1..] : raw;
        var exponentIndex = unsigned.IndexOfAny(['e', 'E']);
        var mantissa = exponentIndex < 0 ? unsigned : unsigned[..exponentIndex];
        var exponentText = exponentIndex < 0 ? "0" : unsigned[(exponentIndex + 1)..];
        var decimalIndex = mantissa.IndexOf('.');
        var fractionDigits = decimalIndex < 0 ? 0 : mantissa.Length - decimalIndex - 1;
        var coefficient = mantissa.Replace(".", "", StringComparison.Ordinal).TrimStart('0');
        if (coefficient.Length == 0)
        {
            if (minimum <= 0 && maximum >= 0) return 0;
            throw new InvalidOperationException(name + " must be inside " + minimum + ".." + maximum);
        }
        var digits = coefficient.TrimEnd('0');
        var trailingZeros = coefficient.Length - digits.Length;
        if (!int.TryParse(exponentText, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var exponent))
            throw new InvalidOperationException(name + " exponent exceeds its bounded integer range");
        var power = (long)exponent - fractionDigits + trailingZeros;
        if (power < 0 || power > 18 || digits.Length + power > 19)
            throw new InvalidOperationException(name + " must be an exact integer inside " + minimum + ".." + maximum);
        var normalized = (negative ? "-" : "") + digits + new string('0', (int)power);
        if (!long.TryParse(normalized, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var result)
            || result < minimum || result > maximum)
            throw new InvalidOperationException(name + " must be inside " + minimum + ".." + maximum);
        return result;
    }
}
