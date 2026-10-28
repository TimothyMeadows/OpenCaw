using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;
static class ExtendedTests
{
    public static async Task Run(Workspace w, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        WriteRgba(w.Resolve("matte.png"), [0, 255, 128]);
        WriteRgba(w.Resolve("opaque.png"), [255, 255, 255]);
        check(PngAlpha.Inspect(w.Resolve("matte.png"))?.Suitable == true, "actual transparent foreground alpha recognized");
        check(PngAlpha.Inspect(w.Resolve("opaque.png"))?.Suitable == false, "opaque RGBA never treated as matte");
        var opts = new Dictionary<string, string> { { "mode", "single-view-diagnostic" }, { "asset", "matte" }, { "version", "v1" }, { "task", "tests" }, { "proof", "matte.png" }, { "rights", "rights.json" }, { "recipe", "recipe.json" }, { "toolchain", "toolchain.json" }, { "actor", "builder" } };
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
        var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/matte/v1/manifest.json";
        opts["manifest"] = manifest;
        string Fingerprint(string kind)
        {
            var state = w.Load<Manifest>(manifest);
            IEnumerable<string> outputs = kind == "proof" ? [] : state.Stages.Values.Where(s => s.Status == "complete").SelectMany(s => s.Outputs.Keys);
            return Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(string.Join("\n", outputs.Concat(new[] { state.Proof, state.ProofMetadata, "rights.json", "recipe.json", "toolchain.json", "STYLE.md" }).Order().Select(x => x + ":" + Workspace.Hash(w.Resolve(x)))))));
        }
        opts["kind"] = "proof";
        opts["reviewer"] = "human";
        var approvalPath = ".opencaw/.cache/tasks/tests/reviews/matte-approval.json";
        opts["evidence"] = approvalPath;
        w.Save(approvalPath, new
        {
            kind = "proof",
            reviewer = "human",
            decision = "approved",
            fingerprint = Fingerprint("proof"),
            reason = "synthetic test approval",
            human = false
        });
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default), "proof approval requires explicit human assertion");
        w.Save(approvalPath, new
        {
            kind = "proof",
            reviewer = "human",
            decision = "approved",
            fingerprint = Fingerprint("proof"),
            reason = "synthetic test approval",
            human = true
        });
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default);
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default);
        var state = w.Load<Manifest>(manifest);
        check(state.Stages["preprocess"].Status == "complete", "approved suitable alpha preserved without engine/download");
        check(File.Exists(w.Resolve(state.Stages["preprocess"].Artifacts["mask"])), "preprocessing retains actual mask");
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("reconstruct", default), "normalized-input review required before reconstruction");
        File.AppendAllText(w.Resolve(state.Stages["preprocess"].Artifacts["normalized"]), "tamper");
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("validate", default), "changed artifact hash rejected");
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default);
        check(w.Load<Manifest>(manifest).Stages["preprocess"].Attempt != state.Stages["preprocess"].Attempt, "invalid stage recovers into new immutable attempt");
        var badReview = new Dictionary<string, string>(opts) { ["kind"] = "independent", ["reviewer"] = "builder" };
        await reject(() => new Pipeline(w, badReview, new NativeProcess(), new AlphaProcessor()).Execute("record", default), "creator cannot self-approve independent review");
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("setup", default);
        check(!Directory.Exists(w.Resolve(".local")), "setup dry-run installs nothing");
        var originalToolchain = File.ReadAllText(w.Resolve("toolchain.json"));
        var unsafeToolchain = w.Load<JsonObject>("toolchain.json");
        unsafeToolchain["files"] = new JsonArray(new JsonObject { ["url"] = "https://invalid.example/not-downloaded", ["sha256"] = new string('0', 64), ["path"] = ".local/tools/proof-to-model/test", ["license"] = "test", ["licenseAccepted"] = false, ["sizeBytes"] = 1 });
        w.Save("toolchain.json", unsafeToolchain);
        opts["execute"] = "true";
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("setup", default), "setup never accepts licenses implicitly");
        opts.Remove("execute");
        File.WriteAllText(w.Resolve("toolchain.json"), originalToolchain);
        await reject(() => Task.Run(() => new StageRegistry([("a", _ => Task.CompletedTask), ("A", _ => Task.CompletedTask)])), "duplicate registry names rejected");
        var executable = Environment.ProcessPath!;
        const string literal = "spaces ; $(not-a-command) & literal";
        await new NativeProcess().Run(executable, ["--echo", literal], w.Root, w.Resolve("literal.log"), 5);
        check(File.ReadAllText(w.Resolve("literal.log")).Contains(literal), "argument arrays preserve shell metacharacters literally");
        using (var cancel = new CancellationTokenSource(100))
            await reject(() => new NativeProcess().Run(executable, ["--sleep"], w.Root, w.Resolve("cancel.log"), 10, cancel.Token), "explicit cancellation terminates owned native process");
        // Approval hashes bind review content, not just its filename.
        File.AppendAllText(w.Resolve(approvalPath), " ");
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default), "edited approval evidence becomes stale");
    }
    static void WriteRgba(string path, byte[] alphas)
    {
        using var file = File.Create(path);
        file.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        void Chunk(string type, byte[] data)
        {
            Span<byte> len = stackalloc byte[4];
            System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(len, data.Length);
            file.Write(len);
            var tag = System.Text.Encoding.ASCII.GetBytes(type);
            file.Write(tag);
            file.Write(data);
            uint crc = 0xffffffff;
            foreach (var b in tag.Concat(data))
            {
                crc ^= b;
                for (var k = 0; k < 8; k++)
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
            }
            System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(len, ~crc);
            file.Write(len);
        }
        var header = new byte[13];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(header, alphas.Length);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), 1);
        header[8] = 8;
        header[9] = 6;
        Chunk("IHDR", header);
        using var bytes = new MemoryStream();
        using (var z = new System.IO.Compression.ZLibStream(bytes, System.IO.Compression.CompressionLevel.SmallestSize, true))
        {
            z.WriteByte(0);
            foreach (var a in alphas)
                z.Write(new byte[] { 255, 100, 50, a });
        }
        Chunk("IDAT", bytes.ToArray());
        Chunk("IEND", []);
    }
}
