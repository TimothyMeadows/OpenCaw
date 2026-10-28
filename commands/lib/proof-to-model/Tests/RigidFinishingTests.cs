using System.Diagnostics;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class RigidFinishingTests
{
    static readonly string ZeroHash = new('0', 64);
    static JsonArray Identity => new(new JsonArray(1, 0, 0, 0), new JsonArray(0, 1, 0, 0), new JsonArray(0, 0, 1, 0), new JsonArray(0, 0, 0, 1));
    static byte[] Bytes(JsonObject value) => Encoding.UTF8.GetBytes(value.ToJsonString());
    static JsonObject Part(string id = "body") => new()
    {
        ["id"] = id, ["parentId"] = null, ["pivot"] = new JsonArray(0, 0, 0),
        ["highObject"] = id + ".HIGH", ["lowObject"] = id + ".LOW", ["maxTriangles"] = 16,
        ["maxVertexSurfaceErrorMetres"] = .0005, ["materialMode"] = "preserve", ["bakeGroup"] = null,
        ["collision"] = true, ["collisionReason"] = "SIMULATED solid fixture, not an owl/model acceptance"
    };
    static JsonObject Handoff() => new()
    {
        ["schemaVersion"] = 1, ["profile"] = "articulated", ["coordinateFrame"] = "opencaw-proof-z-up",
        ["sourceRawSha256"] = ZeroHash, ["preparedGlb"] = ".art-staging/prepared.glb", ["preparedGlbSha256"] = ZeroHash,
        ["sourceToPreparedMatrix"] = Identity, ["authoringEvidence"] = "authoring.json", ["authoringEvidenceSha256"] = ZeroHash,
        ["parts"] = new JsonArray(Part())
    };
    static JsonObject Settings() => new()
    {
        ["schemaVersion"] = 2, ["method"] = "rigid-parts", ["topologyPreparation"] = new JsonObject { ["method"] = "none" },
        ["collision"] = new JsonObject { ["method"] = "exact-hull" },
        ["rigidParts"] = new JsonObject
        {
            ["handoff"] = "handoff.json", ["handoffSha256"] = ZeroHash,
            ["reviewEvidence"] = ".opencaw/.cache/tasks/tests/reviews/rigid.json", ["reviewEvidenceSha256"] = ZeroHash,
            ["maxLod0Triangles"] = 100, ["maxGlbBytes"] = 1_000_000
        },
        ["resources"] = new JsonObject { ["maxPrivateBytes"] = 536_870_912L }
    };
    static JsonObject Authoring() => new()
    {
        ["schemaVersion"] = 1, ["kind"] = "rigid-part-authoring", ["sourceRawSha256"] = ZeroHash, ["preparedGlbSha256"] = ZeroHash,
        ["sources"] = new JsonArray(new JsonObject { ["path"] = "master.txt", ["sha256"] = ZeroHash, ["role"] = "SIMULATED test authoring master" }),
        ["repairs"] = new JsonArray(new JsonObject
        {
            ["partId"] = "body", ["sourceKind"] = "authored-detail", ["sourceDescription"] = "Synthetic octahedron fixture; no reconstruction or real asset claim",
            ["highTriangles"] = 8, ["lowTriangles"] = 8, ["intentionalChanges"] = "No change; exact copies for preserve-policy control"
        })
    };
    static JsonObject Review() => new()
    {
        ["schemaVersion"] = 1, ["kind"] = "rigid-preparation", ["decision"] = "approved", ["human"] = false,
        ["reviewer"] = "SIMULATED-technical-fixture", ["reason"] = "Application failure-contract test only, not a real reviewer or human model acceptance",
        ["sourceRawSha256"] = ZeroHash, ["preparedGlbSha256"] = ZeroHash, ["handoffSha256"] = ZeroHash, ["authoringEvidenceSha256"] = ZeroHash
    };

    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        check(FinishingSettings.Parse(Bytes(Settings()))["method"]!.GetValue<string>() == "rigid-parts", "rigid settings require explicit separate v2 method");
        await CheckCollisionFrameSettings(check, reject);
        await CheckUvAtlasSettings(check, reject);
        await CheckUvRepairSettings(check, reject);
        await CheckImportNormalAndLodSettings(check, reject);
        await CheckSourceTopologySettingsAndReceipt(check, reject);
        await CheckContactLodSettings(check, reject);
        await CheckContactLodCompleteCoverage(parent, check);
        check(RigidHandoff.Parse(Bytes(Handoff()))["parts"]!.AsArray().Count == 1, "closed rigid hierarchy parses without choosing an engine or changing the art pipeline");
        check(RigidHandoff.ParseAuthoring(Bytes(Authoring()))["repairs"]!.AsArray().Count == 1, "authored source and per-part repair records are separate from simplification quality");
        check(RigidHandoff.ParseReview(Bytes(Review()))["human"]!.GetValue<bool>() == false, "rigid technical review is explicitly not human model acceptance");
        var sharedAtlas = Handoff();
        sharedAtlas["parts"]![0]!["materialMode"] = "bake"; sharedAtlas["parts"]![0]!["bakeGroup"] = "shell";
        var atlasWing = Part("wing"); atlasWing["materialMode"] = "bake"; atlasWing["bakeGroup"] = "shell";
        sharedAtlas["parts"]!.AsArray().Add(atlasWing);
        check(RigidHandoff.Parse(Bytes(sharedAtlas))["parts"]!.AsArray().Count == 2, "exact shared bakeGroup intentionally shares one atlas across parts");
        sharedAtlas["parts"]![1]!["bakeGroup"] = "SHELL";
        await reject(() => Task.Run(() => RigidHandoff.Parse(Bytes(sharedAtlas))), "case-aliased distinct bakeGroup filenames rejected before stage admission");
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["schemaVersion"] = 1, x => x["method"] = "automatic", x => x["extra"] = true,
            x => x["quadriFlow"] = new JsonObject { ["coordinateScale"] = 1 },
            x => x["topologyPreparation"]!["method"] = "voxel-remesh", x => x.Remove("resources"),
            x => x["resources"]!["maxPrivateBytes"] = 67_108_863L, x => x["resources"]!["maxPrivateBytes"] = 68_719_476_737L,
            x => x["resources"]!["maxPrivateBytes"] = true, x => x["resources"]!["maxPrivateBytes"] = 67_108_864.5,
            x => x["rigidParts"]!["maxLod0Triangles"] = 3, x => x["rigidParts"]!["maxGlbBytes"] = 1023,
            x => x["rigidParts"]!["handoff"] = "../handoff.json", x => x["rigidParts"]!["handoff"] = "C:/handoff.json",
            x => x["rigidParts"]!["reviewEvidence"] = "NUL.json", x => x["rigidParts"]!["handoffSha256"] = ZeroHash.ToUpperInvariant().Replace('0', 'A'),
            x => x["rigidParts"]!.AsObject().Remove("reviewEvidenceSha256")
        })
        {
            var value = Settings(); change(value);
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(value))), "rigid settings unknown/fallback/unsupported resource/budget/path selection rejected");
        }
        foreach (var invalid in new[]
        {
            Settings().ToJsonString().Replace("\"schemaVersion\":2", "\"schemaVersion\":2,\"schemaVersion\":2"),
            Settings().ToJsonString().Replace("536870912", "536870912.000000000000000001"),
            Settings().ToJsonString().Replace("536870912", "1e-999999999"),
            Settings().ToJsonString().Replace("536870912", "1e999999999999999999")
        }) await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(invalid))), "rigid duplicate/exact-fraction/underflow/oversized-exponent memory choice rejected");
        var notation = Settings().ToJsonString().Replace("536870912", "5.36870912e8");
        check(FinishingSettings.Parse(Encoding.UTF8.GetBytes(notation))["resources"]!["maxPrivateBytes"]!.GetValue<long>() == 536_870_912L,
            "rigid exact integer notation normalizes without rounded memory admission");
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["profile"] = "skinned", x => x["coordinateFrame"] = "engine-default", x => x["parts"] = new JsonArray(),
            x => x["preparedGlb"] = "folder/../source.glb", x => x["preparedGlb"] = "folder\\source.glb",
            x => x["authoringEvidence"] = "aux.json", x => x["sourceRawSha256"] = "wrong", x => x["unreviewed"] = true,
            x => x["sourceToPreparedMatrix"]![3]![3] = 0, x => x["sourceToPreparedMatrix"]![0]![0] = -1,
            x => x["sourceToPreparedMatrix"]![0]![0] = 0, x => x["sourceToPreparedMatrix"]![0] = new JsonArray(1, 0),
            x => x["parts"]![0]!["parentId"] = "body", x => x["parts"]![0]!["parentId"] = "missing",
            x => x["parts"]![0]!["lowObject"] = "body.HIGH", x => x["parts"]![0]!["id"] = "unsafe/id",
            x => x["parts"]![0]!["pivot"] = new JsonArray(0, 0), x => x["parts"]![0]!["collision"] = "false",
            x => x["parts"]![0]!["collisionReason"] = " ", x => x["parts"]![0]!["maxVertexSurfaceErrorMetres"] = 0,
            x => x["parts"]![0]!["maxVertexSurfaceErrorMetres"] = 1.1, x => x["parts"]![0]!["bakeGroup"] = "implicit-skip",
            x => x["parts"]![0]!["materialMode"] = "automatic", x => x["parts"]![0]!["unknown"] = 1,
            x => x["parts"]!.AsArray().Add(Part()),
            x => { var second = Part("wing"); second["parentId"] = "body"; x["parts"]![0]!["parentId"] = "wing"; x["parts"]!.AsArray().Add(second); }
        })
        {
            var value = Handoff(); change(value);
            await reject(() => Task.Run(() => RigidHandoff.Parse(Bytes(value))), "rigid unknown/invalid hierarchy, identity, transform, budget or applicability rejected");
        }
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["human"] = true, x => x["decision"] = "pending", x => x["kind"] = "human", x => x["reviewer"] = " ",
            x => x.Remove("handoffSha256"), x => x["authoringEvidenceSha256"] = null, x => x["scope"] = "unbound"
        })
        {
            var value = Review(); change(value);
            await reject(() => Task.Run(() => RigidHandoff.ParseReview(Bytes(value))), "rigid approval cannot invent human authority or omit exact handoff/authoring binding");
        }
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["sources"] = new JsonArray(), x => x["repairs"] = new JsonArray(), x => x["sources"]![0]!["path"] = "../master.txt",
            x => x["sources"]!.AsArray().Add(x["sources"]![0]!.DeepClone()), x => x["repairs"]!.AsArray().Add(x["repairs"]![0]!.DeepClone()),
            x => x["repairs"]![0]!["sourceKind"] = "generated-high-from-low", x => x["repairs"]![0]!["highTriangles"] = 0,
            x => x["repairs"]![0]!["intentionalChanges"] = "", x => x["sources"]![0]!["sha256"] = "not-a-hash"
        })
        {
            var value = Authoring(); change(value);
            await reject(() => Task.Run(() => RigidHandoff.ParseAuthoring(Bytes(value))), "rigid authored ancestry rejects missing/duplicate/unbound/relabelled/empty descriptions");
        }
        foreach (var (name, parse, value) in new (string, Func<byte[], JsonObject>, JsonObject)[]
        {
            ("handoff",RigidHandoff.Parse,Handoff()),("review",RigidHandoff.ParseReview,Review()),("authoring",RigidHandoff.ParseAuthoring,Authoring())
        })
        {
            var duplicate = value.ToJsonString().Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1");
            await reject(() => Task.Run(() => parse(Encoding.UTF8.GetBytes(duplicate))), "rigid duplicate root rejected in " + name);
        }
        await CheckApplication(parent, check, reject);
        await CheckUvAtlasApplication(parent, check);
        await CheckUvRepairApplication(parent, check, reject);
        await CheckLodApplication(parent, check);
        await CheckCombinedSelectorApplication(parent, check);
        await CheckSourceTopologyApplication(parent, check, reject);
        await CheckContactLodApplication(parent, check, reject);
        await CheckMemoryProcess(parent, check, reject);
    }

    static JsonObject SourceTopologySelection(string receipt = ".opencaw/.cache/tasks/tests/source-topology.json", string? hash = null) => new()
    {
        ["method"] = "reviewed-source-corners-v1", ["receipt"] = receipt, ["receiptSha256"] = hash ?? ZeroHash
    };

    static JsonObject SourceTopologyReceipt(int[]? owners = null, int vertices = 6)
    {
        owners ??= [0,2,4,2,1,4,1,3,4,3,0,4,2,0,5,1,2,5,3,1,5,0,3,5];
        var bytes = new byte[owners.Length * 4];
        for (var index = 0; index < owners.Length; index++) BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(index * 4, 4), owners[index]);
        return new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "rigid-source-corner-topology", ["preparedGlbSha256"] = ZeroHash,
            ["meshes"] = new JsonArray(new JsonObject
            {
                ["node"] = "body.LOW", ["fileNodeIndex"] = 1, ["sourceVertexCount"] = vertices, ["indexedCorners"] = owners.Length,
                ["ownersI32LEHex"] = Convert.ToHexStringLower(bytes), ["ownersSha256"] = Convert.ToHexStringLower(SHA256.HashData(bytes))
            })
        };
    }

    static async Task CheckSourceTopologySettingsAndReceipt(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        check(FinishingSettings.Parse(Bytes(Settings()))["rigidParts"]!["sourceTopology"] is null,
            "absent source topology remains absent; source evidence never chooses a representation implicitly");
        var selected = Settings(); selected["rigidParts"]!["sourceTopology"] = SourceTopologySelection(); selected["rigidParts"]!["lods"] = ConstrainedLods();
        check(FinishingSettings.Parse(Bytes(selected))["rigidParts"]!["sourceTopology"]!["method"]!.GetValue<string>() == "reviewed-source-corners-v1",
            "explicit reviewed source-corner selection parses independently of native geometry acceptance");
        var noLods = Settings(); noLods["rigidParts"]!["sourceTopology"] = SourceTopologySelection();
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(noLods))), "source topology requires explicit source-preserving LOD selection rather than legacy decimation");
        foreach (var change in new Action<JsonObject>[]
        {
            value => value["method"] = "automatic", value => value.Remove("receiptSha256"), value => value["fallback"] = "weld",
            value => value["receiptSha256"] = "wrong", value => value["receiptSha256"] = new string('A',64),
            value => value["receipt"] = "../receipt.json", value => value["receipt"] = "C:/receipt.json",
            value => value["receipt"] = "folder\\receipt.json", value => value["receipt"] = "folder/../receipt.json",
            value => value["receipt"] = "NUL.json", value => value["receipt"] = "receipt.bin"
        })
        {
            var settings = selected.DeepClone().AsObject(); change(settings["rigidParts"]!["sourceTopology"]!.AsObject());
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(settings))), "source topology selector rejects unknown, missing, unbound or non-normalized selections");
        }
        foreach (var value in new JsonNode?[] { null, new JsonArray(), JsonValue.Create("reviewed-source-corners-v1"), JsonValue.Create(true) })
        {
            var settings = selected.DeepClone().AsObject(); settings["rigidParts"]!["sourceTopology"] = value;
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(settings))), "source topology selector requires its exact closed object");
        }
        var valid = SourceTopologyReceipt();
        var parsed = RigidSourceTopology.Parse(Bytes(valid));
        check(parsed.Meshes.Count == 1 && parsed.Meshes[0].SourceVertexCount == 6 && parsed.Meshes[0].IndexedCorners == 24
            && parsed.Meshes[0].FileNodeIndex == 1 && parsed.PreparedGlbSha256 == ZeroHash,
            "source topology parses real LEi32 owner bytes, verifies hash/range/complete owner coverage, and returns bounded summaries only");
        foreach (var change in new Action<JsonObject>[]
        {
            value => value["schemaVersion"] = 2, value => value["kind"] = "inferred-topology", value => value["extra"] = true,
            value => value["preparedGlbSha256"] = "wrong", value => value["meshes"] = new JsonArray(),
            value => value["meshes"] = new JsonObject(), value => value["meshes"]!.AsArray().Add(value["meshes"]![0]!.DeepClone())
        })
        {
            var receipt = valid.DeepClone().AsObject(); change(receipt);
            await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(receipt))), "source topology receipt rejects unknown/duplicate/empty header or mesh identities");
        }
        foreach (var change in new Action<JsonObject>[]
        {
            mesh => mesh["node"] = " ", mesh => mesh["node"] = new string('n',257), mesh => mesh["node"] = "bad\nnode",
            mesh => mesh["fileNodeIndex"] = -1, mesh => mesh["fileNodeIndex"] = 1_000_001, mesh => mesh["fileNodeIndex"] = true,
            mesh => mesh["sourceVertexCount"] = 0, mesh => mesh["sourceVertexCount"] = 8_000_001,
            mesh => mesh["indexedCorners"] = 0, mesh => mesh["indexedCorners"] = 25, mesh => mesh["indexedCorners"] = 16_777_217,
            mesh => mesh["ownersI32LEHex"] = "00", mesh => mesh["ownersI32LEHex"] = new string('g',192),
            mesh => mesh["ownersI32LEHex"] = false, mesh => mesh["ownersSha256"] = ZeroHash,
            mesh => mesh.Remove("ownersSha256"), mesh => mesh["positions"] = new JsonArray()
        })
        {
            var receipt = valid.DeepClone().AsObject(); change(receipt["meshes"]![0]!.AsObject());
            await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(receipt))), "source topology rejects malformed/beyond-budget mesh fields before native execution");
        }
        foreach (var owners in new[] { new[] { -1, 0, 1 }, new[] { 0, 1, 3 } })
        {
            var receipt = SourceTopologyReceipt(owners, 3);
            await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(receipt))), "source topology rejects signed-negative/out-of-range owners despite a correct decoded-byte hash");
        }
        var omitted = SourceTopologyReceipt([0,0,1],3);
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(omitted))), "source topology rejects declared owners missing from a correctly hashed field");
        var tooMany = SourceTopologyReceipt([0,1,2],4);
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(tooMany))), "source topology rejects more declared owners than actual indexed corners");
        var upper = SourceTopologyReceipt(Enumerable.Range(0,12).Concat(Enumerable.Range(0,12)).ToArray(),12);
        check(RigidSourceTopology.Parse(Bytes(upper)).Meshes[0].SourceVertexCount == 12, "source topology handles valid multi-byte hex owner digits before uppercase negative control");
        upper["meshes"]![0]!["ownersI32LEHex"] = upper["meshes"]![0]!["ownersI32LEHex"]!.GetValue<string>().ToUpperInvariant();
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(upper))), "source topology rejects uppercase owner hex even when decoded values/hash/coverage would match");
        var differentNameSameIndex = valid.DeepClone().AsObject();
        var duplicateIndex = valid["meshes"]![0]!.DeepClone(); duplicateIndex["node"] = "other.LOW";
        differentNameSameIndex["meshes"]!.AsArray().Add(duplicateIndex);
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(differentNameSameIndex))), "source topology rejects two names claiming the same file node");
        foreach (var raw in new[]
        {
            valid.ToJsonString().Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            valid.ToJsonString().Replace("\"node\":\"body.LOW\"", "\"node\":\"body.LOW\",\"node\":\"body.LOW\""),
            valid.ToJsonString().Replace("\"fileNodeIndex\":1", "\"fileNodeIndex\":1.000000000000000001"),
            valid.ToJsonString().Replace("\"sourceVertexCount\":6", "\"sourceVertexCount\":1e-999999999"),
            valid.ToJsonString().Replace("\"indexedCorners\":24", "\"indexedCorners\":24.000000000000000001"),
            valid.ToJsonString().Replace("\"indexedCorners\":24", "\"indexedCorners\":1e9999999999")
        }) await reject(() => Task.Run(() => RigidSourceTopology.Parse(Encoding.UTF8.GetBytes(raw))), "source topology rejects duplicate fields and inexact/underflow/oversized integer tokens");
        var notation = valid.ToJsonString().Replace("\"fileNodeIndex\":1", "\"fileNodeIndex\":1e0").Replace("\"indexedCorners\":24", "\"indexedCorners\":2.4e1");
        check(RigidSourceTopology.Parse(Encoding.UTF8.GetBytes(notation)).Meshes[0].IndexedCorners == 24,
            "source topology accepts exact integer notation without floating-point rounding");
        var full = valid.DeepClone().AsObject(); var entries = full["meshes"]!.AsArray(); entries.Clear();
        for (var index = 0; index < 512; index++)
        {
            var mesh = valid["meshes"]![0]!.DeepClone(); mesh["node"] = "LOW" + index; mesh["fileNodeIndex"] = index; entries.Add(mesh);
        }
        check(RigidSourceTopology.Parse(Bytes(full)).Meshes.Count == 512, "source topology accepts the explicit mesh-count ceiling");
        var extra = entries[0]!.DeepClone(); extra["node"] = "LOW-extra"; extra["fileNodeIndex"] = 512; entries.Add(extra);
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(full))), "source topology rejects more than512 mesh entries");
        await reject(() => Task.Run(() => RigidSourceTopology.Parse([])), "source topology rejects empty receipt bytes");
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(new byte[RigidSourceTopology.MaximumBytes+1])), "source topology rejects receipt bytes beyond64MiB before JSON parsing");
        var nested = valid.DeepClone().AsObject(); JsonNode depth = new JsonArray();
        for (var index = 0; index < 14; index++) depth = new JsonArray(depth);
        nested["meshes"] = depth;
        await reject(() => Task.Run(() => RigidSourceTopology.Parse(Bytes(nested))), "source topology bounds JSON depth independently of owner-field validation");
    }

    static void SaveSourceTopology(Fixture fixture, JsonObject receipt, bool reviewedSource = true)
    {
        const string path = ".opencaw/.cache/tasks/tests/source-topology.json";
        fixture.W.Save(path, receipt);
        var hash = Workspace.Hash(fixture.W.Resolve(path));
        var authoring = fixture.W.Load<JsonObject>("authoring.json");
        var sources = authoring["sources"]!.AsArray();
        var bound = sources.SingleOrDefault(source => source!["path"]!.GetValue<string>() == path);
        if (!reviewedSource) { if (bound is not null) sources.Remove(bound); }
        else if (bound is not null) bound["sha256"] = hash;
        else sources.Add(new JsonObject { ["path"] = path, ["sha256"] = hash, ["role"] = "SIMULATED source-corner authorship; no geometric or human approval" });
        fixture.W.Save("authoring.json", authoring);
        var settings = fixture.W.Load<JsonObject>("settings.json"); settings["rigidParts"]!["sourceTopology"] = SourceTopologySelection(path, hash);
        settings["rigidParts"]!["lods"] = ConstrainedLods();
        fixture.W.Save("settings.json", settings); fixture.RefreshBindings();
    }

    static async Task CheckSourceTopologyApplication(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var directory = parent.Resolve("rigid-source-topology"); Directory.CreateDirectory(directory);
        var isolated = new Workspace(directory); isolated.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        var fixture = await Fixture.Create(isolated);
        var w = fixture.W;
        const string path = ".opencaw/.cache/tasks/tests/source-topology.json";
        var receipt = SourceTopologyReceipt(); receipt["preparedGlbSha256"] = Workspace.Hash(w.Resolve(".art-staging/prepared.glb"));
        SaveSourceTopology(fixture, receipt);
        var originals = Directory.GetFiles(w.Root,"*",SearchOption.AllDirectories).ToDictionary(file => file,File.ReadAllBytes);
        void Restore() { foreach (var pair in originals) File.WriteAllBytes(pair.Key,pair.Value); }
        async Task BeforeLaunch(Action mutation, string expected, string label)
        {
            Restore(); mutation();
            var files = Directory.GetFiles(w.Root,"*",SearchOption.AllDirectories).ToDictionary(file => file,File.ReadAllBytes);
            var state = File.ReadAllBytes(w.Resolve(fixture.ManifestPath)); var history = fixture.State.History.Count;
            Exception? observed = null; try { await fixture.Run(); } catch (Exception error) { observed = error; }
            check(observed is not null && observed.Message.Contains(expected,StringComparison.OrdinalIgnoreCase), "SIMULATED source topology reaches intended admission guard: " + label);
            check(fixture.Native.Calls == 0 && fixture.State.History.Count == history && state.SequenceEqual(File.ReadAllBytes(w.Resolve(fixture.ManifestPath))),
                "SIMULATED invalid source topology spends no finish attempt and launches no tool: " + label);
            check(files.Keys.Order().SequenceEqual(Directory.GetFiles(w.Root,"*",SearchOption.AllDirectories).Order())
                && files.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))), "SIMULATED rejected source topology preserves all files and creates no artifacts: " + label);
        }
        await BeforeLaunch(() => File.Delete(w.Resolve(path)), "Missing rigid JSON", "missing selected receipt");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve(path)," "), "checksum", "changed selected receipt before admission");
        await BeforeLaunch(() => SaveSourceTopology(fixture,receipt.DeepClone().AsObject(),false), "reviewed authoring sources", "receipt omitted from reviewed authoring");
        await BeforeLaunch(() =>
        {
            var authoring = w.Load<JsonObject>("authoring.json"); authoring["sources"]![1]!["sha256"] = ZeroHash;
            w.Save("authoring.json",authoring); fixture.RefreshBindings();
        }, "reviewed authoring sources", "receipt hash differs in reviewed authoring");
        await BeforeLaunch(() =>
        {
            var authoring = w.Load<JsonObject>("authoring.json"); authoring["sources"]![1]!["path"] = path.Replace(".json",".JSON",StringComparison.Ordinal);
            w.Save("authoring.json",authoring); fixture.RefreshBindings();
        }, "reviewed authoring sources", "receipt authoring path must match exactly, even on case-insensitive filesystems");
        await BeforeLaunch(() =>
        {
            var settings = w.Load<JsonObject>("settings.json"); settings["rigidParts"]!["sourceTopology"]!["receipt"] = ".opencaw/.cache/tasks/another/source-topology.json";
            w.Save("settings.json",settings);
        }, "task", "selected receipt belongs to another task");
        foreach (var (label,change,expected) in new (string,Action<JsonObject>,string)[]
        {
            ("wrong prepared hash", value => value["preparedGlbSha256"] = ZeroHash,"prepared GLB"),
            ("HIGH selection", value => { value["meshes"]![0]!["node"] = "body.HIGH"; value["meshes"]![0]!["fileNodeIndex"] = 0; },"LOW"),
            ("unknown LOW", value => value["meshes"]![0]!["node"] = "absent.LOW","LOW"),
            ("case-aliased LOW", value => value["meshes"]![0]!["node"] = "Body.LOW","LOW"),
            ("wrong actual node index", value => value["meshes"]![0]!["fileNodeIndex"] = 0,"node index/name/corner count"),
            ("missing actual node index", value => value["meshes"]![0]!["fileNodeIndex"] = 999999,"node index/name/corner count")
        }) await BeforeLaunch(() => { var changed=receipt.DeepClone().AsObject(); change(changed); SaveSourceTopology(fixture,changed); },expected,label);
        await BeforeLaunch(() =>
        {
            var changed = SourceTopologyReceipt([0,2,4,2,1,4,1,3,4,3,0,4,2,0,5,1,2,5,3,1,5]);
            changed["preparedGlbSha256"] = receipt["preparedGlbSha256"]!.DeepClone(); SaveSourceTopology(fixture,changed);
        }, "node index/name/corner count", "actual indexed corner count differs");
        Restore();
        await fixture.Run();
        var stage = fixture.State.Stages["finish"];
        var selected = fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["sourceTopology"]!;
        var lineage = w.Load<JsonObject>(stage.Artifacts["rigidLineage"]);
        var copy = lineage["copies"]!.AsArray().Single(item => item!["source"]!.GetValue<string>() == path)!;
        var snapshot = copy["snapshot"]!.GetValue<string>();
        check(stage.Status == "complete" && fixture.Native.BoundedCalls == 2 && selected["method"]!.GetValue<string>() == "reviewed-source-corners-v1"
            && selected["receipt"]!.GetValue<string>() == path, "SIMULATED explicitly reviewed topology reaches bounded producer unchanged; no native geometry claim");
        check(stage.Inputs[path] == Workspace.Hash(w.Resolve(path)) && stage.Inputs[snapshot] == stage.Inputs[path]
            && Workspace.Hash(w.Resolve(snapshot)) == stage.Inputs[path] && copy["sha256"]!.GetValue<string>() == stage.Inputs[path],
            "SIMULATED source topology is a fingerprinted source dependency with an exact immutable lineage snapshot");
        var historyAfterFinish = fixture.State.History.Count;
        File.AppendAllText(w.Resolve(path)," ");
        await reject(() => fixture.Command("validate",false), "SIMULATED changed source topology invalidates completed finish evidence");
        check(fixture.State.History.Count == historyAfterFinish, "SIMULATED stale source topology never spends another finish attempt");

        var subsetDirectory = parent.Resolve("rigid-source-topology-subset"); Directory.CreateDirectory(subsetDirectory);
        var subsetParent = new Workspace(subsetDirectory); subsetParent.Save("recipe.json",parent.Load<JsonObject>("recipe.json"));
        var subset = await Fixture.Create(subsetParent);
        WriteGlb(subset.W.Resolve(".art-staging/prepared.glb"),extraPart:true);
        var handoff = subset.W.Load<JsonObject>("handoff.json"); handoff["parts"]!.AsArray().Add(Part("wing")); subset.W.Save("handoff.json",handoff);
        var authors = subset.W.Load<JsonObject>("authoring.json"); var wing = authors["repairs"]![0]!.DeepClone(); wing["partId"] = "wing";
        authors["repairs"]!.AsArray().Add(wing); subset.W.Save("authoring.json",authors);
        var subsetReceipt = SourceTopologyReceipt(); subsetReceipt["preparedGlbSha256"] = Workspace.Hash(subset.W.Resolve(".art-staging/prepared.glb"));
        SaveSourceTopology(subset,subsetReceipt); await subset.Run();
        check(subset.Native.LastJob!["rigidHandoff"]!["parts"]!.AsArray().Count == 2
            && RigidSourceTopology.Parse(File.ReadAllBytes(subset.W.Resolve(path))).Meshes.Count == 1,
            "SIMULATED explicit LOW subset admits the actual two-part prepared GLB without selecting topology for other LOWs");
        var legacyDirectory = parent.Resolve("rigid-source-topology-unselected"); Directory.CreateDirectory(legacyDirectory);
        var legacyParent = new Workspace(legacyDirectory); legacyParent.Save("recipe.json",parent.Load<JsonObject>("recipe.json"));
        var legacy = await Fixture.Create(legacyParent);
        var legacyReceipt = SourceTopologyReceipt(); legacyReceipt["preparedGlbSha256"] = Workspace.Hash(legacy.W.Resolve(".art-staging/prepared.glb"));
        SaveSourceTopology(legacy,legacyReceipt);
        var legacySettings = legacy.W.Load<JsonObject>("settings.json"); legacySettings["rigidParts"]!.AsObject().Remove("sourceTopology"); legacy.W.Save("settings.json",legacySettings);
        await legacy.Run();
        check(legacy.Native.LastJob!["finishingSettings"]!["rigidParts"]!["sourceTopology"] is null,
            "SIMULATED an authoring dependency alone never activates source-owned topology or changes legacy inspection");
    }

    static JsonObject RepairAtlas() => new()
    {
        ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2,
        ["triangleRepair"] = new JsonObject
        {
            ["method"] = "density-preserving-isolated-cells-v1", ["minCellPixels"] = 4, ["maxTriangles"] = 2
        }
    };

    static async Task CheckUvRepairSettings(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var selected = Settings(); selected["rigidParts"]!["uvAtlas"] = RepairAtlas();
        var parsed = FinishingSettings.Parse(Bytes(selected));
        FinishingSettings.ValidateUvAtlasRecipe(parsed, 4096);
        check(parsed["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"]!.GetValue<long>() == 2,
            "explicit density-preserving triangle repair preserves its bounded authoring selection");
        var old = Settings(); old["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2 };
        var absent = FinishingSettings.Parse(Bytes(old)); FinishingSettings.ValidateUvAtlasRecipe(absent, 96);
        check(absent["rigidParts"]!["uvAtlas"]!["triangleRepair"] is null, "omitted UV repair remains absent and keeps legacy recipe admission");
        foreach (var mutate in new Action<JsonObject>[]
        {
            r => r["method"] = "automatic", r => r["minCellPixels"] = 8, r => r["minCellPixels"] = true,
            r => r["minCellPixels"] = 4.01, r => r["maxTriangles"] = 0, r => r["maxTriangles"] = 16385,
            r => r["maxTriangles"] = 2.5, r => r["maxTriangles"] = true,
            r => r.Remove("maxTriangles"), r => r["epsilon"] = .001
        })
        {
            var value = selected.DeepClone().AsObject(); mutate(value["rigidParts"]!["uvAtlas"]!["triangleRepair"]!.AsObject());
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(value))), "UV repair rejects unbounded, implicit, fractional or unsupported settings");
        }
        foreach (var size in new[] { 0.0, 96, 8193, 16384, 4096.5, double.PositiveInfinity, double.NaN })
            await reject(() => Task.Run(() => FinishingSettings.ValidateUvAtlasRecipe(parsed, size)), "selected UV repair rejects incompatible recipe before a native call");
        foreach (var size in new[] { 32.0, 4096, 8192 }) FinishingSettings.ValidateUvAtlasRecipe(parsed, size);
        foreach (var token in new[] { "4.0", "4e0" })
        {
            var text = selected.ToJsonString().Replace("\"minCellPixels\":4", "\"minCellPixels\":" + token);
            check(FinishingSettings.Parse(Encoding.UTF8.GetBytes(text))["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["minCellPixels"]!.GetValue<long>() == 4,
                "UV repair exact integer syntax normalizes without losing the selection");
        }
        foreach (var token in new[] { "4.000000000000000001", "true", "1e99999999" })
        {
            var text = selected.ToJsonString().Replace("\"minCellPixels\":4", "\"minCellPixels\":" + token);
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(text))), "UV repair rejects rounded fractional residues and oversized numeric tokens");
        }
        foreach (var limit in new[] { 1, 16384 })
        {
            var boundary = selected.DeepClone().AsObject(); boundary["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"] = limit;
            check(FinishingSettings.Parse(Bytes(boundary))["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"]!.GetValue<long>() == limit,
                "triangle repair normalizes both explicit triangle-count boundaries");
        }
        foreach (var token in new[] { "16384.0", "1.6384e4" })
        {
            var raw = selected.ToJsonString().Replace("\"maxTriangles\":2", "\"maxTriangles\":" + token);
            check(FinishingSettings.Parse(Encoding.UTF8.GetBytes(raw))["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"]!.GetValue<long>() == 16384,
                "triangle repair exact cap notation normalizes to an integer");
        }
        foreach (var token in new[] { "2.000000000000000001", "1.999999999999999999", "16384.000000000000001" })
        {
            var raw = selected.ToJsonString().Replace("\"maxTriangles\":2", "\"maxTriangles\":" + token);
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(raw))), "triangle repair rejects rounded budget residues");
        }
        foreach (var malformed in new JsonNode?[] { null, new JsonArray(), JsonValue.Create(true), JsonValue.Create("density-preserving-isolated-cells-v1") })
        {
            var bad = selected.DeepClone().AsObject(); bad["rigidParts"]!["uvAtlas"]!["triangleRepair"] = malformed;
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(bad))), "triangle repair requires an explicit closed object");
        }
        var oldAlias = selected.DeepClone().AsObject(); var aliasAtlas = oldAlias["rigidParts"]!["uvAtlas"]!.AsObject();
        var oldRepair = aliasAtlas["triangleRepair"]!.DeepClone(); aliasAtlas.Remove("triangleRepair"); aliasAtlas["degenerateTriangles"] = oldRepair;
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(oldAlias))), "unshipped degenerateTriangles alias is not an alternate selector");
        var oldCell = selected.DeepClone().AsObject(); var cellObject = oldCell["rigidParts"]!["uvAtlas"]!["triangleRepair"]!.AsObject();
        cellObject.Remove("minCellPixels"); cellObject["cellPixels"] = 4;
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(oldCell))), "unshipped cellPixels alias is rejected");
        foreach (var field in new[] { "method", "minCellPixels" })
        {
            var fieldValue = field == "method" ? "\"method\":\"density-preserving-isolated-cells-v1\"" : "\"minCellPixels\":4";
            var raw = selected.ToJsonString().Replace(fieldValue, fieldValue + "," + fieldValue);
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(raw))), "triangle repair rejects duplicate " + field);
        }
        var duplicate = selected.ToJsonString().Replace("\"maxTriangles\":2", "\"maxTriangles\":2,\"maxTriangles\":2");
        await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(duplicate))), "UV repair rejects duplicate nested declarations");
    }

    static async Task CheckUvRepairApplication(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        foreach (var invalidRecipe in new[] { false, true })
        {
            var root = parent.Resolve(invalidRecipe ? "rigid-uv-repair-invalid" : "rigid-uv-repair-positive"); Directory.CreateDirectory(root);
            var separate = new Workspace(root); separate.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
            var fixture = await Fixture.Create(separate);
            var value = fixture.W.Load<JsonObject>("settings.json"); value["rigidParts"]!["uvAtlas"] = RepairAtlas(); fixture.W.Save("settings.json", value);
            if (invalidRecipe)
            {
                var recipe = fixture.W.Load<JsonObject>("recipe.json"); recipe["textureSize"] = 96; fixture.W.Save("recipe.json", recipe);
                var before = File.ReadAllBytes(fixture.W.Resolve(fixture.Options["manifest"]));
                var filesBefore = Directory.GetFiles(fixture.W.Root, "*", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
                await reject(fixture.Run, "SIMULATED incompatible UV repair texture blocks before stage allocation");
                check(fixture.Native.Calls == 0 && before.SequenceEqual(File.ReadAllBytes(fixture.W.Resolve(fixture.Options["manifest"]))),
                    "SIMULATED incompatible UV repair consumes no attempt, native call or history write");
                check(filesBefore.Keys.Order().SequenceEqual(Directory.GetFiles(fixture.W.Root, "*", SearchOption.AllDirectories).Order())
                    && filesBefore.All(item => item.Value.SequenceEqual(File.ReadAllBytes(item.Key))),
                    "SIMULATED incompatible triangle repair creates no stage/log/artifact and preserves every input byte");
            }
            else
            {
                value["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"] = 16384;
                value["rigidParts"]!["importNormals"] = new JsonObject { ["method"] = "stored-corner-fan-v1" };
                value["rigidParts"]!["lods"] = new JsonObject { ["method"] = "original-component-finite-collapse-v1", ["maxVertexSurfaceErrorMetres"] = new JsonArray(.003, .01) };
                fixture.W.Save("settings.json", value);
                await fixture.Run();
                check(fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["method"]!.GetValue<string>() == "density-preserving-isolated-cells-v1",
                    "SIMULATED explicit UV repair reaches the producer without implying real UV or visual correctness");
                check(fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["uvAtlas"]!["triangleRepair"]!["maxTriangles"]!.GetValue<long>() == 16384
                    && fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["importNormals"]!["method"]!.GetValue<string>() == "stored-corner-fan-v1"
                    && fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["lods"]!["maxVertexSurfaceErrorMetres"]!.AsArray().Count == 2,
                    "SIMULATED maximum triangle-repair budget and normal/LOD selectors coexist in the actual Pipeline job");
            }
        }
    }

    static JsonObject ConstrainedLods() => new()
    {
        ["method"] = "original-component-finite-collapse-v1",
        ["maxVertexSurfaceErrorMetres"] = new JsonArray(.003, .01)
    };

    static async Task CheckImportNormalAndLodSettings(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var omitted = FinishingSettings.Parse(Bytes(Settings()));
        check(omitted["rigidParts"]!["importNormals"] is null && omitted["rigidParts"]!["lods"] is null,
            "omitted normal/LOD selectors remain absent without defaults or changing the legacy profile");
        var normals = Settings(); normals["rigidParts"]!["importNormals"] = new JsonObject { ["method"] = "stored-corner-fan-v1" };
        check(FinishingSettings.Parse(Bytes(normals))["rigidParts"]!["importNormals"]!["method"]!.GetValue<string>() == "stored-corner-fan-v1",
            "explicit closed normal selector preserves its versioned method");
        foreach (var value in new JsonNode?[] { null, JsonValue.Create(false), JsonValue.Create(1), JsonValue.Create("stored-corner-fan-v1"), new JsonArray(),
            new JsonObject(), new JsonObject { ["method"] = "automatic" }, new JsonObject { ["method"] = "STORED-CORNER-FAN-V1" },
            new JsonObject { ["method"] = true }, new JsonObject { ["method"] = "stored-corner-fan-v1", ["fallback"] = "geometric" } })
        {
            var candidate = Settings(); candidate["rigidParts"]!["importNormals"] = value?.DeepClone();
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(candidate))), "closed importNormals rejects null, wrong types, unknown methods/fields and fallback");
        }
        foreach (var duplicate in new[] { "\"method\":\"stored-corner-fan-v1\"", "\"importNormals\":{\"method\":\"stored-corner-fan-v1\"}" })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(normals.ToJsonString().Replace(duplicate, duplicate + "," + duplicate)))),
                "duplicate normal selector/object fields reject before normalized cloning");

        var selected = Settings(); selected["rigidParts"]!["lods"] = ConstrainedLods();
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["lods"] = null, x => x["lods"] = true, x => x["lods"] = "original-component-finite-collapse-v1",
            x => x["lods"] = new JsonArray(), x => x["lods"] = new JsonObject(),
            x => x["lods"]!["method"] = "collapse", x => x["lods"]!["method"] = true,
            x => x["lods"]!.AsObject().Remove("method"), x => x["lods"]!.AsObject().Remove("maxVertexSurfaceErrorMetres"),
            x => x["lods"]!["requestedRatio"] = .5, x => x["lods"]!["fallback"] = "legacy",
            x => x["lods"]!["maxVertexSurfaceErrorMetres"] = .003,
            x => x["lods"]!["maxVertexSurfaceErrorMetres"] = new JsonArray(),
            x => x["lods"]!["maxVertexSurfaceErrorMetres"] = new JsonArray(.003,.01,.02,.03,.04,.05,.06,.07,.08),
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = null,
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = true,
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = ".003",
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = new JsonObject(),
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = 0,
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = -.001,
            x => x["lods"]!["maxVertexSurfaceErrorMetres"]![0] = 1.01
        })
        {
            var candidate = selected.DeepClone().AsObject(); change(candidate["rigidParts"]!.AsObject());
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(candidate))),
                "closed constrained LOD selection rejects malformed fields/types/level counts/errors without implicit ratios or fallback");
        }
        foreach (var token in new[] { "NaN", "Infinity", "1e9999999", "1e-9999999" })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(selected.ToJsonString().Replace("0.003", token)))),
                "LOD world-metre errors reject nonfinite and underflow numeric tokens");
        foreach (var duplicate in new[] { "\"method\":\"original-component-finite-collapse-v1\"", "\"maxVertexSurfaceErrorMetres\":[0.003,0.01]",
            "\"lods\":{\"method\":\"original-component-finite-collapse-v1\",\"maxVertexSurfaceErrorMetres\":[0.003,0.01]}" })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(selected.ToJsonString().Replace(duplicate, duplicate + "," + duplicate)))),
                "duplicate LOD selector/error fields reject before normalized cloning");
        var boundary = Settings(); boundary["rigidParts"]!["lods"] = new JsonObject
        { ["method"] = "original-component-finite-collapse-v1", ["maxVertexSurfaceErrorMetres"] = new JsonArray(.001,.002,.003,.004,.005,.006,.007,1.0) };
        var parsedBoundary = FinishingSettings.Parse(Bytes(boundary)); FinishingSettings.ValidateLodRecipe(parsedBoundary, 8);
        check(parsedBoundary["rigidParts"]!["lods"]!["maxVertexSurfaceErrorMetres"]!.AsArray().Count == 8,
            "explicit eight-level and one-metre upper boundaries remain admissible with matching authoritative recipe count");
        var parsed = FinishingSettings.Parse(Bytes(selected)); FinishingSettings.ValidateLodRecipe(parsed, 2);
        foreach (var count in new[] { 0, 1, 3, 9 })
            await reject(() => Task.Run(() => FinishingSettings.ValidateLodRecipe(parsed, count)),
                "selected LOD error count must exactly match the authoritative finite recipe level count");
        FinishingSettings.ValidateLodRecipe(omitted, 0);
        selected["rigidParts"]!["importNormals"] = new JsonObject { ["method"] = "stored-corner-fan-v1" };
        selected["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2 };
        var combined = FinishingSettings.Parse(Bytes(selected));
        FinishingSettings.ValidateLodRecipe(combined, 2); FinishingSettings.ValidateUvAtlasRecipe(combined, 64);
        check(combined["rigidParts"]!["lods"] is JsonObject && combined["rigidParts"]!["importNormals"] is JsonObject
            && combined["rigidParts"]!["uvAtlas"] is JsonObject, "explicit normal/LOD/UV selectors coexist without selecting defaults");
    }

    static async Task CheckLodApplication(Workspace parent, Action<bool, string> check)
    {
        foreach (var count in new[] { 1, 3 })
        {
            var directory = parent.Resolve("rigid-lod-count-" + count); Directory.CreateDirectory(directory);
            var isolated = new Workspace(directory); isolated.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
            var fixture = await Fixture.Create(isolated);
            var settings = fixture.W.Load<JsonObject>("settings.json");
            var errors = new JsonArray(); for (var index = 0; index < count; index++) errors.Add(.003 + index * .001);
            settings["rigidParts"]!["lods"] = new JsonObject { ["method"] = "original-component-finite-collapse-v1", ["maxVertexSurfaceErrorMetres"] = errors };
            fixture.W.Save("settings.json", settings);
            var history = fixture.State.History.Count;
            var manifest = File.ReadAllBytes(fixture.W.Resolve(fixture.ManifestPath));
            var files = Directory.GetFiles(fixture.W.Root, "*", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
            Exception? observed = null;
            try { await fixture.Run(); } catch (Exception error) { observed = error; }
            check(observed is not null && observed.Message.Contains("match the authoritative recipe.lodRatios count", StringComparison.Ordinal),
                "SIMULATED selected LOD count mismatch reaches the intended recipe guard before stage allocation: " + count);
            check(fixture.Native.Calls == 0 && fixture.State.History.Count == history
                && manifest.SequenceEqual(File.ReadAllBytes(fixture.W.Resolve(fixture.ManifestPath))),
                "SIMULATED LOD count mismatch starts no native probe/producer, stage/history or spent finish attempt");
            check(files.Keys.Order().SequenceEqual(Directory.GetFiles(fixture.W.Root, "*", SearchOption.AllDirectories).Order())
                && files.All(item => item.Value.SequenceEqual(File.ReadAllBytes(item.Key))),
                "SIMULATED LOD count mismatch creates no log/artifact and preserves all raw settings/recipe/dependency bytes");
        }
    }

    static async Task CheckCombinedSelectorApplication(Workspace parent, Action<bool, string> check)
    {
        var positiveRoot = parent.Resolve("rigid-lod-compatible"); Directory.CreateDirectory(positiveRoot);
        var positiveParent = new Workspace(positiveRoot); positiveParent.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        var positive = await Fixture.Create(positiveParent);
        var selected = positive.W.Load<JsonObject>("settings.json");
        selected["rigidParts"]!["lods"] = ConstrainedLods();
        selected["rigidParts"]!["importNormals"] = new JsonObject { ["method"] = "stored-corner-fan-v1" };
        selected["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2 };
        positive.W.Save("settings.json", selected);
        var rawSettings = File.ReadAllBytes(positive.W.Resolve("settings.json"));
        var rawRecipe = File.ReadAllBytes(positive.W.Resolve("recipe.json"));
        await positive.Run();
        var sent = positive.Native.LastJob!["finishingSettings"]!["rigidParts"]!;
        check(positive.Native.Calls == 2 && sent["lods"]!["maxVertexSurfaceErrorMetres"]!.AsArray().Count == 2
            && sent["importNormals"]!["method"]!.GetValue<string>() == "stored-corner-fan-v1"
            && sent["uvAtlas"]!["islandMarginPixels"]!.GetValue<long>() == 2,
            "SIMULATED compatible closed normal/LOD/UV selections reach the bounded producer together; no native geometry claim");
        check(rawSettings.SequenceEqual(File.ReadAllBytes(positive.W.Resolve("settings.json")))
            && rawRecipe.SequenceEqual(File.ReadAllBytes(positive.W.Resolve("recipe.json"))),
            "SIMULATED explicit selectors preserve original settings/recipe bytes and reconstruction ancestry");
    }

    static async Task CheckContactLodSettings(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var selected = Settings();
        selected["rigidParts"]!["sourceTopology"] = SourceTopologySelection();
        selected["rigidParts"]!["lods"] = ConstrainedLods();
        var oldLods = selected["rigidParts"]!["lods"]!.ToJsonString();
        var omitted = FinishingSettings.Parse(Bytes(selected));
        check(omitted["rigidParts"]!["lods"]!["contactPolicy"] is null
            && omitted["rigidParts"]!["lods"]!.ToJsonString() == oldLods,
            "omitted contact policy leaves the complete existing constrained LOD object unchanged, including source-owned mode");
        selected["rigidParts"]!["lods"]!["contactPolicy"] = "protected-contact-rings-v1";
        var parsed = FinishingSettings.Parse(Bytes(selected));
        check(parsed["rigidParts"]!["lods"]!["contactPolicy"]!.GetValue<string>() == "protected-contact-rings-v1"
            && parsed["rigidParts"]!["sourceTopology"]!["method"]!.GetValue<string>() == "reviewed-source-corners-v1",
            "explicit contact policy and reviewed owner selector survive parsing without selecting an engine or replacement LOD method");
        FinishingSettings.ValidateLodRecipe(parsed, 2);
        await reject(() => Task.Run(() => FinishingSettings.ValidateLodRecipe(parsed, 1)),
            "contact policy cannot change the authoritative recipe LOD count");
        foreach (var value in new JsonNode?[] { null, JsonValue.Create(false), JsonValue.Create(1), JsonValue.Create(""),
            JsonValue.Create("automatic"), JsonValue.Create("PROTECTED-CONTACT-RINGS-V1"), new JsonArray(), new JsonObject() })
        {
            var candidate = selected.DeepClone().AsObject(); candidate["rigidParts"]!["lods"]!["contactPolicy"] = value?.DeepClone();
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(candidate))),
                "contact policy rejects null, wrong types, empty or unknown choices before normalized cloning");
        }
        foreach (var change in new Action<JsonObject>[]
        {
            p => p.Remove("sourceTopology"), p => p["sourceTopology"] = null,
            p => p["sourceTopology"]!["method"] = "coordinate-weld",
            p => p["sourceTopology"]!.AsObject().Remove("receiptSha256"),
            p => p["lods"]!["contactRingWidth"] = .001, p => p["lods"]!["fallback"] = "retain",
            p => p["lods"]!["method"] = "legacy-decimate"
        })
        {
            var candidate = selected.DeepClone().AsObject(); change(candidate["rigidParts"]!.AsObject());
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(candidate))),
                "contact policy requires its existing valid owner contract and accepts no extra numeric policy, fallback or replacement method");
        }
        const string property = "\"contactPolicy\":\"protected-contact-rings-v1\"";
        var lodProperty = "\"lods\":" + selected["rigidParts"]!["lods"]!.ToJsonString();
        foreach (var duplicate in new[] { property, lodProperty })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(selected.ToJsonString().Replace(duplicate, duplicate + "," + duplicate)))),
                "duplicate contact policy or LOD object is rejected before producer/tool admission");
        check(parsed["rigidParts"]!["lods"]!["maxVertexSurfaceErrorMetres"]!.ToJsonString() == ConstrainedLods()["maxVertexSurfaceErrorMetres"]!.ToJsonString()
            && parsed["rigidParts"]!["maxLod0Triangles"]!.GetValue<long>() == 100
            && parsed["rigidParts"]!["maxGlbBytes"]!.GetValue<long>() == 1_000_000,
            "contact policy preserves declared per-level errors and existing asset budgets");
    }

    static async Task CheckContactLodCompleteCoverage(Workspace parent, Action<bool, string> check)
    {
        var directory = parent.Resolve("rigid-contact-lod-incomplete-owner"); Directory.CreateDirectory(directory);
        var isolated = new Workspace(directory); isolated.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        var fixture = await Fixture.Create(isolated); var w = fixture.W;
        WriteGlb(w.Resolve(".art-staging/prepared.glb"), extraPart: true);
        var handoff = w.Load<JsonObject>("handoff.json"); handoff["parts"]!.AsArray().Add(Part("wing")); w.Save("handoff.json", handoff);
        var authoring = w.Load<JsonObject>("authoring.json"); var wing = authoring["repairs"]![0]!.DeepClone(); wing["partId"] = "wing";
        authoring["repairs"]!.AsArray().Add(wing); w.Save("authoring.json", authoring);
        var receipt = SourceTopologyReceipt(); receipt["preparedGlbSha256"] = Workspace.Hash(w.Resolve(".art-staging/prepared.glb"));
        SaveSourceTopology(fixture, receipt);
        var settings = w.Load<JsonObject>("settings.json"); settings["rigidParts"]!["lods"]!["contactPolicy"] = "protected-contact-rings-v1"; w.Save("settings.json", settings);
        var before = Directory.GetFiles(w.Root, "*", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
        var history = fixture.State.History.Count;
        Exception? observed = null; try { await fixture.Run(); } catch (Exception error) { observed = error; }
        check(observed is not null && observed.Message.Contains("every declared LOW mesh before native launch", StringComparison.Ordinal),
            "SIMULATED global contact policy rejects a valid partial owner receipt at the intended complete-coverage gate");
        check(fixture.Native.Calls == 0 && fixture.State.History.Count == history
            && before.Keys.Order().SequenceEqual(Directory.GetFiles(w.Root, "*", SearchOption.AllDirectories).Order())
            && before.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
            "SIMULATED incomplete contact coverage consumes no attempt, launches no doctor/producer and changes no files");
        settings["rigidParts"]!["lods"]!.AsObject().Remove("contactPolicy"); w.Save("settings.json", settings);
        await fixture.Run();
        check(fixture.Native.BoundedCalls == 2 && fixture.Native.LastJob!["rigidHandoff"]!["parts"]!.AsArray().Count == 2
            && fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["lods"]?["contactPolicy"] is null,
            "SIMULATED omitted contact policy retains legacy two-part admission with the same valid one-LOW receipt");
    }

    static async Task CheckContactLodApplication(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var directory = parent.Resolve("rigid-contact-lod"); Directory.CreateDirectory(directory);
        var isolated = new Workspace(directory); isolated.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        var fixture = await Fixture.Create(isolated); var w = fixture.W;
        var receipt = SourceTopologyReceipt(); receipt["preparedGlbSha256"] = Workspace.Hash(w.Resolve(".art-staging/prepared.glb"));
        SaveSourceTopology(fixture, receipt);
        var selected = w.Load<JsonObject>("settings.json"); selected["rigidParts"]!["lods"]!["contactPolicy"] = "protected-contact-rings-v1";
        w.Save("settings.json", selected);
        var acceptedSettings = File.ReadAllBytes(w.Resolve("settings.json"));
        foreach (var (change, expected) in new (Action<JsonObject>, string)[]
        {
            (p => p.Remove("sourceTopology"), "contactPolicy requires explicitly reviewed sourceTopology"),
            (p => p["sourceTopology"]!["receipt"] = ".opencaw/.cache/tasks/tests/missing.json", "Missing rigid JSON"),
            (p => p["sourceTopology"]!["method"] = "coordinate-weld", "sourceTopology must explicitly select"),
            (p => p["lods"]!["contactPolicy"] = false, "contactPolicy must explicitly select"),
            (p => p["lods"]!["contactRingWidth"] = .001, "Unknown or duplicate rigidParts.lods")
        })
        {
            var invalid = selected.DeepClone().AsObject(); change(invalid["rigidParts"]!.AsObject()); w.Save("settings.json", invalid);
            var files = Directory.GetFiles(w.Root,"*",SearchOption.AllDirectories).ToDictionary(path => path,File.ReadAllBytes);
            var state = File.ReadAllBytes(w.Resolve(fixture.ManifestPath)); var history = fixture.State.History.Count;
            Exception? observed = null; try { await fixture.Run(); } catch (Exception error) { observed = error; }
            check(observed is not null && observed.Message.Contains(expected, StringComparison.OrdinalIgnoreCase),
                "SIMULATED invalid contact policy reaches its intended admission guard: " + expected);
            check(fixture.Native.Calls == 0 && fixture.State.History.Count == history
                && state.SequenceEqual(File.ReadAllBytes(w.Resolve(fixture.ManifestPath))),
                "SIMULATED invalid contact policy launches no doctor/producer and consumes no attempt or manifest history");
            check(files.Keys.Order().SequenceEqual(Directory.GetFiles(w.Root,"*",SearchOption.AllDirectories).Order())
                && files.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
                "SIMULATED invalid contact admission preserves all input bytes and creates no artifacts");
            File.WriteAllBytes(w.Resolve("settings.json"), acceptedSettings);
        }
        var recipe = File.ReadAllBytes(w.Resolve("recipe.json"));
        await fixture.Run();
        var stage = fixture.State.Stages["finish"];
        var sent = fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!;
        var snapshot = w.Load<JsonObject>(stage.Artifacts["finishingSettings"]);
        check(fixture.Native.BoundedCalls == 2 && sent["lods"]!["contactPolicy"]!.GetValue<string>() == "protected-contact-rings-v1"
            && snapshot["rigidParts"]!["lods"]!["contactPolicy"]!.GetValue<string>() == "protected-contact-rings-v1"
            && sent["sourceTopology"]!["method"]!.GetValue<string>() == "reviewed-source-corners-v1",
            "SIMULATED reviewed contact selector reaches bounded producer and immutable settings snapshot without implying native LOD quality");
        check(stage.Inputs["settings.json"] == Workspace.Hash(w.Resolve("settings.json"))
            && recipe.SequenceEqual(File.ReadAllBytes(w.Resolve("recipe.json")))
            && acceptedSettings.SequenceEqual(File.ReadAllBytes(w.Resolve("settings.json"))),
            "SIMULATED contact selection remains a fingerprinted input and leaves recipe-owned ratios/budgets/settings untouched");
        var after = fixture.State.History.Count;
        selected["rigidParts"]!["lods"]!.AsObject().Remove("contactPolicy"); w.Save("settings.json", selected);
        await reject(() => fixture.Command("validate", false), "SIMULATED changing selected contact policy invalidates completed finish evidence");
        check(fixture.State.History.Count == after, "SIMULATED stale contact policy never spends an additional attempt");
    }

    static async Task CheckCollisionFrameSettings(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var selected = Settings();
        selected["collision"] = new JsonObject { ["method"] = "kdop-26", ["padding"] = .0005, ["maxVolumeRatio"] = 2 };
        check(FinishingSettings.Parse(Bytes(selected))["collision"]!["frame"] is null,
            "absent rigid collision frame remains absent without implicitly selecting PCA");
        foreach (var frame in new[] { "world", "principal-axes-v1" })
        {
            var value = selected.DeepClone().AsObject(); value["collision"]!["frame"] = frame;
            check(FinishingSettings.Parse(Bytes(value))["collision"]!["frame"]!.GetValue<string>() == frame,
                "explicit rigid support frame preserves the selected world or principal basis");
        }
        foreach (var frame in new JsonNode?[]
        {
            null, JsonValue.Create(true), JsonValue.Create(1), new JsonArray("world"), new JsonObject(),
            JsonValue.Create(""), JsonValue.Create("WORLD"), JsonValue.Create("pca"),
            JsonValue.Create("principal-axes-v2"), JsonValue.Create("world ")
        })
        {
            var value = selected.DeepClone().AsObject(); value["collision"]!["frame"] = frame;
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(value))),
                "rigid collision rejects unknown or wrongly typed orientation without fallback");
        }
        var exact = Settings(); exact["collision"]!["frame"] = "world";
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(exact))), "exact hull cannot acquire an unused support frame");
        var fallback = selected.DeepClone().AsObject(); fallback["collision"]!["fallback"] = "principal-axes-v1";
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(fallback))), "collision cannot select an implicit orientation fallback");
        selected["collision"]!["frame"] = "world";
        var duplicate = selected.ToJsonString().Replace("\"frame\":\"world\"", "\"frame\":\"world\",\"frame\":\"principal-axes-v1\"");
        await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(duplicate))), "duplicate collision frame is rejected before launch");
        var legacy = new JsonObject
        {
            ["schemaVersion"] = 1, ["topologyPreparation"] = new JsonObject { ["method"] = "none" },
            ["collision"] = new JsonObject { ["method"] = "kdop-26", ["padding"] = .0005, ["maxVolumeRatio"] = 2 }
        };
        check(FinishingSettings.Parse(Bytes(legacy))["schemaVersion"]!.GetValue<int>() == 1, "legacy collision settings remain unchanged");
        legacy["collision"]!["frame"] = "principal-axes-v1";
        await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(legacy))), "principal orientation is explicitly scoped to rigid v2");
    }

    static async Task CheckUvAtlasSettings(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        check(FinishingSettings.Parse(Bytes(Settings()))["rigidParts"]!["uvAtlas"] is null, "absent rigid UV override remains absent without adding defaults");
        var selected = Settings();
        selected["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2 };
        foreach (var exact in new[] { "1", "64", "2.0", "2e0", "200e-2", "0.2e1" })
        {
            var json = selected.ToJsonString().Replace("\"islandMarginPixels\":2", "\"islandMarginPixels\":" + exact);
            var parsed = FinishingSettings.Parse(Encoding.UTF8.GetBytes(json));
            var pixels = parsed["rigidParts"]!["uvAtlas"]!["islandMarginPixels"]!.GetValue<long>();
            FinishingSettings.ValidateUvAtlasRecipe(parsed, pixels * 8);
            check(pixels is >= 1 and <= 64, "explicit pixel margin exact integer notation normalizes and admits the exact textureSize/8 boundary: " + exact);
        }
        foreach (var change in new Action<JsonObject>[]
        {
            x => x["uvAtlas"] = null, x => x["uvAtlas"] = new JsonArray(), x => x["uvAtlas"] = new JsonObject(),
            x => x["uvAtlas"]!["method"] = "automatic", x => x["uvAtlas"]!["extra"] = true,
            x => x["uvAtlas"]!.AsObject().Remove("method"), x => x["uvAtlas"]!.AsObject().Remove("islandMarginPixels"),
            x => x["uvAtlas"]!["islandMarginPixels"] = true, x => x["uvAtlas"]!["islandMarginPixels"] = "2",
            x => x["uvAtlas"]!["islandMarginPixels"] = 0, x => x["uvAtlas"]!["islandMarginPixels"] = 65,
            x => x["uvAtlas"]!["islandMarginPixels"] = 2.5
        })
        {
            var value = selected.DeepClone().AsObject(); change(value["rigidParts"]!.AsObject());
            await reject(() => Task.Run(() => FinishingSettings.Parse(Bytes(value))), "closed explicit UV atlas rejects malformed, incomplete or out-of-range choices");
        }
        foreach (var token in new[] { "2.00000000000000000001", "200000000000000000001e-20", "1e-999999999", "1e999999999999", "NaN", "Infinity" })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(selected.ToJsonString().Replace("\"islandMarginPixels\":2", "\"islandMarginPixels\":" + token)))), "pixel margin rejects nonfinite, rounded fractions and extreme integer notation");
        foreach (var duplicate in new[] { "\"method\":\"smart-project-pixels\"", "\"islandMarginPixels\":2" })
            await reject(() => Task.Run(() => FinishingSettings.Parse(Encoding.UTF8.GetBytes(selected.ToJsonString().Replace(duplicate, duplicate + "," + duplicate)))), "duplicate UV atlas fields rejected before normalized cloning");
        foreach (var size in new[] { 15.0, 0, double.PositiveInfinity, double.NaN })
            await reject(() => Task.Run(() => FinishingSettings.ValidateUvAtlasRecipe(FinishingSettings.Parse(Bytes(selected)), size)), "pixel margin requires compatible finite recipe textureSize");
        FinishingSettings.ValidateUvAtlasRecipe(FinishingSettings.Parse(Bytes(Settings())), 1);
        check(true, "absent UV override imposes no new recipe compatibility rule");
    }

    static async Task CheckUvAtlasApplication(Workspace parent, Action<bool, string> check)
    {
        var root = parent.Resolve("rigid-uv-atlas"); Directory.CreateDirectory(root);
        var separate = new Workspace(root); separate.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        var fixture = await Fixture.Create(separate);
        var recipe = File.ReadAllBytes(fixture.W.Resolve("recipe.json"));
        var value = fixture.W.Load<JsonObject>("settings.json");
        value["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 2 };
        var text = value.ToJsonString().Replace("\"islandMarginPixels\":2", "\"islandMarginPixels\":2.0");
        File.WriteAllText(fixture.W.Resolve("settings.json"), text);
        var original = File.ReadAllBytes(fixture.W.Resolve("settings.json"));
        await fixture.Run();
        check(fixture.Native.LastJob!["finishingSettings"]!["rigidParts"]!["uvAtlas"]!["islandMarginPixels"]!.GetValue<long>() == 2,
            "SIMULATED known-compatible UV atlas selection reaches the producer in normalized settings");
        var stage = fixture.State.Stages["finish"];
        check(stage.Inputs["settings.json"] == fixture.W.HashFile(fixture.W.Resolve("settings.json"))
            && original.SequenceEqual(File.ReadAllBytes(fixture.W.Resolve("settings.json")))
            && recipe.SequenceEqual(File.ReadAllBytes(fixture.W.Resolve("recipe.json"))),
            "SIMULATED pixel selection binds unchanged raw settings and recipe bytes while cloning normalized producer values");
    }

    public static int ObserveAllocation(string[] args)
    {
        // Actual unmanaged committed allocations inside the explicitly owned job.
        // Each helper is bounded to <=512MiB requested; no GPU/native asset work.
        var buffers = new List<IntPtr>();
        try
        {
            if (args[0] == "--rigid-memory-parent")
            {
                var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
                start.ArgumentList.Add("--rigid-memory-allocate"); start.ArgumentList.Add("512"); start.ArgumentList.Add(args[1]);
                using var child = Process.Start(start)!;
                File.WriteAllText(args[1], child.Id.ToString());
                child.WaitForExit();
                return child.ExitCode;
            }
            var megabytes = int.Parse(args[1]);
            if (megabytes is < 1 or > 512) return 92;
            if (args.Length > 2) File.WriteAllText(args[2] + ".allocator", Environment.ProcessId.ToString());
            for (var index = 0; index < megabytes; index += 8)
            {
                var memory = Marshal.AllocHGlobal(8 * 1024 * 1024);
                buffers.Add(memory);
                for (var offset = 0; offset < 8 * 1024 * 1024; offset += 4096) Marshal.WriteByte(memory, offset, 1);
            }
            Console.WriteLine("CONTROLLED allocated unmanaged bytes=" + buffers.Count * 8L * 1024 * 1024);
            return 0;
        }
        catch (OutOfMemoryException) { Console.Error.WriteLine("CONTROLLED owned-job allocation refused"); return 37; }
        finally { foreach (var memory in buffers) Marshal.FreeHGlobal(memory); }
    }

    static async Task CheckMemoryProcess(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var native = new NativeProcess();
        var directory = parent.Resolve("rigid-memory"); Directory.CreateDirectory(directory);
        var lowLog = Path.Combine(directory,"invalid.log");
        foreach (var invalid in new[] { 0L, 67_108_863L, 68_719_476_737L })
            await reject(() => native.RunWithLimits(Environment.ProcessPath!, ["--echo","unexpected"], directory,lowLog,5,invalid), "native resource invalid budget rejected before child/log creation");
        check(!File.Exists(lowLog), "invalid resource policy has no child/log side effects");
        if (!native.SupportsPrivateMemoryLimit)
        {
            await reject(() => native.RunWithLimits(Environment.ProcessPath!, ["--echo","unexpected"],directory,lowLog,5,536_870_912), "unsupported aggregate-memory enforcement blocks before launch");
            check(!File.Exists(lowLog), "unsupported memory enforcement has no log side effect");
            return;
        }
        check(native.SupportsPrivateMemoryLimit, "Windows native runner advertises actual owned-job committed-memory enforcement");
        var positive = Path.Combine(directory,"positive.log");
        await native.RunWithLimits(Environment.ProcessPath!,["--rigid-memory-allocate","16"],directory,positive,10,536_870_912);
        var text = File.ReadAllText(positive);
        check(text.Contains("allocated unmanaged bytes=16777216") && text.Contains("aggregate-committed-memory") && text.Contains("536870912"), "actual bounded child completes and retains precise resource-policy accounting");
        var negative = Path.Combine(directory,"refused.log");
        await reject(() => native.RunWithLimits(Environment.ProcessPath!,["--rigid-memory-allocate","512"],directory,negative,10,268_435_456), "actual owned job refuses allocation above selected aggregate committed-memory budget");
        check(File.ReadAllText(negative).Contains("allocation refused"), "actual memory refusal is observed from child, not a simulated passing report");
        var witness = Path.Combine(directory,"descendant.pid");
        await reject(() => native.RunWithLimits(Environment.ProcessPath!,["--rigid-memory-parent",witness],directory,Path.Combine(directory,"descendant.log"),10,268_435_456), "actual descendant allocations share the owned-job aggregate limit");
        var childId = int.Parse(File.ReadAllText(witness));
        var alive = false;
        try { using var child = Process.GetProcessById(childId); alive = !child.HasExited; } catch (ArgumentException) { }
        check(!alive, "actual memory-failed descendant is not left running");
        using var cancel = new CancellationTokenSource(); cancel.Cancel();
        var cancelLog = Path.Combine(directory,"cancel.log");
        await reject(() => native.RunWithLimits(Environment.ProcessPath!,["--sleep"],directory,cancelLog,5,536_870_912,cancel.Token), "already-cancelled bounded run rejects before process launch");
        check(!File.Exists(cancelLog), "already-cancelled resource run creates no log");
    }

    static async Task CheckApplication(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var fixture = await Fixture.Create(parent);
        var w = fixture.W;
        var files = new[] { "settings.json", "handoff.json", "authoring.json", fixture.ReviewPath, "master.txt", ".art-staging/prepared.glb" };
        var originals = files.ToDictionary(p => p, p => File.ReadAllBytes(w.Resolve(p)));
        void Restore()
        {
            foreach (var item in originals) File.WriteAllBytes(w.Resolve(item.Key), item.Value);
            fixture.Native.Supported = true;
        }
        async Task BeforeLaunch(Action mutate, string expected, string description)
        {
            Restore(); mutate();
            var history = fixture.State.History.Count;
            Exception? observed = null;
            try { await fixture.Run(); } catch (Exception error) { observed = error; }
            check(observed is not null && observed.Message.Contains(expected, StringComparison.OrdinalIgnoreCase), "SIMULATED admission rejects " + description + " at the intended guard: " + observed?.Message);
            check(fixture.State.History.Count == history && fixture.Native.Calls == 0, "SIMULATED " + description + " consumes no finish start and launches no process");
        }
        await BeforeLaunch(() => fixture.Native.Supported = false, "memory policy", "unsupported resource enforcement");
        var beforeAtlasFiles = Directory.GetFiles(w.Root, "*", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
        await BeforeLaunch(() =>
        {
            var settings = w.Load<JsonObject>("settings.json");
            settings["rigidParts"]!["uvAtlas"] = new JsonObject { ["method"] = "smart-project-pixels", ["islandMarginPixels"] = 9 };
            w.Save("settings.json", settings); // Actual fixture recipe is64px:8px is the maximum.
        }, "textureSize/8", "UV margin incompatible with the known recipe");
        Restore();
        check(beforeAtlasFiles.Keys.Order().SequenceEqual(Directory.GetFiles(w.Root, "*", SearchOption.AllDirectories).Order())
            && beforeAtlasFiles.All(item => item.Value.SequenceEqual(File.ReadAllBytes(item.Key))),
            "SIMULATED incompatible UV admission creates no artifact, log or history and leaves every input byte unchanged");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve("handoff.json"), " "), "handoff checksum", "changed exact handoff bytes");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve("master.txt"), "changed"), "dependency", "changed authoring master dependency");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve("authoring.json"), " "), "authoring evidence checksum", "changed authoring evidence bytes");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve(fixture.ReviewPath), " "), "review checksum", "changed review bytes");
        await BeforeLaunch(() => File.AppendAllText(w.Resolve(".art-staging/prepared.glb"), "changed"), "dependency", "changed prepared GLB");
        await BeforeLaunch(() =>
        {
            var handoff = w.Load<JsonObject>("handoff.json"); handoff["parts"]![0]!["pivot"] = new JsonArray(.01, 0, 0); w.Save("handoff.json", handoff);
            var settings = w.Load<JsonObject>("settings.json"); settings["rigidParts"]!["handoffSha256"] = w.HashFile(w.Resolve("handoff.json")); w.Save("settings.json", settings);
        }, "Stale rigid preparation review", "pivot change with stale otherwise-valid technical approval");
        await BeforeLaunch(() =>
        {
            var handoff = w.Load<JsonObject>("handoff.json"); handoff["sourceRawSha256"] = ZeroHash; w.Save("handoff.json", handoff); fixture.RefreshBindings();
        }, "different retained raw", "different reconstruction ancestry");
        await BeforeLaunch(() =>
        {
            var other = ".opencaw/.cache/tasks/other/review.json"; w.Save(other, w.Load<JsonObject>(fixture.ReviewPath));
            var settings = w.Load<JsonObject>("settings.json"); settings["rigidParts"]!["reviewEvidence"] = other;
            settings["rigidParts"]!["reviewEvidenceSha256"] = w.HashFile(w.Resolve(other)); w.Save("settings.json", settings);
        }, "task-local", "another task's technical review");
        Restore();
        foreach (var kind in new[] { "container", "undeclared", "count", "cap", "authority", "nonfinite", "index", "storage", "scene", "transform", "cycle", "mirrored" })
        {
            await BeforeLaunch(() =>
            {
                if (kind == "container") File.WriteAllBytes(w.Resolve(".art-staging/prepared.glb"), new byte[28]);
                else if (kind == "undeclared") WriteGlb(w.Resolve(".art-staging/prepared.glb"), "extra.HIGH", "body.LOW");
                else if (kind is "nonfinite" or "index" or "storage")
                {
                    if (kind == "storage") WriteGlb(w.Resolve(".art-staging/prepared.glb"), fault: "storage");
                    else
                    {
                        using var stream = File.Open(w.Resolve(".art-staging/prepared.glb"), FileMode.Open, FileAccess.ReadWrite);
                        using var reader = new BinaryReader(stream, Encoding.UTF8, leaveOpen: true);
                        stream.Position = 12; var jsonLength = reader.ReadUInt32();
                        stream.Position = 20 + jsonLength + 8 + (kind == "index" ? 72 : 0);
                        using var writer = new BinaryWriter(stream);
                        if (kind == "nonfinite") writer.Write(float.NaN); else writer.Write((ushort)65535);
                    }
                }
                else if (kind is "scene" or "transform" or "cycle" or "mirrored") WriteGlb(w.Resolve(".art-staging/prepared.glb"), fault: kind);
                else if (kind == "count")
                {
                    var authoring = w.Load<JsonObject>("authoring.json"); authoring["repairs"]![0]!["highTriangles"] = 9; w.Save("authoring.json", authoring);
                }
                else if (kind == "cap")
                {
                    var settings = w.Load<JsonObject>("settings.json"); settings["rigidParts"]!["maxLod0Triangles"] = 4; w.Save("settings.json", settings);
                }
                else
                {
                    var review = w.Load<JsonObject>(fixture.ReviewPath); review["human"] = true; w.Save(fixture.ReviewPath, review);
                }
                fixture.RefreshBindings();
            }, kind switch { "container" => "container", "undeclared" => "exactly account", "count" => "triangle claims", "cap" => "LOD0", "nonfinite" => "nonfinite", "index" => "index exceeds", "storage" => "packed byte storage", "scene" => "selected scene", "transform" => "transform", "cycle" => "cycle", "mirrored"=>"positive orientation", _ => "not human" }, "rigid " + kind + " failure");
        }
        Restore();
        var link = w.Resolve("linked-sources");
        var target = w.Resolve("real-sources"); Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target, "master.txt"), "SIMULATED linked source");
        if (OperatingSystem.IsWindows())
            await new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", link, target], w.Root, w.Resolve("junction.log"), 5);
        else Directory.CreateSymbolicLink(link, target);
        try
        {
            await BeforeLaunch(() =>
            {
                var authoring = w.Load<JsonObject>("authoring.json"); authoring["sources"]![0]!["path"] = "linked-sources/master.txt";
                authoring["sources"]![0]!["sha256"] = Workspace.Hash(Path.Combine(target, "master.txt"));
                w.Save("authoring.json", authoring); fixture.RefreshBindings();
            }, "reparse", "actual confined-but-reparse authoring source");
        }
        finally { Directory.Delete(link); }
        Restore();
        await fixture.Run();
        var state = fixture.State;
        var stage = state.Stages["finish"];
        check(stage.Status == "complete" && fixture.Native.BoundedCalls == 2 && fixture.Native.UnboundedCalls == 0,
            "SIMULATED reviewed rigid finish uses explicit resource enforcement for version probe and producer");
        check(fixture.Native.LastJob!["rigidHandoff"]!["profile"]!.GetValue<string>() == "articulated"
            && fixture.Native.LastJob["taskEvidenceRoot"]!.GetValue<string>() == ".opencaw/.cache/tasks/tests",
            "SIMULATED native job carries exact reviewed handoff and active task, without applying another engine selector");
        check(stage.Artifacts.Keys.Contains("rigidHandoff") && stage.Artifacts.Keys.Contains("rigidPreparedSource")
            && stage.Artifacts.Keys.Contains("rigidAuthoringEvidence") && stage.Artifacts.Keys.Contains("rigidPreparationReview"),
            "SIMULATED native stage retains authoritative immutable handoff, source, authoring and review snapshots");
        check(new[] { "finish.py", "review.py", "common.py", "rigid_finish.py", "rigid_source_topology.py" }
            .All(name => stage.ExternalInputs.Keys.Any(path => path.EndsWith("/" + name, StringComparison.Ordinal) || path.EndsWith("\\" + name, StringComparison.Ordinal))),
            "SIMULATED explicit rigid path binds all five fixed audited scripts including source topology");
        check(stage.Inputs.ContainsKey("master.txt") && stage.Inputs.Keys.Any(p => p.StartsWith(stage.Attempt + "/rigid-sources/", StringComparison.Ordinal)),
            "SIMULATED authoring dependencies and exact copied inputs are retained as hash-bound evidence");
        var before = fixture.State.History.Count;
        File.AppendAllText(w.Resolve("master.txt"), "stale after successful fixture");
        await reject(() => fixture.Command("validate", false), "SIMULATED changed authoring source invalidates completed finish evidence");
        check(fixture.State.History.Count == before, "SIMULATED stale-evidence validation never spends an extra attempt");
        File.WriteAllBytes(w.Resolve("master.txt"), originals["master.txt"]);
        foreach (var failure in new[] { "identity", "measurements", "authority", "process", "mutation" })
        {
            fixture.Native.Failure = failure;
            var consumed = fixture.State.History.Count;
            await reject(() => fixture.Run(), "SIMULATED rigid producer cannot succeed through " + failure);
            check(fixture.State.Stages["finish"].Status == "failed" && fixture.State.History.Count == consumed + 1,
                "SIMULATED failed rigid producer preserves spent attempt without resetting history: " + failure);
            fixture.Native.Failure = "";
            if (failure == "mutation") File.WriteAllBytes(w.Resolve("master.txt"), originals["master.txt"]);
        }
    }

    sealed class Fixture
    {
        public required Workspace W { get; init; }
        public required Dictionary<string, string> Options { get; init; }
        public required SimulatedRigid Native { get; init; }
        public string ReviewPath => ".opencaw/.cache/tasks/tests/reviews/rigid.json";
        public string ManifestPath => Options["manifest"];
        public Manifest State => W.Load<Manifest>(ManifestPath);
        public Task Run() => Command("finish");
        public Task Command(string command, bool settings = true)
        {
            var options = new Dictionary<string, string>(Options);
            if (!settings) options.Remove("finish-settings");
            return new Pipeline(W, options, Native, new AlphaProcessor()).Execute(command, default);
        }
        public void RefreshBindings()
        {
            var handoff = W.Load<JsonObject>("handoff.json");
            var authoring = W.Load<JsonObject>("authoring.json");
            var preparedHash = W.HashFile(W.Resolve(".art-staging/prepared.glb"));
            handoff["preparedGlbSha256"] = preparedHash; authoring["preparedGlbSha256"] = preparedHash;
            W.Save("authoring.json", authoring);
            var authoringHash = W.HashFile(W.Resolve("authoring.json")); handoff["authoringEvidenceSha256"] = authoringHash;
            W.Save("handoff.json", handoff);
            var handoffHash = W.HashFile(W.Resolve("handoff.json"));
            var review = W.Load<JsonObject>(ReviewPath);
            review["sourceRawSha256"] = handoff["sourceRawSha256"]!.DeepClone(); review["preparedGlbSha256"] = preparedHash;
            review["authoringEvidenceSha256"] = authoringHash; review["handoffSha256"] = handoffHash;
            W.Save(ReviewPath, review);
            var selection = W.Load<JsonObject>("settings.json"); selection["rigidParts"]!["handoffSha256"] = handoffHash;
            selection["rigidParts"]!["reviewEvidenceSha256"] = W.HashFile(W.Resolve(ReviewPath)); W.Save("settings.json", selection);
        }
        public static async Task<Fixture> Create(Workspace parent)
        {
            var root = parent.Resolve("rigid-admission"); Directory.CreateDirectory(root); var w = new Workspace(root);
            File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
            RgbaPng.Write(w.Resolve("source.png"), new RgbaPng.Image(2, 2, Enumerable.Repeat((byte)255, 16).ToArray()));
            w.Save("rights.json", new { authorized = true, source = "SIMULATED test only" }); w.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
            w.Save("toolchain.json", new { schemaVersion = 1, files = Array.Empty<object>(), models = Array.Empty<object>(), blender = new { path = Environment.ProcessPath! }, limits = new { maxAttempts = 20, timeoutSeconds = 10 } });
            var baseline = w.Resolve("baseline"); var scripts = Path.Combine(baseline, ".styles/.pipelines/proof-to-model/blender"); Directory.CreateDirectory(scripts);
            foreach (var name in new[] { "finish.py", "review.py", "common.py", "rigid_finish.py", "rigid_source_topology.py" })
                File.WriteAllText(Path.Combine(scripts, name), "# SIMULATED fixed producer for C# contracts only\n");
            var options = new Dictionary<string, string> { ["mode"] = "single-view-diagnostic", ["asset"] = "rigid", ["version"] = "v1", ["task"] = "tests", ["proof"] = "source.png", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json", ["actor"] = "SIMULATED-builder", ["baseline-root"] = baseline };
            var native = new SimulatedRigid(w);
            await new Pipeline(w, options, native, new AlphaProcessor()).Execute("init", default);
            var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/rigid/v1/manifest.json"; options["manifest"] = manifest;
            var state = w.Load<Manifest>(manifest); Directory.CreateDirectory(w.Resolve(state.Staging + "/fixture"));
            var normalized = state.Staging + "/fixture/input.dat"; File.WriteAllText(w.Resolve(normalized), "SIMULATED preprocessing");
            var raw = state.Staging + "/fixture/raw.glb"; WriteGlb(w.Resolve(raw));
            state.Stages["preprocess"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Outputs = new() { [normalized] = Workspace.Hash(w.Resolve(normalized)) }, Artifacts = new() { ["normalized"] = normalized } };
            state.Stages["reconstruct"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Outputs = new() { [raw] = Workspace.Hash(w.Resolve(raw)) }, Artifacts = new() { ["glb"] = raw } };
            var core = new[] { state.Proof, state.ProofMetadata, state.Rights, state.Recipe, state.Toolchain, "STYLE.md" };
            foreach (var kind in new[] { "proof", "preprocessing" })
            {
                var path = ".opencaw/.cache/tasks/tests/reviews/" + kind + ".json"; w.Save(path, new { reason = "SIMULATED test approval, not a real human decision" });
                var paths = kind == "proof" ? core : core.Append(normalized);
                var fingerprint = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", paths.Order().Select(file => file + ":" + Workspace.Hash(w.Resolve(file)))))));
                state.Approvals.Add(new(kind, "SIMULATED", path, Workspace.Hash(w.Resolve(path)), fingerprint, DateTimeOffset.UtcNow));
            }
            w.Save(manifest, state);
            Directory.CreateDirectory(w.Resolve(".art-staging")); WriteGlb(w.Resolve(".art-staging/prepared.glb"));
            File.WriteAllText(w.Resolve("master.txt"), "SIMULATED source-master fixture");
            var handoff = Handoff(); handoff["sourceRawSha256"] = Workspace.Hash(w.Resolve(raw));
            var authoring = Authoring(); authoring["sourceRawSha256"] = handoff["sourceRawSha256"]!.DeepClone();
            authoring["sources"]![0]!["sha256"] = Workspace.Hash(w.Resolve("master.txt"));
            w.Save("handoff.json", handoff); w.Save("authoring.json", authoring);
            var reviewPath = ".opencaw/.cache/tasks/tests/reviews/rigid.json"; w.Save(reviewPath, Review());
            w.Save("settings.json", Settings()); options["finish-settings"] = "settings.json";
            var result = new Fixture { W = w, Options = options, Native = native };
            result.RefreshBindings();
            return result;
        }
    }

    sealed class SimulatedRigid(Workspace w) : INativeProcess
    {
        public bool Supported { get; set; } = true;
        public bool SupportsPrivateMemoryLimit => Supported;
        public int BoundedCalls { get; private set; }
        public int UnboundedCalls { get; private set; }
        public int Calls => BoundedCalls + UnboundedCalls;
        public JsonObject? LastJob { get; private set; }
        public string Failure { get; set; } = "";
        public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        { UnboundedCalls++; return Core(arguments.ToArray(), log); }
        public Task RunWithLimits(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, long maximumPrivateBytes, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        {
            if (!Supported || maximumPrivateBytes != 536_870_912) throw new InvalidOperationException("SIMULATED wrong explicit memory policy");
            BoundedCalls++; return Core(arguments.ToArray(), log);
        }
        Task Core(string[] args, string log)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(log)!);
            if (args.Contains("--version")) { File.WriteAllText(log, "Blender 4.5.10\nSIMULATED version only"); return Task.CompletedTask; }
            var job = w.Load<JsonObject>(args[Array.IndexOf(args,"--job")+1]); LastJob = job;
            var output = job["outputDir"]!.GetValue<string>(); Directory.CreateDirectory(w.Resolve(output));
            WriteGlb(w.Resolve(output+"/asset.glb"), runtime: true); File.WriteAllText(w.Resolve(output+"/asset.blend"),"BLENDER-SIMULATED");
            w.Save(output+"/report.json",new { simulated = true });
            var result = new JsonObject
            {
                ["status"] = "prepared", ["stages"] = new JsonArray(),
                ["measurements"] = new JsonObject { ["lod0Triangles"] = 8, ["glbBytes"] = new FileInfo(w.Resolve(output+"/asset.glb")).Length },
                ["inputSha256"] = Workspace.Hash(w.Resolve(job["input"]!.GetValue<string>())),
                ["rigidHandoffSha256"] = Workspace.Hash(w.Resolve("handoff.json")),
                ["finishingSettings"] = job["finishingSettings"]!.DeepClone(),
                ["artifacts"] = new JsonObject { ["glb"] = output+"/asset.glb", ["blend"] = output+"/asset.blend", ["report"] = output+"/report.json" }
            };
            if (Failure == "identity") result.Remove("rigidHandoffSha256");
            if (Failure == "measurements") result["measurements"] = new JsonObject();
            if (Failure == "authority") result["artifacts"]!["rigidHandoff"] = output+"/report.json";
            w.Save(job["result"]!.GetValue<string>(), result);
            File.WriteAllText(log,"SIMULATED native producer; no Blender/model/human approval claim\n");
            if (Failure == "mutation") File.AppendAllText(w.Resolve("master.txt"),"SIMULATED mutation during producer");
            if (Failure == "process") throw new IOException("SIMULATED unsuccessful process despite a passing-looking report");
            return Task.CompletedTask;
        }
    }

    static void WriteGlb(string path, string highName = "body.HIGH", string lowName = "body.LOW", bool runtime = false, string fault = "", bool extraPart = false)
    {
        float[] positions = [.01f,0,0,-.01f,0,0,0,.01f,0,0,-.01f,0,0,0,.01f,0,0,-.01f];
        ushort[] indices = [0,2,4,2,1,4,1,3,4,3,0,4,2,0,5,1,2,5,3,1,5,0,3,5];
        var json = new
        {
            asset = new { version = "2.0" }, scene = 0, scenes = new[] { new { nodes = runtime ? new[] { 0 } : new[] { 0,1 } } },
            nodes = runtime ? new[] { new { name = lowName, mesh = 0 } } : new[] { new { name = highName, mesh = 0 }, new { name = lowName, mesh = 1 } },
            meshes = new[] { new { primitives = new[] { new { attributes = new { POSITION = 0 }, indices = 1, material = 0 } } }, new { primitives = new[] { new { attributes = new { POSITION = 0 }, indices = 1, material = 0 } } } },
            materials = new[] { new { name = "SIMULATED constant material", pbrMetallicRoughness = new { metallicFactor = 0.0, roughnessFactor = .5 } } },
            buffers = new[] { new { byteLength = 120 } }, bufferViews = new[] { new { buffer = 0, byteOffset = 0, byteLength = 72 }, new { buffer = 0, byteOffset = 72, byteLength = 48 } },
            accessors = new object[] { new { bufferView = 0, componentType = 5126, count = fault == "storage" ? 600 : 6, type = "VEC3", min = new[] { -.01,-.01,-.01 }, max = new[] { .01,.01,.01 } }, new { bufferView = 1, componentType = 5123, count = 24, type = "SCALAR" } }
        };
        var document = JsonSerializer.SerializeToNode(json)!;
        if (extraPart)
        {
            document["nodes"]!.AsArray().Add(new JsonObject { ["name"] = "wing.HIGH", ["mesh"] = 0 });
            document["nodes"]!.AsArray().Add(new JsonObject { ["name"] = "wing.LOW", ["mesh"] = 1 });
            document["scenes"]![0]!["nodes"]!.AsArray().Add(2); document["scenes"]![0]!["nodes"]!.AsArray().Add(3);
        }
        if (fault == "scene") document["scenes"]![0]!["nodes"] = new JsonArray(0);
        if (fault == "transform") document["nodes"]![0]!["translation"] = new JsonArray(double.MaxValue, 0, 0);
        if (fault == "mirrored") document["nodes"]![0]!["scale"] = new JsonArray(-1,1,1);
        if (fault == "cycle")
        {
            document["nodes"]![0]!["children"] = new JsonArray(1);
            document["nodes"]![1]!["children"] = new JsonArray(0);
        }
        var text = Encoding.UTF8.GetBytes(document.ToJsonString());
        var jsonLength = (text.Length+3)/4*4;
        using var stream = File.Create(path); using var writer = new BinaryWriter(stream);
        writer.Write(0x46546c67u); writer.Write(2u); writer.Write((uint)(12+8+jsonLength+8+120));
        writer.Write((uint)jsonLength); writer.Write(0x4E4F534Au); writer.Write(text);
        for (var index=text.Length;index<jsonLength;index++) writer.Write((byte)' ');
        writer.Write(120u); writer.Write(0x004E4942u);
        foreach (var value in positions) writer.Write(value);
        foreach (var value in indices) writer.Write(value);
    }
}
