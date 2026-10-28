using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using OpenCaw.ProofToModel.Domain;

namespace OpenCaw.ProofToModel.Application;

public sealed partial class Pipeline
{
    sealed record RigidSelection(string HandoffPath, byte[] HandoffBytes, JsonObject Handoff,
        string PreparedPath, string ReviewPath, byte[] ReviewBytes,
        string AuthoringPath, byte[] AuthoringBytes, Dictionary<string, string> Inputs);

    RigidSelection? ReadRigidSelection()
    {
        if (finishingSelection is not { } settings || settings.Value["method"]?.GetValue<string>() != "rigid-parts") return null;
        if (!native.SupportsPrivateMemoryLimit)
            throw new PlatformNotSupportedException("The explicitly selected rigid finishing memory policy is unavailable in this runner/platform; blocked before spending an attempt or launching a process");
        var declarations = settings.Value["rigidParts"]!.AsObject();
        var handoffPath = declarations["handoff"]!.GetValue<string>();
        var handoffBytes = ReadRigidJson(handoffPath, RigidHandoff.MaximumBytes);
        var handoffHash = ByteHash(handoffBytes);
        if (handoffHash != declarations["handoffSha256"]!.GetValue<string>())
            throw new InvalidOperationException("Rigid handoff checksum changed before admission");
        var handoff = RigidHandoff.Parse(handoffBytes);
        var rawHash = Hash(Artifact("reconstruct", "glb"));
        if (handoff["sourceRawSha256"]!.GetValue<string>() != rawHash)
            throw new InvalidOperationException("Rigid handoff belongs to a different retained raw reconstruction");
        var prepared = handoff["preparedGlb"]!.GetValue<string>();
        var preparedHash = handoff["preparedGlbSha256"]!.GetValue<string>();
        var inputs = new Dictionary<string, string>(StringComparer.Ordinal) { [handoffPath] = handoffHash };
        BindExpected(prepared, preparedHash);
        var authoringPath = handoff["authoringEvidence"]!.GetValue<string>();
        var authoringBytes = ReadRigidJson(authoringPath, RigidHandoff.MaximumBytes);
        var authoringHash = ByteHash(authoringBytes);
        if (authoringHash != handoff["authoringEvidenceSha256"]!.GetValue<string>())
            throw new InvalidOperationException("Rigid authoring evidence checksum changed");
        var authoring = RigidHandoff.ParseAuthoring(authoringBytes);
        foreach (var key in new[] { "sourceRawSha256", "preparedGlbSha256" })
            if (authoring[key]!.GetValue<string>() != handoff[key]!.GetValue<string>())
                throw new InvalidOperationException("Rigid authoring evidence does not bind the current " + key);
        inputs.Add(authoringPath, authoringHash);
        RigidSourceTopology.Receipt? topology = null;
        if (declarations["sourceTopology"] is JsonObject selectedTopology)
        {
            var receiptPath = selectedTopology["receipt"]!.GetValue<string>();
            RequireTaskEvidence(receiptPath);
            var receiptBytes = ReadRigidJson(receiptPath, RigidSourceTopology.MaximumBytes);
            var receiptHash = ByteHash(receiptBytes);
            if (receiptHash != selectedTopology["receiptSha256"]!.GetValue<string>())
                throw new InvalidOperationException("Selected source topology receipt checksum changed before admission");
            topology = RigidSourceTopology.Parse(receiptBytes);
            if (topology.PreparedGlbSha256 != preparedHash)
                throw new InvalidOperationException("Source topology receipt belongs to a different reviewed prepared GLB");
            if (!authoring["sources"]!.AsArray().Any(source => source!["path"]!.GetValue<string>() == receiptPath
                    && source["sha256"]!.GetValue<string>() == receiptHash))
                throw new InvalidOperationException("Source topology receipt requires its exact path/hash in reviewed authoring sources");
            var lowNames = handoff["parts"]!.AsArray().Select(part => part!["lowObject"]!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
            if (topology.Meshes.Any(mesh => !lowNames.Contains(mesh.Node)))
                throw new InvalidOperationException("Source topology receipt may select only existing declared LOW meshes");
            if (declarations["lods"]?["contactPolicy"]?.GetValue<string>() == "protected-contact-rings-v1"
                && !lowNames.SetEquals(topology.Meshes.Select(mesh => mesh.Node)))
                throw new InvalidOperationException("protected-contact-rings-v1 requires reviewed source topology for every declared LOW mesh before native launch");
            BindExpected(receiptPath, receiptHash);
        }
        foreach (var source in authoring["sources"]!.AsArray())
            BindExpected(source!["path"]!.GetValue<string>(), source["sha256"]!.GetValue<string>());
        var reviewPath = declarations["reviewEvidence"]!.GetValue<string>();
        RequireTaskEvidence(reviewPath);
        var reviewBytes = ReadRigidJson(reviewPath, RigidHandoff.MaximumReviewBytes);
        var reviewHash = ByteHash(reviewBytes);
        if (reviewHash != declarations["reviewEvidenceSha256"]!.GetValue<string>())
            throw new InvalidOperationException("Rigid preparation review checksum changed");
        var review = RigidHandoff.ParseReview(reviewBytes);
        if (review["sourceRawSha256"]!.GetValue<string>() != rawHash
            || review["preparedGlbSha256"]!.GetValue<string>() != preparedHash
            || review["handoffSha256"]!.GetValue<string>() != handoffHash
            || review["authoringEvidenceSha256"]!.GetValue<string>() != authoringHash)
            throw new InvalidOperationException("Stale rigid preparation review: exact raw, prepared, handoff and authoring identities required");
        inputs.Add(reviewPath, reviewHash);
        ValidatePreparedMeshDeclarations(prepared, handoff, authoring, declarations["maxLod0Triangles"]!.GetValue<long>(), topology);
        foreach (var input in inputs)
            if (Hash(input.Key) != input.Value) throw new InvalidOperationException("Rigid input changed during admission: " + input.Key);
        return new(handoffPath, handoffBytes, handoff, prepared, reviewPath, reviewBytes, authoringPath, authoringBytes, inputs);

        void BindExpected(string path, string expected)
        {
            var relative = w.Relative(path);
            if (!File.Exists(w.Resolve(relative)) || Hash(relative) != expected)
                throw new InvalidOperationException("Missing/corrupt rigid source dependency: " + path);
            if (inputs.TryGetValue(relative, out var previous) && previous != expected)
                throw new InvalidOperationException("Conflicting rigid source dependency hash: " + path);
            inputs[relative] = expected;
        }
    }

    byte[] ReadRigidJson(string path, int maximum)
    {
        var full = w.Resolve(path);
        if (!File.Exists(full)) throw new InvalidOperationException("Missing rigid JSON input: " + path);
        using var stream = File.OpenRead(full);
        using var reader = new BinaryReader(stream);
        var bytes = reader.ReadBytes(maximum + 1);
        if (bytes.Length is 0 || bytes.Length > maximum) throw new InvalidOperationException("Rigid JSON exceeds its declared byte limit");
        return bytes;
    }
    static string ByteHash(byte[] bytes) => Convert.ToHexStringLower(SHA256.HashData(bytes));

    async Task SnapshotRigidInputs(Stage stage, CancellationToken cancellation)
    {
        var selection = rigidSelection!;
        BindInputSnapshot(stage, selection.HandoffPath, selection.HandoffBytes, "rigidHandoff", "rigid-handoff.json");
        BindInputSnapshot(stage, selection.ReviewPath, selection.ReviewBytes, "rigidPreparationReview", "rigid-preparation-review.json");
        BindInputSnapshot(stage, selection.AuthoringPath, selection.AuthoringBytes, "rigidAuthoringEvidence", "rigid-authoring-evidence.json");
        var copies = new JsonArray();
        var index = 0;
        foreach (var input in selection.Inputs.Where(p => p.Key != selection.HandoffPath && p.Key != selection.ReviewPath && p.Key != selection.AuthoringPath))
        {
            if (stage.Inputs.GetValueOrDefault(input.Key) != input.Value || Hash(input.Key) != input.Value)
                throw new InvalidOperationException("Rigid source changed after admission: " + input.Key);
            var name = stage.Attempt + "/rigid-sources/source" + index++ + Path.GetExtension(input.Key);
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(name))!);
            await using (var source = File.OpenRead(w.Resolve(input.Key)))
            await using (var target = new FileStream(w.Resolve(name), FileMode.CreateNew, FileAccess.Write, FileShare.None))
                await source.CopyToAsync(target, 1048576, cancellation);
            if (Hash(name) != input.Value || Hash(input.Key) != input.Value)
                throw new InvalidOperationException("Immutable rigid source copy differs: " + input.Key);
            stage.Inputs[name] = input.Value;
            if (input.Key == selection.PreparedPath) stage.Artifacts["rigidPreparedSource"] = name;
            copies.Add(new JsonObject { ["source"] = input.Key, ["snapshot"] = name, ["sha256"] = input.Value });
        }
        var lineage = stage.Attempt + "/rigid-source-lineage.json";
        w.Save(lineage, new { schemaVersion = 1, kind = "rigid-input-snapshots", humanApproval = "pending", copies });
        stage.Artifacts["rigidLineage"] = lineage;
        Save();
    }

    void ValidatePreparedMeshDeclarations(string path, JsonObject handoff, JsonObject authoring, long lod0Limit, RigidSourceTopology.Receipt? topology = null)
    {
        // Stream bounded structural preflight; actual geometry/material/UV quality
        // is measured independently by the fixed Blender producer and reviewer.
        using var stream = File.OpenRead(w.Resolve(path));
        using var reader = new BinaryReader(stream);
        if (stream.Length is < 28 or > 2_147_483_648 || reader.ReadUInt32() != 0x46546c67
            || reader.ReadUInt32() != 2 || reader.ReadUInt32() != stream.Length)
            throw new InvalidOperationException("Invalid bounded prepared GLB container");
        var length = reader.ReadUInt32();
        if (length is < 2 or > 16_777_216 || length > stream.Length - stream.Position - 4 || reader.ReadUInt32() != 0x4E4F534A)
            throw new InvalidOperationException("Prepared GLB requires bounded first JSON chunk");
        var bytes = reader.ReadBytes((int)length);
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 64 });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.GetProperty("asset").GetProperty("version").GetString() != "2.0")
            throw new InvalidOperationException("Prepared source must be glTF2");
        foreach (var key in new[] { "skins", "animations" })
            if (root.TryGetProperty(key, out var array) && (array.ValueKind != JsonValueKind.Array || array.GetArrayLength() != 0))
                throw new InvalidOperationException("Rigid prepared source cannot contain skins or animation");
        foreach (var key in new[] { "buffers", "images" })
            if (root.TryGetProperty(key, out var array))
                foreach (var entry in array.EnumerateArray())
                    if (entry.TryGetProperty("uri", out _)) throw new InvalidOperationException("Prepared source dependencies must be embedded, not external/data URIs");
        if (stream.Position + 8 > stream.Length) throw new InvalidOperationException("Prepared GLB has no embedded binary chunk");
        var binaryLength = reader.ReadUInt32();
        if (reader.ReadUInt32() != 0x004E4942 || binaryLength != stream.Length - stream.Position)
            throw new InvalidOperationException("Prepared GLB binary chunk is truncated or has extra chunks");
        var buffers = root.GetProperty("buffers");
        if (buffers.GetArrayLength() != 1 || buffers[0].GetProperty("byteLength").GetInt64() > binaryLength)
            throw new InvalidOperationException("Prepared GLB requires one contained binary buffer");
        var meshes = root.GetProperty("meshes");
        var accessors = root.GetProperty("accessors");
        var binaryStart = stream.Position;
        var views = root.GetProperty("bufferViews");
        foreach (var view in views.EnumerateArray())
        {
            var offset = view.TryGetProperty("byteOffset", out var declaredOffset) ? declaredOffset.GetInt64() : 0;
            var size = view.GetProperty("byteLength").GetInt64();
            if (view.GetProperty("buffer").GetInt32() != 0 || offset < 0 || size < 1 || offset > binaryLength || size > binaryLength - offset)
                throw new InvalidOperationException("Prepared buffer view escapes its embedded binary payload");
        }
        var positionBounds = new Dictionary<int, double[]>();
        var checkedIndices = new HashSet<(int Accessor, long Positions)>();
        var nodes = root.GetProperty("nodes");
        var worldTransforms = ValidatePreparedGraph(root, nodes);
        var names = new Dictionary<string, long>(StringComparer.Ordinal);
        var topologyMeshes = topology?.Meshes.ToDictionary(mesh => mesh.Node, StringComparer.Ordinal);
        var matchedTopologyMeshes = 0;
        for (var nodeIndex = 0; nodeIndex < nodes.GetArrayLength(); nodeIndex++)
        {
            var node = nodes[nodeIndex];
            if (!node.TryGetProperty("mesh", out var index)) continue;
            var meshIndex = index.GetInt32();
            if (meshIndex < 0 || meshIndex >= meshes.GetArrayLength()) throw new InvalidOperationException("Prepared source mesh reference is invalid");
            var name = node.GetProperty("name").GetString();
            if (string.IsNullOrWhiteSpace(name)) throw new InvalidOperationException("Every prepared HIGH/LOW node must have an explicit name");
            long triangles = 0;
            foreach (var primitive in meshes[meshIndex].GetProperty("primitives").EnumerateArray())
            {
                if (primitive.TryGetProperty("mode", out var mode) && mode.GetInt32() != 4)
                    throw new InvalidOperationException("Prepared source primitives must be triangles");
                var positions = primitive.GetProperty("attributes").GetProperty("POSITION").GetInt32();
                if (positions < 0 || positions >= accessors.GetArrayLength()) throw new InvalidOperationException("Prepared POSITION accessor is invalid");
                var positionData = Accessor(positions, true);
                if (!positionBounds.TryGetValue(positions, out var maximumAbsolute))
                {
                    maximumAbsolute = new double[3];
                    stream.Position = positionData.Start;
                    for (long vertex = 0; vertex < positionData.Count; vertex++)
                    {
                        for (var axis = 0; axis < 3; axis++)
                        {
                            var coordinate = reader.ReadSingle();
                            if (!float.IsFinite(coordinate)) throw new InvalidOperationException("Prepared POSITION data contains nonfinite coordinates");
                            maximumAbsolute[axis] = Math.Max(maximumAbsolute[axis], Math.Abs(coordinate));
                        }
                        if (positionData.Stride > 12) stream.Seek(positionData.Stride - 12, SeekOrigin.Current);
                    }
                    positionBounds.Add(positions, maximumAbsolute);
                }
                var world = worldTransforms[nodeIndex];
                var orientation = world[0]*(world[5]*world[10]-world[6]*world[9])
                    -world[1]*(world[4]*world[10]-world[6]*world[8])+world[2]*(world[4]*world[9]-world[5]*world[8]);
                if (!double.IsFinite(orientation) || orientation <= 0)
                    throw new InvalidOperationException("Prepared rigid mesh world transform must have positive orientation; realize mirrored geometry before handoff");
                for (var axis = 0; axis < 3; axis++)
                    if (Math.Abs(world[axis * 4]) * maximumAbsolute[0] + Math.Abs(world[axis * 4 + 1]) * maximumAbsolute[1]
                        + Math.Abs(world[axis * 4 + 2]) * maximumAbsolute[2] + Math.Abs(world[axis * 4 + 3]) > float.MaxValue)
                        throw new InvalidOperationException("Prepared world transform/position arithmetic exceeds finite Blender coordinates");
                if (primitive.TryGetProperty("targets", out _)) throw new InvalidOperationException("Rigid prepared geometry must realize morph targets before handoff");
                var accessor = primitive.TryGetProperty("indices", out var indices) ? indices.GetInt32() : positions;
                if (accessor < 0 || accessor >= accessors.GetArrayLength()) throw new InvalidOperationException("Prepared triangle accessor is invalid");
                var indexData = indices.ValueKind != JsonValueKind.Undefined ? Accessor(accessor, false) : positionData;
                var count = indexData.Count;
                if (count <= 0 || count % 3 != 0) throw new InvalidOperationException("Prepared primitive has empty/incomplete triangle discovery");
                if (indices.ValueKind != JsonValueKind.Undefined && checkedIndices.Add((accessor, positionData.Count)))
                {
                    stream.Position = indexData.Start;
                    for (long indexValue = 0; indexValue < count; indexValue++)
                    {
                        var actual = indexData.ComponentType switch { 5121 => reader.ReadByte(), 5123 => reader.ReadUInt16(), _ => reader.ReadUInt32() };
                        if (actual >= positionData.Count) throw new InvalidOperationException("Prepared primitive index exceeds actual position storage");
                        if (indexData.Stride > indexData.ElementSize) stream.Seek(indexData.Stride - indexData.ElementSize, SeekOrigin.Current);
                    }
                }
                triangles = checked(triangles + count / 3);
            }
            if (triangles == 0 || !names.TryAdd(name, triangles)) throw new InvalidOperationException("Prepared mesh names must be nonempty and unique");
            if (topologyMeshes is not null && topologyMeshes.TryGetValue(name, out var selected))
            {
                if (selected.FileNodeIndex != nodeIndex || selected.IndexedCorners != checked(triangles * 3))
                    throw new InvalidOperationException("Source topology node index/name/corner count differs from actual prepared GLB");
                matchedTopologyMeshes++;
            }
        }
        if (topologyMeshes is not null && matchedTopologyMeshes != topologyMeshes.Count)
            throw new InvalidOperationException("Source topology node selection is missing from actual prepared GLB");
        var declarations = handoff["parts"]!.AsArray();
        var expectedNames = declarations.SelectMany(p => new[] { p!["highObject"]!.GetValue<string>(), p["lowObject"]!.GetValue<string>() }).ToHashSet(StringComparer.Ordinal);
        if (!expectedNames.SetEquals(names.Keys)) throw new InvalidOperationException("Prepared GLB must exactly account for every declared HIGH/LOW mesh and no others");
        var repairs = authoring["repairs"]!.AsArray().ToDictionary(p => p!["partId"]!.GetValue<string>(), p => p!, StringComparer.Ordinal);
        if (!repairs.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(declarations.Select(p => p!["id"]!.GetValue<string>())))
            throw new InvalidOperationException("Authoring repairs must name exactly the declared parts");
        long total = 0;
        foreach (var part in declarations)
        {
            var high = names[part!["highObject"]!.GetValue<string>()];
            var low = names[part["lowObject"]!.GetValue<string>()];
            var repair = repairs[part["id"]!.GetValue<string>()];
            if (repair["highTriangles"]!.GetValue<long>() != high || repair["lowTriangles"]!.GetValue<long>() != low)
                throw new InvalidOperationException("Authoring triangle claims differ from actual prepared primitive counts");
            if (low > part["maxTriangles"]!.GetValue<long>()) throw new InvalidOperationException("Prepared LOW exceeds its explicit per-part cap");
            if (part["materialMode"]!.GetValue<string>() == "preserve" && high != low)
                throw new InvalidOperationException("Preserved part HIGH/LOW triangle counts differ; actual identity is additionally checked by Blender");
            total = checked(total + low);
        }
        if (total > lod0Limit) throw new InvalidOperationException("Prepared total LOD0 exceeds the explicit rigid geometry budget");

        PreparedAccessor Accessor(int index, bool position)
        {
            var accessor = accessors[index];
            if (accessor.TryGetProperty("sparse", out _))
                throw new InvalidOperationException("Prepared rigid inputs require dense packed accessors; sparse inputs must be explicitly prepared before finishing");
            var component = accessor.GetProperty("componentType").GetInt32();
            var type = accessor.GetProperty("type").GetString();
            if (position ? component != 5126 || type != "VEC3" : component is not (5121 or 5123 or 5125) || type != "SCALAR")
                throw new InvalidOperationException("Prepared POSITION/index component type is unsupported");
            var componentSize = component switch { 5121 => 1, 5123 => 2, _ => 4 };
            var elementSize = componentSize * (position ? 3 : 1);
            var count = accessor.GetProperty("count").GetInt64();
            var viewIndex = accessor.GetProperty("bufferView").GetInt32();
            if (viewIndex < 0 || viewIndex >= views.GetArrayLength()) throw new InvalidOperationException("Prepared accessor references an invalid buffer view");
            var view = views[viewIndex];
            var viewOffset = view.TryGetProperty("byteOffset", out var viewStart) ? viewStart.GetInt64() : 0;
            var viewLength = view.GetProperty("byteLength").GetInt64();
            var offset = accessor.TryGetProperty("byteOffset", out var start) ? start.GetInt64() : 0;
            var stride = view.TryGetProperty("byteStride", out var declaredStride) ? declaredStride.GetInt32() : elementSize;
            if (count < 1 || count > binaryLength || offset < 0 || offset > viewLength || offset % componentSize != 0
                || stride < elementSize || stride > 252 || stride % componentSize != 0
                || (count - 1) * stride + elementSize > viewLength - offset)
                throw new InvalidOperationException("Prepared accessor count/stride exceeds actual packed byte storage");
            return new(binaryStart + viewOffset + offset, count, stride, component, elementSize);
        }
    }
    readonly record struct PreparedAccessor(long Start, long Count, int Stride, int ComponentType, int ElementSize);

    static Dictionary<int, double[]> ValidatePreparedGraph(JsonElement root, JsonElement nodes)
    {
        var count = nodes.GetArrayLength();
        if (count == 0) throw new InvalidOperationException("Prepared source has no node discovery");
        var parents = Enumerable.Repeat(-1, count).ToArray();
        var children = new List<int>[count];
        var local = new double[count][];
        for (var index = 0; index < count; index++)
        {
            var node = nodes[index];
            if (node.TryGetProperty("skin", out _) || node.TryGetProperty("weights", out _))
                throw new InvalidOperationException("Rigid prepared nodes cannot select skin or morph weights");
            local[index] = PreparedNodeMatrix(node);
            children[index] = [];
            if (!node.TryGetProperty("children", out var declared)) continue;
            var seen = new HashSet<int>();
            foreach (var child in declared.EnumerateArray())
            {
                var id = child.GetInt32();
                if (id < 0 || id >= count || !seen.Add(id) || parents[id] != -1)
                    throw new InvalidOperationException("Prepared node graph has an invalid/duplicate/multiple-parent child");
                parents[id] = index;
                children[index].Add(id);
            }
        }
        // Iterative parent traversal avoids using an attacker-controlled CLR stack.
        var colors = new byte[count];
        for (var index = 0; index < count; index++)
        {
            var path = new List<int>();
            var cursor = index;
            while (cursor >= 0 && colors[cursor] == 0)
            {
                colors[cursor] = 1; path.Add(cursor); cursor = parents[cursor];
            }
            if (cursor >= 0 && colors[cursor] == 1) throw new InvalidOperationException("Prepared node graph contains a cycle");
            foreach (var id in path) colors[id] = 2;
        }
        var scenes = root.GetProperty("scenes");
        var selection = root.GetProperty("scene").GetInt32();
        if (selection < 0 || selection >= scenes.GetArrayLength()) throw new InvalidOperationException("Prepared selected scene index is invalid");
        var world = new Dictionary<int, double[]>();
        var queue = new Queue<int>();
        foreach (var item in scenes[selection].GetProperty("nodes").EnumerateArray())
        {
            var id = item.GetInt32();
            if (id < 0 || id >= count || parents[id] != -1 || !world.TryAdd(id, local[id]))
                throw new InvalidOperationException("Prepared selected scene roots must be valid unique parentless nodes");
            queue.Enqueue(id);
        }
        while (queue.TryDequeue(out var parent))
            foreach (var child in children[parent])
            {
                var matrix = new double[16];
                for (var row = 0; row < 4; row++)
                    for (var column = 0; column < 4; column++)
                    {
                        double value = 0;
                        for (var axis = 0; axis < 4; axis++) value += world[parent][row * 4 + axis] * local[child][axis * 4 + column];
                        if (!double.IsFinite(value) || Math.Abs(value) > float.MaxValue)
                            throw new InvalidOperationException("Prepared composed node transform is nonfinite/out-of-range");
                        matrix[row * 4 + column] = value;
                    }
                if (!world.TryAdd(child, matrix)) throw new InvalidOperationException("Prepared selected scene visits a node more than once");
                queue.Enqueue(child);
            }
        for (var index = 0; index < count; index++)
            if (nodes[index].TryGetProperty("mesh", out _) && !world.ContainsKey(index))
                throw new InvalidOperationException("Every prepared HIGH/LOW mesh must be reachable exactly once from the selected scene");
        return world;
    }

    static double[] PreparedNodeMatrix(JsonElement node)
    {
        double[] Read(string key, int length, double[] fallback)
        {
            if (!node.TryGetProperty(key, out var value)) return fallback;
            if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() != length)
                throw new InvalidOperationException("Prepared node transform " + key + " has invalid dimensions");
            var array = value.EnumerateArray().Select(v => v.GetDouble()).ToArray();
            if (array.Any(v => !double.IsFinite(v) || Math.Abs(v) > float.MaxValue))
                throw new InvalidOperationException("Prepared node transform is nonfinite/out-of-range");
            return array;
        }
        double[] matrix;
        if (node.TryGetProperty("matrix", out _))
        {
            if (new[] { "translation", "rotation", "scale" }.Any(key => node.TryGetProperty(key, out _)))
                throw new InvalidOperationException("Prepared node cannot mix matrix and TRS transforms");
            var columnMajor = Read("matrix", 16, []);
            matrix = new double[16];
            for (var row = 0; row < 4; row++) for (var column = 0; column < 4; column++) matrix[row * 4 + column] = columnMajor[column * 4 + row];
            if (!matrix.Skip(12).SequenceEqual(new double[] { 0, 0, 0, 1 }))
                throw new InvalidOperationException("Prepared node matrix must be affine");
        }
        else
        {
            var t = Read("translation", 3, [0, 0, 0]);
            var s = Read("scale", 3, [1, 1, 1]);
            var q = Read("rotation", 4, [0, 0, 0, 1]);
            if (s.Any(v => v == 0) || Math.Abs(q.Sum(v => v * v) - 1) > .0001)
                throw new InvalidOperationException("Prepared node requires nonsingular scale and unit quaternion rotation");
            var x = q[0]; var y = q[1]; var z = q[2]; var w = q[3];
            matrix = [
                (1-2*(y*y+z*z))*s[0], 2*(x*y-z*w)*s[1], 2*(x*z+y*w)*s[2], t[0],
                2*(x*y+z*w)*s[0], (1-2*(x*x+z*z))*s[1], 2*(y*z-x*w)*s[2], t[1],
                2*(x*z-y*w)*s[0], 2*(y*z+x*w)*s[1], (1-2*(x*x+y*y))*s[2], t[2],
                0,0,0,1];
        }
        var determinant = matrix[0]*(matrix[5]*matrix[10]-matrix[6]*matrix[9])
                          -matrix[1]*(matrix[4]*matrix[10]-matrix[6]*matrix[8])
                          +matrix[2]*(matrix[4]*matrix[9]-matrix[5]*matrix[8]);
        if (!double.IsFinite(determinant) || determinant == 0 || matrix.Any(v => !double.IsFinite(v) || Math.Abs(v)>float.MaxValue))
            throw new InvalidOperationException("Prepared node transform is singular or nonfinite/out-of-range");
        return matrix;
    }
}
