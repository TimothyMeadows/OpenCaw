using System.Buffers.Binary;
using System.Collections;
using System.Security.Cryptography;
using System.Text.Json;

namespace OpenCaw.ProofToModel.Domain;

/// <summary>Bounded representation evidence; actual corner correspondence and geometry require native verification.</summary>
public static class RigidSourceTopology
{
    public const int MaximumBytes = 64 * 1024 * 1024;
    public const int MaximumMeshes = 512;
    public const int MaximumSourceVertices = 8_000_000;
    public const int MaximumIndexedCorners = 16_777_216;

    public sealed record Mesh(string Node, int FileNodeIndex, int SourceVertexCount, int IndexedCorners, string OwnersSha256);
    public sealed record Receipt(string PreparedGlbSha256, IReadOnlyList<Mesh> Meshes);

    public static Receipt Parse(byte[] bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes)
            throw new InvalidOperationException("Source topology receipt must contain1..64MiB");
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
        var root = document.RootElement;
        FinishingSettings.Fields(root, "source topology receipt", "schemaVersion", "kind", "preparedGlbSha256", "meshes");
        FinishingSettings.Integer(root.GetProperty("schemaVersion"), "source topology schemaVersion", 1, 1);
        if (RigidHandoff.Text(root.GetProperty("kind"), "source topology kind", 80) != "rigid-source-corner-topology")
            throw new InvalidOperationException("Unknown source topology receipt kind");
        var preparedHash = RigidHandoff.Digest(root.GetProperty("preparedGlbSha256"), "source topology preparedGlbSha256");
        var entries = root.GetProperty("meshes");
        if (entries.ValueKind != JsonValueKind.Array || entries.GetArrayLength() is < 1 or > MaximumMeshes)
            throw new InvalidOperationException("Source topology receipt must select1..512 LOW meshes");
        var names = new HashSet<string>(StringComparer.Ordinal);
        var indices = new HashSet<int>();
        var meshes = new List<Mesh>();
        foreach (var entry in entries.EnumerateArray())
        {
            FinishingSettings.Fields(entry, "source topology mesh", "node", "fileNodeIndex", "sourceVertexCount", "indexedCorners", "ownersI32LEHex", "ownersSha256");
            var name = RigidHandoff.Text(entry.GetProperty("node"), "source topology node", 256);
            var index = (int)FinishingSettings.Integer(entry.GetProperty("fileNodeIndex"), "source topology fileNodeIndex", 0, 1_000_000);
            if (!names.Add(name) || !indices.Add(index))
                throw new InvalidOperationException("Source topology mesh names and file node indices must be unique");
            var vertices = (int)FinishingSettings.Integer(entry.GetProperty("sourceVertexCount"), "source topology sourceVertexCount", 1, MaximumSourceVertices);
            var corners = (int)FinishingSettings.Integer(entry.GetProperty("indexedCorners"), "source topology indexedCorners", 1, MaximumIndexedCorners);
            if (corners % 3 != 0 || vertices > corners)
                throw new InvalidOperationException("Source topology requires complete triangles and coverage of every declared owner");
            var value = entry.GetProperty("ownersI32LEHex");
            if (value.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Source topology owners require a lowercase hexadecimal i32 field");
            var hex = value.GetString()!;
            if (hex.Length != checked(corners * 8) || hex.Any(character => character is not (>= '0' and <= '9') and not (>= 'a' and <= 'f')))
                throw new InvalidOperationException("Source topology owners require exactly8 lowercase hex characters per indexed corner");
            var expectedHash = RigidHandoff.Digest(entry.GetProperty("ownersSha256"), "source topology ownersSha256");
            var owners = Convert.FromHexString(hex);
            if (Convert.ToHexStringLower(SHA256.HashData(owners)) != expectedHash)
                throw new InvalidOperationException("Source topology decoded owner bytes do not match ownersSha256");
            var covered = new BitArray(vertices);
            var count = 0;
            for (var corner = 0; corner < corners; corner++)
            {
                var owner = BinaryPrimitives.ReadInt32LittleEndian(owners.AsSpan(corner * 4, 4));
                if (owner < 0 || owner >= vertices)
                    throw new InvalidOperationException("Source topology owner ID exceeds declared source vertices");
                if (!covered[owner]) { covered[owner] = true; count++; }
            }
            if (count != vertices)
                throw new InvalidOperationException("Source topology owner field omits declared source vertices");
            meshes.Add(new(name, index, vertices, corners, expectedHash));
        }
        return new(preparedHash, meshes.AsReadOnly());
    }
}
