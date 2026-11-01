using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using UnityEditor;
using UnityEditor.Compilation;
using UnityEditor.PackageManager;
using UnityEngine;

// Native Editor fixture. Online SDK acceptance is deliberately a separate,
// authorized procedure; the offline protocol simulations never run here.
public static class HephaeraUnityToolingCases
{
    private static string HashFile(string file)
    {
        using (var hash = SHA256.Create())
            return BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(file)));
    }

    public static IEnumerator PackageInventory(HephaeraUnityFeatureContext context)
    {
        if (Environment.GetCommandLineArgs().Any(argument => String.Equals(argument, "-noUpm", StringComparison.OrdinalIgnoreCase)))
            context.Blocked("UPM is disabled for this invocation; use an explicitly prepared Editor for offline request acceptance");
        context.Check(!EditorApplication.isCompiling, "Editor was compiling before inventory");
        context.Check(!EditorApplication.isUpdating, "Editor was importing before inventory");
        var required = context.Setting("RequiredPackages").Split(',')
            .Select(value => value.Trim()).Where(value => value.Length != 0).ToArray();
        context.Check(required.Length != 0, "No explicit package inventory was selected");
        context.Check(required.Distinct(StringComparer.Ordinal).Count() == required.Length,
            "Required package inventory contains duplicates");
        var project = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        var manifest = Path.Combine(project, "Packages", "manifest.json");
        var lockFile = Path.Combine(project, "Packages", "packages-lock.json");
        context.Check(File.Exists(manifest), "Fixture package manifest is missing");
        if (!File.Exists(lockFile)) context.Blocked("Resolved fixture package lock is unavailable");
        var manifestHash = HashFile(manifest);
        var lockHash = HashFile(lockFile);

        // offlineMode=true: inspect installed cache state; do not contact a
        // registry, add/remove a package or initiate an explicit resolve.
        var request = Client.List(true, true);
        context.Check(request != null, "UPM did not return a ListRequest");
        var deadline = EditorApplication.timeSinceStartup + 30.0;
        while (!request.IsCompleted && EditorApplication.timeSinceStartup < deadline)
            yield return null;
        context.Check(request.IsCompleted, "UPM inventory did not reach terminal state within 30 seconds");
        context.Check(request.Status == StatusCode.Success,
            "UPM inventory failed: " + (request.Error == null ? "unknown error" : request.Error.message));
        context.Check(request.Result != null && request.Result.Any(), "UPM returned an empty package inventory");

        var installed = new Dictionary<string, UnityEditor.PackageManager.PackageInfo>(StringComparer.Ordinal);
        foreach (var package in request.Result)
        {
            context.Check(!String.IsNullOrEmpty(package.name) && !String.IsNullOrEmpty(package.version),
                "UPM package identity/version is incomplete");
            context.Check(!installed.ContainsKey(package.name), "UPM returned duplicate package identity");
            installed.Add(package.name, package);
        }
        var registered = UnityEditor.PackageManager.PackageInfo.GetAllRegisteredPackages();
        foreach (var name in required)
        {
            context.Check(installed.ContainsKey(name), "Selected package is not installed: " + name);
            context.Check(registered.Any(package => package.name == name && package.version == installed[name].version),
                "Registered package differs from completed UPM inventory: " + name);
            context.Note("Offline installed package " + name + "@" + installed[name].version);
        }
        context.Check(HashFile(manifest) == manifestHash && HashFile(lockFile) == lockHash,
            "Read-only package inventory changed the fixture manifest or lock");
        var playerAssemblies = CompilationPipeline.GetAssemblies(AssembliesType.Player);
        context.Check(playerAssemblies.All(assembly => !assembly.sourceFiles.Any(file =>
                file.Replace('\\', '/').EndsWith("/Editor/ToolingServiceFeatureCases.cs", StringComparison.Ordinal))),
            "Editor tooling fixture leaked into a player assembly");
        context.Note("Actual native offline UPM completion and Editor/player assembly boundary checked; no online service was invoked.");
    }
}
