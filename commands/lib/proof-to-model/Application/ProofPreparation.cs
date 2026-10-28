using System.Buffers.Binary;
using System.Net;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Domain;

namespace OpenCaw.ProofToModel.Application;

// Registers actual assistant/provider artifacts. This code performs neither vision
// nor image generation and cannot authenticate the assertions in supplied receipts.
public sealed partial class Pipeline
{
    static string PreparationText(JsonObject value, string name) =>
        value[name] is JsonValue node && node.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text)
            ? text : throw new InvalidOperationException("Preparation report requires " + name);
    static JsonArray PreparationArray(JsonObject value, string name) => value[name] as JsonArray ?? throw new InvalidOperationException("Preparation report requires array " + name);
    static JsonObject PreparationObject(JsonNode? node) => node as JsonObject ?? throw new InvalidOperationException("Preparation report requires an object");
    static void PreparationFields(JsonObject value, params string[] allowed)
    {
        foreach (var field in value)
            if (!allowed.Contains(field.Key, StringComparer.Ordinal)) throw new InvalidOperationException("Unknown preparation field: " + field.Key);
    }
    static void PreparationVersion(JsonObject value)
    {
        if (value["schemaVersion"]?.GetValue<int>() != 1) throw new InvalidOperationException("Unsupported preparation report schema version");
    }
    static void RequireHash(string value)
    {
        if (value.Length != 64 || value.Any(c => c is not (>= 'a' and <= 'f') and not (>= '0' and <= '9')))
            throw new InvalidOperationException("Expected lowercase SHA-256 identity");
    }
    void BindPreparationInput(Stage stage, string path)
    {
        var relative = w.Relative(path);
        stage.Inputs[relative] = Hash(relative);
    }
    JsonObject ReadPreparation(string path)
    {
        var full = w.Resolve(path);
        if (!File.Exists(full) || new FileInfo(full).Length is < 2 or > 8 * 1024 * 1024)
            throw new InvalidOperationException("Preparation report is missing, empty or exceeds 8 MiB");
        return w.Load<JsonObject>(path);
    }
    (int Width, int Height) PreparationImage(string path)
    {
        var full = w.Resolve(path);
        var extension = Path.GetExtension(full).ToLowerInvariant();
        if (extension is not (".png" or ".jpg" or ".jpeg")) throw new InvalidOperationException("Source/proof files must use an explicit PNG or JPEG extension");
        if (!File.Exists(full) || new FileInfo(full).Length is < 24 or > 512 * 1024 * 1024)
            throw new InvalidOperationException("Source/proof image is missing, empty or exceeds 512 MiB");
        using var stream = File.OpenRead(full);
        using var reader = new BinaryReader(stream);
        var header = reader.ReadBytes(24);
        if (header.Take(8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }) && header.AsSpan(12, 4).SequenceEqual("IHDR"u8))
        {
            if (extension != ".png") throw new InvalidOperationException("PNG bytes require a matching .png extension");
            var width = BinaryPrimitives.ReadInt32BigEndian(header.AsSpan(16, 4));
            var height = BinaryPrimitives.ReadInt32BigEndian(header.AsSpan(20, 4));
            if (width <= 0 || height <= 0 || (long)width * height > 100_000_000) throw new InvalidOperationException("Image dimensions exceed preparation bounds");
            return (width, height);
        }
        if (header[0] == 255 && header[1] == 216)
        {
            if (extension is not (".jpg" or ".jpeg")) throw new InvalidOperationException("JPEG bytes require a matching .jpg/.jpeg extension");
            stream.Position = 2;
            while (stream.Position + 4 <= stream.Length)
            {
                if (reader.ReadByte() != 255) throw new InvalidOperationException("Malformed JPEG marker");
                byte marker;
                do { marker = reader.ReadByte(); } while (marker == 255 && stream.Position < stream.Length);
                if (marker is 0xD9 or 0xDA) break;
                if (marker is >= 0xD0 and <= 0xD7 or 0x01) continue;
                var length = (reader.ReadByte() << 8) | reader.ReadByte();
                if (length < 2 || stream.Position + length - 2 > stream.Length) break;
                if (marker is >= 0xC0 and <= 0xC3 or >= 0xC5 and <= 0xC7 or >= 0xC9 and <= 0xCB or >= 0xCD and <= 0xCF)
                {
                    if (length < 8) break;
                    _ = reader.ReadByte();
                    var height = (reader.ReadByte() << 8) | reader.ReadByte();
                    var width = (reader.ReadByte() << 8) | reader.ReadByte();
                    if (width <= 0 || height <= 0 || (long)width * height > 100_000_000) break;
                    return (width, height);
                }
                stream.Position += length - 2;
            }
        }
        throw new InvalidOperationException("Preparation requires an identifiable PNG or JPEG image; decoding and matte validation remain separate checks");
    }
    void InitializeSources()
    {
        if (m.SchemaVersion != 2) return;
        JsonObject? supplied = options.TryGetValue("sources", out var sourcePath) ? ReadPreparation(sourcePath) : null;
        if (supplied is not null) { PreparationVersion(supplied); PreparationFields(supplied, "schemaVersion", "images"); }
        var images = supplied is null
            ? new JsonArray(new JsonObject { ["id"] = "source-1", ["path"] = m.Proof })
            : PreparationArray(supplied, "images");
        if (images.Count is < 1 or > 64) throw new InvalidOperationException("Register between one and 64 original sources");
        var saved = new JsonArray();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var hashes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in images)
        {
            var image = PreparationObject(node);
            PreparationFields(image, "id", "path", "sha256");
            var id = Id(PreparationText(image, "id"));
            var path = w.Relative(PreparationText(image, "path"));
            if (!ids.Add(id)) throw new InvalidOperationException("Duplicate original source ID");
            var dimensions = PreparationImage(path);
            var hash = Hash(path);
            if (!hashes.Add(hash)) throw new InvalidOperationException("Duplicate original image bytes are not separate sources");
            if (image["sha256"] is not null && image["sha256"]!.GetValue<string>() != hash) throw new InvalidOperationException("Original source hash mismatch");
            var first = saved.Count == 0;
            if (first && hash != Hash(m.Proof)) throw new InvalidOperationException("First source must match the registered primary original proof");
            var target = first ? m.Proof : m.Staging + "/original/sources/" + id + Path.GetExtension(path).ToLowerInvariant();
            if (!first)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(target))!);
                File.Copy(w.Resolve(path), w.Resolve(target), false);
            }
            var originalPath = supplied is null ? ReadPreparation(m.ProofMetadata)["originalPath"]?.GetValue<string>() ?? path : path;
            saved.Add(new JsonObject { ["id"] = id, ["path"] = target, ["sha256"] = hash, ["originalPath"] = originalPath, ["width"] = dimensions.Width, ["height"] = dimensions.Height });
        }
        m.SourceSet = m.Staging + "/original/source-set.json";
        w.Save(m.SourceSet, new JsonObject { ["schemaVersion"] = 1, ["primarySourceId"] = saved[0]!["id"]!.GetValue<string>(), ["images"] = saved });
        var metadata = ReadPreparation(m.ProofMetadata);
        metadata["sourceSetHash"] = Hash(m.SourceSet);
        w.Save(m.ProofMetadata, metadata);
    }
    JsonObject CurrentSourceSet()
    {
        if (string.IsNullOrWhiteSpace(m.SourceSet)) throw new InvalidOperationException("Register immutable original sources first");
        if (!w.Relative(m.SourceSet).StartsWith(m.Staging + "/original/", StringComparison.Ordinal)) throw new InvalidOperationException("Source set must remain under this version's immutable original directory");
        var sources = ReadPreparation(m.SourceSet);
        PreparationVersion(sources);
        var originalMetadata = ReadPreparation(m.ProofMetadata);
        if (originalMetadata["sourceSetHash"]?.GetValue<string>() != Hash(m.SourceSet) || originalMetadata["proofHash"]?.GetValue<string>() != Hash(m.Proof)) throw new InvalidOperationException("Changed immutable source-set or primary original ancestry");
        var images = PreparationArray(sources, "images");
        if (images.Count is < 1 or > 64) throw new InvalidOperationException("Invalid original source inventory");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var hashes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in images)
        {
            var image = PreparationObject(node);
            var id = Id(PreparationText(image, "id"));
            var path = w.Relative(PreparationText(image, "path"));
            var hash = PreparationText(image, "sha256"); RequireHash(hash);
            if (!ids.Add(id) || !hashes.Add(hash)) throw new InvalidOperationException("Duplicate original source identity");
            if (!path.StartsWith(m.Staging + "/original/", StringComparison.Ordinal) || Hash(path) != hash) throw new InvalidOperationException("Changed or non-original source image");
            var dimensions = PreparationImage(path);
            if (image["width"]?.GetValue<int>() != dimensions.Width || image["height"]?.GetValue<int>() != dimensions.Height) throw new InvalidOperationException("Changed original source dimensions");
        }
        if (PreparationText(sources, "primarySourceId") != images[0]!["id"]!.GetValue<string>() || images[0]!["path"]!.GetValue<string>() != m.Proof) throw new InvalidOperationException("Invalid primary original source");
        return sources;
    }
    IEnumerable<string> PreparationPaths()
    {
        if (m.SchemaVersion != 2 || string.IsNullOrEmpty(m.SourceSet)) yield break;
        yield return m.SourceSet;
        foreach (var node in PreparationArray(CurrentSourceSet(), "images")) yield return PreparationText(PreparationObject(node), "path");
        if (!string.IsNullOrEmpty(m.Classification)) yield return m.Classification;
        if (string.IsNullOrEmpty(m.ProofSet)) yield break;
        yield return m.ProofSet;
        var set = ReadPreparation(m.ProofSet);
        foreach (var node in PreparationArray(set, "views"))
        {
            var view = PreparationObject(node);
            yield return PreparationText(view, "image");
            if (view["generationReceipt"] is JsonValue receipt) yield return receipt.GetValue<string>();
        }
        if (set["generationPolicy"] is JsonObject policy)
        {
            yield return PreparationText(policy, "mediaContract");
            yield return PreparationText(policy, "authorization");
        }
    }
    Dictionary<string, JsonObject> SourceIdentities(JsonObject sources) => PreparationArray(sources, "images").Select(PreparationObject).ToDictionary(x => PreparationText(x, "id"), StringComparer.Ordinal);
    static string[] SourceReferences(JsonObject value, string key, IReadOnlyDictionary<string, JsonObject> sources, bool allowEmpty = false)
    {
        var references = PreparationArray(value, key).Select(x => x?.GetValue<string>() ?? "").ToArray();
        if ((!allowEmpty && references.Length == 0) || references.Distinct(StringComparer.Ordinal).Count() != references.Length || references.Any(id => !sources.ContainsKey(id)))
            throw new InvalidOperationException("Classification/proof evidence must reference registered original source IDs only");
        return references;
    }
    void ValidateClassification(JsonObject report, JsonObject sources, bool forProofs)
    {
        PreparationVersion(report);
        PreparationFields(report, "schemaVersion", "sourceSetHash", "sources", "sourceViews", "researchStatus", "researchReason", "research", "subjects", "relations", "unknowns", "preservationConstraints", "prohibitedSubstitutions", "conflicts");
        if (PreparationText(report, "sourceSetHash") != Hash(m.SourceSet)) throw new InvalidOperationException("Classification is bound to a different source set");
        var known = SourceIdentities(sources);
        var citedSources = PreparationArray(report, "sources").Select(PreparationObject).ToArray();
        if (citedSources.Length != known.Count || citedSources.Select(x => PreparationText(x, "sourceId")).Distinct(StringComparer.Ordinal).Count() != known.Count)
            throw new InvalidOperationException("Classification must cover the complete original source set exactly once");
        foreach (var source in citedSources)
        {
            var id = PreparationText(source, "sourceId");
            if (!known.TryGetValue(id, out var original) || PreparationText(source, "sha256") != PreparationText(original, "sha256")) throw new InvalidOperationException("Classification cites generated, renamed or changed image evidence");
            if (source.Any(p => p.Key is not ("sourceId" or "sha256"))) throw new InvalidOperationException("Classification source evidence may contain only registered source IDs and hashes");
        }
        var sourceViews = PreparationArray(report, "sourceViews").Select(PreparationObject).ToArray();
        if (sourceViews.Length != known.Count || sourceViews.Select(x => PreparationText(x, "sourceId")).Distinct(StringComparer.Ordinal).Count() != known.Count) throw new InvalidOperationException("Classify the view/coverage of every original source exactly once");
        foreach (var sourceView in sourceViews)
        {
            PreparationFields(sourceView, "sourceId", "view", "usable", "reason");
            if (!known.ContainsKey(PreparationText(sourceView, "sourceId"))) throw new InvalidOperationException("View classification references an unregistered source");
            var angle = PreparationText(sourceView, "view");
            if (!MultiViewGeometry.Views.Contains(angle, StringComparer.Ordinal) && angle is not ("oblique" or "unknown")) throw new InvalidOperationException("Unknown classified source angle");
            _ = PreparationText(sourceView, "reason");
            if (sourceView["usable"] is null || (sourceView["usable"]!.GetValue<bool>() && !MultiViewGeometry.Views.Contains(angle, StringComparer.Ordinal))) throw new InvalidOperationException("Only a usable canonical source angle can replace a generated proof");
        }
        var research = PreparationArray(report, "research").Select(PreparationObject).ToArray();
        var researchIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in research)
        {
            PreparationFields(item, "id", "url", "title", "sourceQuestion", "sourceIds", "retrievedAt");
            if (!researchIds.Add(Id(PreparationText(item, "id")))) throw new InvalidOperationException("Duplicate research identity");
            if (!Uri.TryCreate(PreparationText(item, "url"), UriKind.Absolute, out var uri) || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo)) throw new InvalidOperationException("Research requires an explicit HTTPS source without credentials");
            _ = PreparationText(item, "title"); _ = PreparationText(item, "sourceQuestion");
            SourceReferences(item, "sourceIds", known);
            if (!DateTimeOffset.TryParse(PreparationText(item, "retrievedAt"), out _)) throw new InvalidOperationException("Research requires a retrieval timestamp");
        }
        var researchStatus = PreparationText(report, "researchStatus");
        if (researchStatus is not ("performed" or "not-required") || (researchStatus == "performed" && research.Length == 0) || (researchStatus == "not-required" && research.Length != 0)) throw new InvalidOperationException("Research status must describe actual recorded references");
        _ = PreparationText(report, "researchReason");
        var subjectIds = new HashSet<string>(StringComparer.Ordinal);
        var subjects = PreparationArray(report, "subjects");
        if (subjects.Count == 0) throw new InvalidOperationException("Classification requires subjects or an explicitly unknown subject");
        foreach (var node in subjects)
        {
            var subject = PreparationObject(node);
            PreparationFields(subject, "id", "kind", "classification", "sourceIds", "claims", "parts");
            if (!subjectIds.Add(Id(PreparationText(subject, "id")))) throw new InvalidOperationException("Duplicate classified subject");
            if (PreparationText(subject, "kind") is not ("living" or "nonliving" or "assembly" or "unknown")) throw new InvalidOperationException("Unknown subject classification kind");
            _ = PreparationText(subject, "classification");
            SourceReferences(subject, "sourceIds", known);
            var claims = PreparationArray(subject, "claims");
            if (claims.Count == 0) throw new InvalidOperationException("Subject requires observed, inferred or unknown claims");
            var claimIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var claimNode in claims)
            {
                var claim = PreparationObject(claimNode);
                PreparationFields(claim, "id", "description", "sourceIds", "confidence", "disposition", "basis", "impact", "alternatives", "researchIds");
                if (!claimIds.Add(Id(PreparationText(claim, "id")))) throw new InvalidOperationException("Duplicate subject claim");
                _ = PreparationText(claim, "description"); SourceReferences(claim, "sourceIds", known);
                if (PreparationText(claim, "confidence") is not ("high" or "medium" or "low" or "unknown")) throw new InvalidOperationException("Claim requires a confidence category");
                var disposition = PreparationText(claim, "disposition");
                if (disposition is not ("observed" or "research-inferred" or "user-specified" or "unknown")) throw new InvalidOperationException("Claim requires a distinct evidence disposition");
                if (disposition == "research-inferred")
                {
                    _ = PreparationText(claim, "basis"); _ = PreparationText(claim, "impact");
                    _ = PreparationArray(claim, "alternatives");
                    var references = PreparationArray(claim, "researchIds").Select(x => x!.GetValue<string>()).ToArray();
                    if (references.Length == 0 || references.Any(id => !researchIds.Contains(id))) throw new InvalidOperationException("Inferred anatomy/structure requires actual research support");
                }
            }
            var partIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var partNode in PreparationArray(subject, "parts"))
            {
                var part = PreparationObject(partNode); _ = Id(PreparationText(part, "id")); _ = PreparationText(part, "name");
                if (!partIds.Add(PreparationText(part, "id"))) throw new InvalidOperationException("Duplicate semantic part identity");
                PreparationFields(part, "id", "name", "sourceIds", "visibility", "disposition", "claimIds");
                SourceReferences(part, "sourceIds", known);
                if (PreparationText(part, "visibility") is not ("visible" or "partial" or "hidden" or "unknown")) throw new InvalidOperationException("Semantic part requires visibility");
                if (PreparationText(part, "disposition") is not ("observed" or "research-inferred" or "user-specified" or "unknown")) throw new InvalidOperationException("Semantic part requires an evidence disposition");
                var evidenceClaims = PreparationArray(part, "claimIds").Select(x => x!.GetValue<string>()).ToArray();
                if (evidenceClaims.Length == 0 || evidenceClaims.Any(id => !claimIds.Contains(id))) throw new InvalidOperationException("Semantic parts require subject claim support");
                if (PreparationText(part, "visibility") == "hidden" && PreparationText(part, "disposition") == "observed") throw new InvalidOperationException("Fully hidden anatomy/structure cannot be reported as observed");
                if (!claims.Select(PreparationObject).Any(claim => evidenceClaims.Contains(PreparationText(claim, "id"), StringComparer.Ordinal) && PreparationText(claim, "disposition") == PreparationText(part, "disposition"))) throw new InvalidOperationException("Semantic part disposition disagrees with its supporting claims");
            }
        }
        foreach (var node in PreparationArray(report, "relations"))
        {
            var relation = PreparationObject(node);
            PreparationFields(relation, "from", "to", "type", "description", "sourceIds");
            if (!subjectIds.Contains(PreparationText(relation, "from")) || !subjectIds.Contains(PreparationText(relation, "to"))) throw new InvalidOperationException("Assembly relation references an unknown subject");
            _ = PreparationText(relation, "type"); _ = PreparationText(relation, "description"); SourceReferences(relation, "sourceIds", known);
        }
        foreach (var key in new[] { "preservationConstraints", "prohibitedSubstitutions" })
            foreach (var item in PreparationArray(report, key)) if (string.IsNullOrWhiteSpace(item?.GetValue<string>())) throw new InvalidOperationException("Empty preservation or substitution constraint");
        foreach (var node in PreparationArray(report, "unknowns"))
        {
            var unknown = PreparationObject(node); _ = PreparationText(unknown, "description"); _ = PreparationText(unknown, "impact"); SourceReferences(unknown, "sourceIds", known);
            PreparationFields(unknown, "description", "impact", "sourceIds", "requiresResolution", "resolution");
            if (unknown["requiresResolution"] is null) throw new InvalidOperationException("Unknowns require an explicit resolution applicability");
            if (forProofs && unknown["requiresResolution"]!.GetValue<bool>() && string.IsNullOrWhiteSpace(unknown["resolution"]?.GetValue<string>())) throw new InvalidOperationException("Resolve consequential source uncertainty before proof production");
        }
        foreach (var node in PreparationArray(report, "conflicts"))
        {
            var conflict = PreparationObject(node); _ = PreparationText(conflict, "description"); SourceReferences(conflict, "sourceIds", known);
            PreparationFields(conflict, "description", "sourceIds", "resolved", "resolution");
            if (conflict["resolved"] is null) throw new InvalidOperationException("Conflicts require explicit resolution status");
            if (forProofs && (!conflict["resolved"]!.GetValue<bool>() || string.IsNullOrWhiteSpace(conflict["resolution"]?.GetValue<string>()))) throw new InvalidOperationException("Resolve conflicting originals before proof production");
        }
    }
    Task RegisterClassification(Stage stage, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        var input = w.Relative(Need("classification"));
        var report = ReadPreparation(input);
        ValidateClassification(report, CurrentSourceSet(), false);
        BindPreparationInput(stage, input);
        var target = stage.Attempt + "/classification.json";
        w.Save(target, report);
        stage.Artifacts["classification"] = target;
        var usable = PreparationArray(report, "sourceViews").Select(PreparationObject).Where(view => view["usable"]!.GetValue<bool>()).ToArray();
        var covered = usable.Select(view => PreparationText(view, "view")).ToHashSet(StringComparer.Ordinal);
        var missing = MultiViewGeometry.Views.Where(view => !covered.Contains(view)).ToArray();
        var blocked = new JsonArray();
        foreach (var node in PreparationArray(report, "unknowns"))
        {
            var unknown = PreparationObject(node);
            if (unknown["requiresResolution"]!.GetValue<bool>() && string.IsNullOrWhiteSpace(unknown["resolution"]?.GetValue<string>())) blocked.Add(PreparationText(unknown, "description"));
        }
        foreach (var node in PreparationArray(report, "conflicts"))
        {
            var conflict = PreparationObject(node);
            if (!conflict["resolved"]!.GetValue<bool>() || string.IsNullOrWhiteSpace(conflict["resolution"]?.GetValue<string>())) blocked.Add(PreparationText(conflict, "description"));
        }
        var plan = stage.Attempt + "/proof-plan.json";
        w.Save(plan, new JsonObject { ["schemaVersion"] = 1, ["sourceSetHash"] = Hash(m.SourceSet), ["classificationHash"] = Hash(target), ["requiredViews"] = new JsonArray(MultiViewGeometry.Views.Select(view => JsonValue.Create(view)).ToArray()), ["usableSourceViews"] = new JsonArray(usable.Select(view => view.DeepClone()).ToArray()), ["missingViews"] = new JsonArray(missing.Select(view => JsonValue.Create(view)).ToArray()), ["minimumGeneratedViews"] = missing.Length, ["generationExecution"] = false, ["blockedBy"] = blocked, ["humanApproval"] = "pending" });
        stage.Artifacts["proof-plan"] = plan;
        m.Classification = target;
        m.ProofSet = "";
        return Task.CompletedTask;
    }
    JsonObject CurrentProofSet()
    {
        if (string.IsNullOrEmpty(m.Classification) || string.IsNullOrEmpty(m.ProofSet)) throw new InvalidOperationException("Complete source classification and six-view proof preparation first");
        var sources = CurrentSourceSet();
        ValidateClassification(ReadPreparation(m.Classification), sources, true);
        var report = ReadPreparation(m.ProofSet);
        ValidateProofSet(report, sources, false);
        return report;
    }
    string CurrentFrontProof() => m.SchemaVersion == 2 && !string.IsNullOrEmpty(m.ProofSet)
        ? PreparationText(PreparationObject(PreparationArray(CurrentProofSet(), "views")[0]), "image") : m.Proof;
    void ValidatePreparation()
    {
        if (m.SchemaVersion != 2) return;
        var sources = CurrentSourceSet();
        if (!string.IsNullOrEmpty(m.Classification)) ValidateClassification(ReadPreparation(m.Classification), sources, !string.IsNullOrEmpty(m.ProofSet));
        if (!string.IsNullOrEmpty(m.ProofSet)) _ = CurrentProofSet();
    }
    void ValidateGenerationReceipt(JsonObject receipt, JsonObject view, Dictionary<string, JsonObject> sources, string expectedPipeline)
    {
        PreparationVersion(receipt);
        PreparationFields(receipt, "schemaVersion", "runId", "createdAt", "backend", "modality", "model", "workflow", "generation", "inputs", "outputs", "runtime", "review");
        if (PreparationText(receipt, "modality") != "image") throw new InvalidOperationException("Proof receipt must describe image generation");
        _ = PreparationText(receipt, "runId");
        if (!DateTimeOffset.TryParse(PreparationText(receipt, "createdAt"), out _)) throw new InvalidOperationException("Generation receipt requires timestamp");
        var backend = PreparationObject(receipt["backend"]);
        PreparationFields(backend, "kind", "provider", "capability", "toolVersion");
        if (PreparationText(backend, "kind") != (expectedPipeline == "CLOUD" ? "cloud-session" : "local")) throw new InvalidOperationException("Generation receipt disagrees with selected CLOUD/LOCAL capability");
        _ = PreparationText(backend, "provider"); _ = PreparationText(backend, "capability");
        PreparationFields(PreparationObject(receipt["model"]), "name", "revision", "digest", "license");
        PreparationFields(PreparationObject(receipt["workflow"]), "name", "revision", "digest");
        foreach (var pair in new[] { (backend, "toolVersion"), (PreparationObject(receipt["model"]), "name"), (PreparationObject(receipt["model"]), "revision"), (PreparationObject(receipt["model"]), "digest"), (PreparationObject(receipt["model"]), "license"), (PreparationObject(receipt["workflow"]), "name"), (PreparationObject(receipt["workflow"]), "revision"), (PreparationObject(receipt["workflow"]), "digest") }) ValidateDisclosure(pair.Item1[pair.Item2]);
        var generation = PreparationObject(receipt["generation"]);
        PreparationFields(generation, "prompt", "negativePrompt", "parameters", "seed");
        _ = PreparationText(generation, "prompt"); ValidateDisclosure(generation["negativePrompt"]);
        if (generation["parameters"] is not JsonObject) throw new InvalidOperationException("Generation parameters require actual values or an explicit unavailable object");
        if (generation["seed"] is not JsonValue seed || !seed.TryGetValue<long>(out _))
        {
            if (generation["seed"] is not JsonObject) throw new InvalidOperationException("Generation seed must be an integer or explicit unavailable object");
            ValidateDisclosure(generation["seed"]);
        }
        var inputs = PreparationArray(receipt, "inputs").Select(PreparationObject).ToArray();
        foreach (var input in inputs)
        {
            PreparationFields(input, "description", "source", "rights", "consent");
            _ = PreparationText(input, "description"); _ = PreparationText(input, "source"); _ = PreparationText(input, "rights");
            if (PreparationText(input, "consent") is not ("confirmed" or "not-applicable")) throw new InvalidOperationException("Unconfirmed input consent blocks proof registration");
        }
        foreach (var id in SourceReferences(view, "sourceIds", sources))
            if (!inputs.Any(input => PreparationText(input, "source") == PreparationText(sources[id], "path") || PreparationText(input, "source") == "sha256:" + PreparationText(sources[id], "sha256"))) throw new InvalidOperationException("Generation receipt omits original source ancestry");
        var hash = PreparationText(view, "sha256");
        var matches = PreparationArray(receipt, "outputs").Select(PreparationObject).Where(output => PreparationText(output, "sha256") == hash).ToArray();
        if (matches.Length != 1 || PreparationText(matches[0], "status") is not ("staged" or "accepted")) throw new InvalidOperationException("Generation receipt does not identify exactly one usable selected output");
        var outputPath = PreparationText(matches[0], "stagedPath");
        if (Hash(outputPath) != hash) throw new InvalidOperationException("Generation receipt output changed");
        if (w.Relative(outputPath).StartsWith("assets/", StringComparison.Ordinal)) throw new InvalidOperationException("Generated proofs must remain outside runtime assets");
        ValidateDisclosure(matches[0]["runtimeTarget"]);
        var runtime = PreparationObject(receipt["runtime"]); ValidateDisclosure(runtime["destination"]);
        PreparationFields(runtime, "destination", "budgets");
        if (PreparationObject(runtime["budgets"]).Count == 0) throw new InvalidOperationException("Generation receipt requires declared runtime budgets");
        var review = PreparationObject(receipt["review"]);
        PreparationFields(review, "status", "reviewer", "reviewedAt", "notes");
        if (PreparationText(review, "status") is not ("pending" or "accepted")) throw new InvalidOperationException("Rejected generation receipt cannot supply a proof");
        ValidateDisclosure(review["reviewer"]); ValidateDisclosure(review["reviewedAt"]);
        if (review["notes"] is not JsonValue notes || !notes.TryGetValue<string>(out _)) throw new InvalidOperationException("Generation review requires text notes");
    }
    static void ValidateDisclosure(JsonNode? node)
    {
        if (node is JsonValue value && value.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text)) return;
        if (node is JsonObject unavailable && unavailable["unavailable"]?.GetValue<bool>() == true && !string.IsNullOrWhiteSpace(unavailable["reason"]?.GetValue<string>())) return;
        throw new InvalidOperationException("Provider metadata must disclose a value or an explicit unavailable reason");
    }
    JsonObject ValidateGenerationPolicy(JsonObject policy)
    {
        PreparationFields(policy, "pipeline", "mediaContract", "mediaContractHash", "authorization", "authorizationHash");
        var pipeline = PreparationText(policy, "pipeline");
        if (pipeline is not ("CLOUD" or "LOCAL")) throw new InvalidOperationException("Proof generation requires explicit CLOUD or LOCAL selection");
        if (w.Relative(PreparationText(policy, "mediaContract")) != "MEDIA.md" || PreparationText(policy, "mediaContractHash") != Hash("MEDIA.md")) throw new InvalidOperationException("Proof generation requires the current MEDIA.md contract");
        var authorizationPath = PreparationText(policy, "authorization"); RequirePreparationReceipt(authorizationPath);
        if (policy["authorizationHash"] is not null && policy["authorizationHash"]!.GetValue<string>() != Hash(authorizationPath)) throw new InvalidOperationException("Changed generation authorization");
        var authorization = ReadPreparation(authorizationPath); PreparationVersion(authorization);
        PreparationFields(authorization, "schemaVersion", "authorized", "purpose", "pipeline", "sourceSetHash", "classificationHash", "mediaContractHash", "actor", "reason", "maxGeneratedCandidates", "maxRevisionsPerView");
        if (authorization["authorized"]?.GetValue<bool>() != true || PreparationText(authorization, "purpose") != "proof-to-model-multiview" || PreparationText(authorization, "pipeline") != pipeline || PreparationText(authorization, "sourceSetHash") != Hash(m.SourceSet) || PreparationText(authorization, "classificationHash") != Hash(m.Classification) || PreparationText(authorization, "mediaContractHash") != Hash("MEDIA.md")) throw new InvalidOperationException("Generation authorization must bind current originals, classification, media contract and capability");
        _ = PreparationText(authorization, "actor"); _ = PreparationText(authorization, "reason");
        if (authorization["maxGeneratedCandidates"]?.GetValue<int>() is not > 0 || authorization["maxRevisionsPerView"]?.GetValue<int>() is not > 0) throw new InvalidOperationException("Generation authorization requires positive image-count and per-view revision budgets");
        return authorization;
    }
    void ValidateProofSet(JsonObject report, JsonObject sourceSet, bool incoming)
    {
        PreparationVersion(report);
        PreparationFields(report, "schemaVersion", "revision", "sourceSetHash", "classificationHash", "camera", "views", "generationPolicy", "previousProofSetHash", "reviewStatus", "revisedViews");
        if (PreparationText(report, "sourceSetHash") != Hash(m.SourceSet) || PreparationText(report, "classificationHash") != Hash(m.Classification)) throw new InvalidOperationException("Proof set ancestry is stale");
        if (report["revision"]?.GetValue<int>() is not > 0) throw new InvalidOperationException("Proof set requires positive revision");
        MultiViewGeometry.Validate(report);
        var sources = SourceIdentities(sourceSet);
        var hashes = new HashSet<string>(StringComparer.Ordinal);
        var generated = new List<JsonObject>();
        foreach (var node in PreparationArray(report, "views"))
        {
            var view = PreparationObject(node);
            PreparationFields(view, "view", "image", "sha256", "origin", "sourceIds", "cameraToWorld", "cameraAngleX", "revision", "width", "height", "generationReceipt", "generationReceiptHash");
            var path = w.Relative(PreparationText(view, "image"));
            if (!incoming && !path.StartsWith(m.Staging + "/attempts/prepare-proofs-", StringComparison.Ordinal)) throw new InvalidOperationException("Selected proof images must be immutable preparation artifacts");
            var hash = PreparationText(view, "sha256"); RequireHash(hash);
            if (!hashes.Add(hash)) throw new InvalidOperationException("Six angles require distinct image bytes, not duplicated or mirrored file aliases");
            if (Hash(path) != hash) throw new InvalidOperationException("Changed selected proof image");
            var dimensions = PreparationImage(path);
            if (!incoming && (view["width"]?.GetValue<int>() != dimensions.Width || view["height"]?.GetValue<int>() != dimensions.Height)) throw new InvalidOperationException("Selected proof dimensions changed");
            var references = SourceReferences(view, "sourceIds", sources);
            if (view["revision"]?.GetValue<int>() is not > 0) throw new InvalidOperationException("View requires a positive revision");
            var origin = PreparationText(view, "origin");
            if (origin == "source")
            {
                if (references.Length != 1 || hash != PreparationText(sources[references[0]], "sha256")) throw new InvalidOperationException("Original-view slot must preserve actual registered original bytes");
                if (view["generationReceipt"] is not null || view["generationReceiptHash"] is not null) throw new InvalidOperationException("Generated proofs cannot be declared original sources");
                var sourceViews = PreparationArray(ReadPreparation(m.Classification), "sourceViews").Select(PreparationObject);
                if (!sourceViews.Any(sourceView => PreparationText(sourceView, "sourceId") == references[0] && sourceView["usable"]!.GetValue<bool>() && PreparationText(sourceView, "view") == PreparationText(view, "view"))) throw new InvalidOperationException("Original may fill a canonical slot only when source classification identifies that usable angle; preserve oblique sources as anchors");
            }
            else if (origin == "generated")
            {
                if (sources.Values.Any(source => PreparationText(source, "sha256") == hash)) throw new InvalidOperationException("An unchanged original is not a newly generated angle");
                generated.Add(view);
            }
            else throw new InvalidOperationException("View origin must be source or generated");
        }
        if (report["generationPolicy"] is JsonObject suppliedPolicy) _ = ValidateGenerationPolicy(suppliedPolicy);
        if (generated.Count > 0)
        {
            var policy = PreparationObject(report["generationPolicy"]);
            var authorization = ValidateGenerationPolicy(policy);
            foreach (var view in generated)
            {
                var receiptPath = PreparationText(view, "generationReceipt");
                RequirePreparationReceipt(receiptPath);
                if (view["generationReceiptHash"] is not null && view["generationReceiptHash"]!.GetValue<string>() != Hash(receiptPath)) throw new InvalidOperationException("Changed generation receipt");
                ValidateGenerationReceipt(ReadPreparation(receiptPath), view, sources, PreparationText(policy, "pipeline"));
                if (view["revision"]!.GetValue<int>() > authorization["maxRevisionsPerView"]!.GetValue<int>()) throw new InvalidOperationException("Per-view generation revision budget exhausted");
            }
        }
    }
    void RequirePreparationReceipt(string path)
    {
        var relative = w.Relative(path);
        if (relative.StartsWith(m.Staging + "/attempts/prepare-proofs-", StringComparison.Ordinal)) return;
        RequireTaskEvidence(relative);
    }
    Task RegisterProofSet(Stage stage, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (string.IsNullOrEmpty(m.Classification)) throw new InvalidOperationException("Classify original sources before preparing proofs");
        var sources = CurrentSourceSet(); ValidateClassification(ReadPreparation(m.Classification), sources, true);
        var input = w.Relative(Need("proof-set")); var report = ReadPreparation(input);
        ValidateProofSet(report, sources, true);
        JsonObject? previous = string.IsNullOrEmpty(m.ProofSet) ? null : ReadPreparation(m.ProofSet);
        if (report["revision"]!.GetValue<int>() != (previous?["revision"]?.GetValue<int>() ?? 0) + 1) throw new InvalidOperationException("Proof-set revision must advance exactly once");
        var views = PreparationArray(report, "views").Select(PreparationObject).ToArray();
        var priorViews = previous is null ? [] : PreparationArray(previous, "views").Select(PreparationObject).ToArray();
        var revised = new JsonArray();
        var generatedHistory = m.History.Where(item => item["event"]?.GetValue<string>() == "proof-generated-output").ToList();
        BindPreparationInput(stage, input);
        var candidateHistory = new List<JsonObject>();
        foreach (var view in views)
        {
            cancellation.ThrowIfCancellationRequested();
            var name = PreparationText(view, "view"); var path = PreparationText(view, "image"); var hash = PreparationText(view, "sha256");
            var old = priorViews.FirstOrDefault(item => PreparationText(item, "view") == name);
            var unchanged = old is not null && PreparationText(old, "sha256") == hash;
            if (unchanged)
            {
                if (view["revision"]!.GetValue<int>() != old!["revision"]!.GetValue<int>() || PreparationText(view, "origin") != PreparationText(old, "origin") || !JsonNode.DeepEquals(view["sourceIds"], old["sourceIds"])) throw new InvalidOperationException("Unchanged view must retain its candidate identity and ancestry");
            }
            else if (view["revision"]!.GetValue<int>() != (old?["revision"]?.GetValue<int>() ?? 0) + 1) throw new InvalidOperationException("A changed view must advance its revision exactly once");
            BindPreparationInput(stage, path);
            var dimensions = PreparationImage(path);
            var copied = PreparationObject(view.DeepClone());
            if (unchanged) copied["image"] = PreparationText(old!, "image");
            else
            {
                var target = stage.Attempt + "/views/" + name + Path.GetExtension(path).ToLowerInvariant();
                Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(target))!);
                File.Copy(w.Resolve(path), w.Resolve(target), false);
                copied["image"] = target;
                stage.Artifacts["view-" + name] = target;
                revised.Add(name);
                candidateHistory.Add(new JsonObject { ["event"] = "proof-candidate", ["view"] = name, ["revision"] = view["revision"]!.GetValue<int>(), ["origin"] = PreparationText(view, "origin"), ["sha256"] = hash, ["image"] = target, ["classificationHash"] = Hash(m.Classification), ["previousSha256"] = old?["sha256"]?.GetValue<string>() });
            }
            copied["width"] = dimensions.Width; copied["height"] = dimensions.Height;
            if (PreparationText(view, "origin") == "generated")
            {
                var receipt = PreparationText(view, "generationReceipt"); BindPreparationInput(stage, receipt);
                RetainGenerationOutputs(stage, ReadPreparation(receipt), Hash(receipt), generatedHistory);
                var runId = PreparationText(ReadPreparation(receipt), "runId");
                if (!m.History.Any(item => item["event"]?.GetValue<string>() == "proof-generated-view" && item["classificationHash"]?.GetValue<string>() == Hash(m.Classification) && item["view"]?.GetValue<string>() == name && item["runId"]?.GetValue<string>() == runId))
                {
                    m.History.Add(new JsonObject { ["event"] = "proof-generated-view", ["classificationHash"] = Hash(m.Classification), ["view"] = name, ["runId"] = runId, ["receiptHash"] = Hash(receipt) });
                    Save();
                }
                if (unchanged)
                {
                    if (Hash(receipt) != PreparationText(old!, "generationReceiptHash")) throw new InvalidOperationException("Unchanged view must retain generation receipt identity");
                    copied["generationReceipt"] = PreparationText(old!, "generationReceipt");
                }
                else
                {
                    var target = stage.Attempt + "/receipts/" + name + ".json";
                    Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(target))!);
                    File.Copy(w.Resolve(receipt), w.Resolve(target), false);
                    copied["generationReceipt"] = target; stage.Artifacts["receipt-" + name] = target;
                }
                copied["generationReceiptHash"] = Hash(PreparationText(copied, "generationReceipt"));
            }
            view.ReplaceWith(copied);
        }
        if (report["generationPolicy"] is JsonObject policy)
        {
            var authorization = ValidateGenerationPolicy(policy);
            if (generatedHistory.Count > authorization["maxGeneratedCandidates"]!.GetValue<int>()) throw new InvalidOperationException("Cumulative generated candidates, including rejected outputs, exceed the authorized image budget");
            if (m.History.Where(item => item["event"]?.GetValue<string>() == "proof-generated-view" && item["classificationHash"]?.GetValue<string>() == Hash(m.Classification)).GroupBy(item => item["view"]!.GetValue<string>()).Any(group => group.Select(item => item["runId"]!.GetValue<string>()).Distinct().Count() > authorization["maxRevisionsPerView"]!.GetValue<int>()))
                throw new InvalidOperationException("Cumulative per-view generation revision budget exhausted; reclassification cannot reset prior runs");
            BindPreparationInput(stage, "MEDIA.md");
            var path = PreparationText(policy, "authorization"); BindPreparationInput(stage, path);
            var target = stage.Attempt + "/generation-authorization.json";
            File.Copy(w.Resolve(path), w.Resolve(target), false);
            policy["authorization"] = target; policy["authorizationHash"] = Hash(target); stage.Artifacts["generation-authorization"] = target;
        }
        report["previousProofSetHash"] = previous is null ? null : Hash(m.ProofSet);
        report["reviewStatus"] = "pending";
        report["revisedViews"] = revised;
        var destination = stage.Attempt + "/proof-set.json";
        w.Save(destination, report); stage.Artifacts["proof-set"] = destination;
        var page = stage.Attempt + "/proof-review.html";
        var figures = string.Join("", PreparationArray(report, "views").Select(PreparationObject).Select(view => "<figure><img src=\"" + WebUtility.HtmlEncode(Path.GetRelativePath(w.Resolve(stage.Attempt), w.Resolve(PreparationText(view, "image"))).Replace('\\', '/')) + "\"><figcaption>" + WebUtility.HtmlEncode(PreparationText(view, "view") + " / " + PreparationText(view, "origin") + " / " + PreparationText(view, "sha256")) + "</figcaption></figure>"));
        var originals = string.Join("", PreparationArray(sources, "images").Select(PreparationObject).Select(image => "<figure><img src=\"" + WebUtility.HtmlEncode(Path.GetRelativePath(w.Resolve(stage.Attempt), w.Resolve(PreparationText(image, "path"))).Replace('\\', '/')) + "\"><figcaption>Original " + WebUtility.HtmlEncode(PreparationText(image, "id")) + "</figcaption></figure>"));
        File.WriteAllText(w.Resolve(page), "<!doctype html><meta charset=\"utf-8\"><title>Six-view proof review</title><style>body{font-family:sans-serif;background:#222;color:#eee}main{display:flex;flex-wrap:wrap}img{max-width:400px;max-height:400px}figure{margin:12px}pre{white-space:pre-wrap}</style><h1>Six-view proof set: human approval pending</h1><p>Inspect full-resolution files. Generated hidden surfaces are proposed interpretations. Structural checks do not certify anatomy, likeness, materials or camera alignment.</p><h2>Immutable original sources</h2><main>" + originals + "</main><h2>Current six-view selection</h2><main>" + figures + "</main><p><a href=\"proof-set.json\">Proof-set and camera data</a></p><h2>Source-only classification, hypotheses and unknowns</h2><pre>" + WebUtility.HtmlEncode(ReadPreparation(m.Classification).ToJsonString(Serialization.Json)) + "</pre>");
        stage.Artifacts["proof-review"] = page;
        foreach (var history in candidateHistory) m.History.Add(history);
        m.History.Add(new JsonObject { ["event"] = "proof-set-revision", ["revision"] = report["revision"]!.GetValue<int>(), ["proofSet"] = destination, ["sha256"] = Hash(destination), ["revisedViews"] = revised.DeepClone(), ["humanApproval"] = "pending" });
        m.ProofSet = destination;
        return Task.CompletedTask;
    }
    void RetainGenerationOutputs(Stage stage, JsonObject receipt, string receiptHash, List<JsonObject> known)
    {
        var runId = PreparationText(receipt, "runId");
        if (known.Any(item => item["runId"]?.GetValue<string>() == runId && item["receiptHash"]?.GetValue<string>() != receiptHash)) throw new InvalidOperationException("Generation run identity was reused with changed receipt content");
        var retainedReceipt = stage.Attempt + "/generated-receipts/" + receiptHash + ".json";
        if (!File.Exists(w.Resolve(retainedReceipt)))
        {
            w.Save(retainedReceipt, receipt);
            stage.Artifacts["generated-receipt-" + receiptHash] = retainedReceipt;
        }
        var outputIndex = 0;
        foreach (var node in PreparationArray(receipt, "outputs"))
        {
            var ordinal = outputIndex++;
            var output = PreparationObject(node);
            PreparationFields(output, "stagedPath", "sha256", "status", "runtimeTarget", "rejectionReason");
            var path = PreparationText(output, "stagedPath");
            var hash = PreparationText(output, "sha256"); RequireHash(hash);
            var status = PreparationText(output, "status");
            if (status is not ("staged" or "accepted" or "rejected")) throw new InvalidOperationException("Generated proof candidates cannot be promoted runtime outputs");
            if (status == "rejected") _ = PreparationText(output, "rejectionReason");
            if (Hash(path) != hash || w.Relative(path).StartsWith("assets/", StringComparison.Ordinal)) throw new InvalidOperationException("Changed or runtime-located generated candidate");
            _ = PreparationImage(path);
            BindPreparationInput(stage, path);
            if (known.Any(item => item["runId"]?.GetValue<string>() == runId && item["outputIndex"]?.GetValue<int>() == ordinal)) continue;
            var target = stage.Attempt + "/generated/" + known.Count + "-" + ordinal + Path.GetExtension(path).ToLowerInvariant();
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(target))!);
            File.Copy(w.Resolve(path), w.Resolve(target), false);
            stage.Artifacts["generated-" + known.Count] = target;
            var history = new JsonObject { ["event"] = "proof-generated-output", ["runId"] = runId, ["outputIndex"] = ordinal, ["receiptHash"] = receiptHash, ["retainedReceipt"] = retainedReceipt, ["retainedReceiptHash"] = Hash(retainedReceipt), ["sha256"] = hash, ["image"] = target, ["status"] = status, ["rejectionReason"] = output["rejectionReason"]?.GetValue<string>() };
            // A failed registration cannot erase generation that already happened.
            // Persist each retained output before later candidates or budget checks can fail.
            known.Add(history); m.History.Add(history); Save();
        }
    }
}
