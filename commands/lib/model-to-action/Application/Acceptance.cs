using System.Text.Json.Nodes;
using OpenCaw.ModelAction.Domain;
using static OpenCaw.ModelAction.Application.ActionValidation;
namespace OpenCaw.ModelAction.Application;

public sealed partial class Pipeline
{
    void Validate()
    {
        foreach (var (name, stage) in m.Stages)
        {
            if (stage.Status != "complete") throw new InvalidOperationException("Incomplete/interrupted action stage: " + name);
            foreach (var previous in Order.Take(System.Array.IndexOf(Order, name))) Require(previous);
        }
        if (m.Stages.TryGetValue("export", out var export)) ValidatePackage(LoadObject(export.Artifacts["package"]), export);
        if (m.Stages.TryGetValue("review", out var review)) ValidateReview(LoadObject(review.Artifacts["reviewReport"]), review, Plan());
        foreach (var approval in m.Approvals)
        {
            if (approval.Fingerprint != Fingerprint() || HashFile(approval.Evidence) != approval.EvidenceHash) throw new InvalidOperationException("Stale action approval");
            if (approval.Kind == "human") ValidateRuntime(LoadObject(approval.Evidence));
        }
    }
    void Record()
    {
        var kind = Need("kind"); var reviewer = Need("reviewer");
        if (kind is not ("action" or "independent" or "human") || string.IsNullOrWhiteSpace(reviewer)) throw new InvalidOperationException("Select action, independent or human review with a reviewer");
        var evidence = Relative(w, Need("evidence")); RequireEvidence(evidence); var receipt = LoadObject(evidence);
        Require("review"); Validate();
        if (Text(receipt, "kind") != kind || Text(receipt, "reviewer") != reviewer || Text(receipt, "decision") != "approved" || Text(receipt, "reason").Length < 8 || Text(receipt, "fingerprint") != Fingerprint()) throw new InvalidOperationException("Review receipt must bind current kind/reviewer/fingerprint/reason");
        if (kind is "action" or "human" && receipt["human"]?.GetValue<bool>() != true) throw new InvalidOperationException("Explicit human action/runtime assertion required");
        if (kind == "independent")
        {
            RequireApproval("action");
            if (reviewer.Equals(m.Actor, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Independent reviewer must differ from creator");
        }
        if (kind == "human") { RequireApproval("action"); RequireApproval("independent"); ValidateRuntime(receipt); }
        m.Approvals.RemoveAll(approval => approval.Kind == kind);
        m.Approvals.Add(new Approval(kind, reviewer, evidence, HashFile(evidence), Fingerprint(), DateTimeOffset.UtcNow));
        m.History.Add(new JsonObject { ["event"] = "approval", ["kind"] = kind, ["reviewer"] = reviewer, ["evidence"] = evidence, ["timestamp"] = DateTimeOffset.UtcNow.ToString("O") }); Save();
    }
    void ValidateRuntime(JsonObject receipt)
    {
        var runtime = receipt["runtime"]?.AsObject() ?? throw new InvalidOperationException("Human runtime review requires actual selected-engine evidence");
        if (Text(runtime, "status") != "passed" || Text(runtime, "engine") != Text(m.Engine, "effectiveEngine") || Text(runtime, "modelSha256") != HashFile(Artifact("export", "glb")) || Text(runtime, "packageSha256") != HashFile(Artifact("export", "package"))) throw new InvalidOperationException("Runtime review conflicts with current engine/model/action package");
        var records = Array(runtime, "evidence").Select(node => node!.AsObject()).ToArray();
        foreach (var kind in new[] { "runtime-test", "runtime-capture", "performance-profile" })
            if (records.Count(item => Text(item, "kind") == kind) != 1) throw new InvalidOperationException("Runtime review requires exactly one " + kind);
        foreach (var record in records)
        {
            var file = Relative(w, Text(record, "path")); RequireEvidence(file); var expected = Text(record, "sha256"); Hash(expected);
            if (!File.Exists(w.Resolve(file)) || new FileInfo(w.Resolve(file)).Length == 0 || HashFile(file) != expected) throw new InvalidOperationException("Missing/stale runtime evidence");
        }
    }
    void Promote()
    {
        Validate(); foreach (var stage in Order) Require(stage);
        foreach (var kind in new[] { "action", "independent", "human" }) RequireApproval(kind);
        var accepted = m.Approvals.Last(approval => approval.Kind == "human"); ValidateRuntime(LoadObject(accepted.Evidence));
        var destination = Relative(w, Need("destination"));
        if (!destination.StartsWith("assets/models/", StringComparison.Ordinal) || Directory.Exists(w.Resolve(destination)) || File.Exists(w.Resolve(destination))) throw new InvalidOperationException("Promotion requires a new assets/models/... destination");
        var temporary = destination + ".pending-" + Guid.NewGuid().ToString("N"); Directory.CreateDirectory(w.Resolve(temporary));
        var package = LoadObject(Artifact("export", "package")); var originalHash = HashFile(Artifact("export", "package"));
        m.History.Add(new JsonObject { ["event"] = "promotion-start", ["temporary"] = temporary, ["destination"] = destination, ["sourcePackageSha256"] = originalHash }); Save();
        try
        {
            foreach (var (field, source, filename) in new[] { ("model", Artifact("export", "glb"), "model.glb"), ("source", Artifact("export", "blend"), "source.blend"), ("motion", m.Motion, "motion-source.json") })
            {
                var expected = HashFile(source); File.Copy(w.Resolve(source), w.Resolve(temporary + "/" + filename), false);
                if (HashFile(temporary + "/" + filename) != expected) throw new InvalidOperationException("Promoted action file changed during copy");
                package[field] = new JsonObject { ["path"] = destination + "/" + filename, ["sha256"] = expected };
            }
            package["verification"] = new JsonObject { ["status"] = "accepted", ["evidence"] = accepted.Evidence, ["evidenceSha256"] = accepted.EvidenceHash, ["reviewer"] = accepted.Reviewer };
            w.Save(temporary + "/action-package.json", package);
            w.Save(temporary + "/promotion.json", new { schemaVersion = 1, sourceManifest = path, sourcePackage = Artifact("export", "package"), sourcePackageSha256 = originalHash, promotedPackageSha256 = HashFile(temporary + "/action-package.json"), approvals = m.Approvals, note = "Model/source/motion paths explicitly rebound; source ancestry and human runtime evidence retained" });
            VerifyHashes(m.Originals); VerifyHashes(m.SourceInputs); VerifyHashes(m.BaselineInputs, true);
            foreach (var stage in m.Stages.Values) { VerifyHashes(stage.Inputs); VerifyHashes(stage.Outputs); VerifyHashes(stage.ExternalInputs, true); }
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(destination))!); Directory.Move(w.Resolve(temporary), w.Resolve(destination));
            m.History.Add(new JsonObject { ["event"] = "promoted", ["destination"] = destination, ["sourcePackageSha256"] = originalHash, ["promotedPackageSha256"] = HashFile(destination + "/action-package.json"), ["timestamp"] = DateTimeOffset.UtcNow.ToString("O") }); Save();
        }
        catch (Exception error) { m.History.Add(new JsonObject { ["event"] = "promotion-failed", ["destination"] = destination, ["temporary"] = temporary, ["error"] = error.Message }); Save(); throw; }
    }
}
