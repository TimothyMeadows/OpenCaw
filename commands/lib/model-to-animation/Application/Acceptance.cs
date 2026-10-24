using System.Text.Json.Nodes;
using OpenCaw.ModelAnimation.Domain;
using static OpenCaw.ModelAnimation.Application.MotionValidation;
namespace OpenCaw.ModelAnimation.Application;

public sealed partial class Pipeline
{
    void Record()
    {
        var kind = Need("kind");
        if (kind is not ("rig" or "motion" or "independent" or "human"))
            throw new InvalidOperationException("Approval kind must be rig, motion, independent or human");
        var reviewer = Need("reviewer");
        if (string.IsNullOrWhiteSpace(reviewer))
            throw new InvalidOperationException("Reviewer required");
        var evidence = Relative(w, Need("evidence"));
        RequireEvidence(evidence);
        var receipt = LoadObject(evidence);
        if (Text(receipt, "kind") != kind || Text(receipt, "reviewer") != reviewer || Text(receipt, "decision") != "approved" || Text(receipt, "reason").Length < 8 || Text(receipt, "fingerprint") != Fingerprint(kind))
            throw new InvalidOperationException("Approval receipt does not bind current kind, reviewer, reason and fingerprint");
        if (kind is "rig" or "motion" or "human" && receipt["human"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("This approval requires an explicit human assertion");
        if (kind == "rig")
            Require("rig");
        else
        {
            Require("review");
            Validate();
        }
        if (kind == "independent")
        {
            RequireApproval("motion");
            if (reviewer.Equals(m.Actor, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Independent reviewer must differ from creator");
        }
        if (kind == "human")
        {
            RequireApproval("motion");
            RequireApproval("independent");
            ValidateRuntimeAcceptance(receipt);
        }
        m.Approvals.RemoveAll(a => a.Kind == kind);
        m.Approvals.Add(new Approval(kind, reviewer, evidence, HashFile(evidence), Fingerprint(kind), DateTimeOffset.UtcNow));
        m.History.Add(new()
        {
            ["event"] = "approval",
            ["kind"] = kind,
            ["reviewer"] = reviewer,
            ["evidence"] = evidence,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O")
        });
        Save();
    }
    void ValidateRuntimeAcceptance(JsonObject receipt)
    {
        var runtime = receipt["runtime"]?.AsObject() ?? throw new InvalidOperationException("Human runtime acceptance requires actual selected-engine evidence");
        if (Text(runtime, "status") != "passed" || Text(runtime, "engine") != Text(m.Engine, "effectiveEngine") || Text(runtime, "modelSha256") != HashFile(Artifact("export", "glb")) || Text(runtime, "packageSha256") != HashFile(Artifact("export", "package")))
            throw new InvalidOperationException("Runtime acceptance conflicts with current engine/export identities");
        var evidence = Array(runtime, "evidence").Select(node => node!.AsObject()).ToArray();
        foreach (var kind in new[] { "runtime-test", "runtime-capture", "performance-profile" })
            if (!evidence.Any(item => Text(item, "kind") == kind))
                throw new InvalidOperationException("Runtime acceptance omits " + kind);
        foreach (var item in evidence)
        {
            var file = Relative(w, Text(item, "path"));
            RequireEvidence(file);
            var hash = Text(item, "sha256");
            MotionValidation.Hash(hash);
            if (!File.Exists(w.Resolve(file)) || new FileInfo(w.Resolve(file)).Length == 0 || HashFile(file) != hash)
                throw new InvalidOperationException("Missing/stale runtime acceptance artifact");
        }
    }
    void Promote()
    {
        Validate();
        foreach (var name in Order)
            Require(name);
        foreach (var kind in new[] { "rig", "motion", "independent", "human" })
            RequireApproval(kind);
        var accepted = m.Approvals.Last(approval => approval.Kind == "human" && approval.Fingerprint == Fingerprint("human"));
        ValidateRuntimeAcceptance(LoadObject(accepted.Evidence));
        var destination = Relative(w, Need("destination"));
        if (!destination.StartsWith("assets/models/", StringComparison.Ordinal) || Directory.Exists(w.Resolve(destination)) || File.Exists(w.Resolve(destination)))
            throw new InvalidOperationException("Promotion requires a new assets/models/... destination");
        var temporary = destination + ".pending-" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(w.Resolve(temporary));
        var package = LoadObject(Artifact("export", "package"));
        var originalPackageHash = HashFile(Artifact("export", "package"));
        m.History.Add(new()
        {
            ["event"] = "promotion-start",
            ["destination"] = destination,
            ["temporary"] = temporary,
            ["sourcePackageSha256"] = originalPackageHash
        });
        Save();
        try
        {
            foreach (var pair in new[] { ("model", "glb", "model.glb"), ("source", "blend", "source.blend") })
            {
                var source = Artifact("export", pair.Item2);
                var target = temporary + "/" + pair.Item3;
                var expected = HashFile(source);
                File.Copy(w.Resolve(source), w.Resolve(target), false);
                if (HashFile(target) != expected)
                    throw new InvalidOperationException("Promoted copy hash mismatch");
                package[pair.Item1]!["path"] = destination + "/" + pair.Item3;
            }
            package["verification"] = new JsonObject { ["status"] = "accepted", ["evidence"] = accepted.Evidence, ["evidenceSha256"] = accepted.EvidenceHash, ["reviewer"] = accepted.Reviewer };
            w.Save(temporary + "/motion-package.json", package);
            w.Save(temporary + "/promotion.json", new
            {
                schemaVersion = 1,
                sourceManifest = path,
                sourcePackage = Artifact("export", "package"),
                sourcePackageSha256 = originalPackageHash,
                promotedPackageSha256 = HashFile(temporary + "/motion-package.json"),
                pathRebinding = new
                {
                    model = destination + "/model.glb",
                    source = destination + "/source.blend"
                },
                approvals = m.Approvals
            });
            foreach (var stage in m.Stages.Values)
            {
                VerifyHashes(stage.Inputs);
                VerifyHashes(stage.Outputs);
                VerifyHashes(stage.ExternalInputs, true);
            }
            VerifyHashes(m.Originals);
            VerifyHashes(m.SourceInputs);
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(destination))!);
            Directory.Move(w.Resolve(temporary), w.Resolve(destination));
            m.History.Add(new()
            {
                ["event"] = "promoted",
                ["destination"] = destination,
                ["sourcePackageSha256"] = originalPackageHash,
                ["packageSha256"] = HashFile(destination + "/motion-package.json"),
                ["timestamp"] = DateTimeOffset.UtcNow.ToString("O")
            });
            Save();
        }
        catch (Exception e) { m.History.Add(new() { ["event"] = "promotion-failed", ["destination"] = destination, ["temporary"] = temporary, ["error"] = e.Message }); Save(); throw; }
    }
}
