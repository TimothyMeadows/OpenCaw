using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

public sealed class HephaeraFixtureState : ScriptableObject
{
    public static int Enables;
    public static int Disables;
    public static int Destructions;
    public int Value;
    private void OnEnable() { Enables++; }
    private void OnDisable() { Disables++; }
    private void OnDestroy() { Destructions++; }
}

public static class HephaeraFixture
{
    [Serializable]
    private sealed class Result
    {
        public string fixture = "hephaera-native-unity";
        public string status = "fail";
        public string engineVersion = Application.unityVersion;
        public int checks;
        public string buildStatus = "not-run";
        public string buildReason = "No build target was selected";
        public string message;
    }

    private static void Check(bool condition, string message, Result result)
    {
        if (!condition) throw new InvalidOperationException(message);
        result.checks++;
    }

    public static void Run()
    {
        var result = new Result();
        try
        {
            HephaeraFixtureState.Enables = 0;
            HephaeraFixtureState.Disables = 0;
            HephaeraFixtureState.Destructions = 0;
            var first = ScriptableObject.CreateInstance<HephaeraFixtureState>();
            Check(HephaeraFixtureState.Enables == 1, "CreateInstance did not enable once", result);
            first.Value = 17;
            string serialized = JsonUtility.ToJson(first);
            var restored = ScriptableObject.CreateInstance<HephaeraFixtureState>();
            JsonUtility.FromJsonOverwrite(serialized, restored);
            Check(restored.Value == 17, "Serialized state did not round-trip", result);
            Check(first.GetInstanceID() != restored.GetInstanceID(), "Instances shared identity", result);
            UnityEngine.Object.DestroyImmediate(first);
            UnityEngine.Object.DestroyImmediate(restored);
            Check(HephaeraFixtureState.Disables == 2, "Destruction did not disable both objects", result);
            Check(HephaeraFixtureState.Destructions == 2, "Destruction callback count changed", result);

            string targetName = Environment.GetEnvironmentVariable("HEPHAERA_FIXTURE_BUILD_TARGET");
            if (!String.IsNullOrEmpty(targetName))
            {
                BuildTarget target;
                if (!Enum.TryParse(targetName, out target)) throw new InvalidOperationException("Unknown build target");
                BuildTargetGroup group = BuildPipeline.GetBuildTargetGroup(target);
                if (!BuildPipeline.IsBuildTargetSupported(group, target))
                {
                    result.buildStatus = "blocked";
                    result.buildReason = "The selected installed Editor lacks this platform module";
                }
                else
                {
                    var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                    new GameObject("Hephaera Fixture Runner").AddComponent<HephaeraFixtureProbe>();
                    const string scenePath = "Assets/HephaeraFixtureSmoke.unity";
                    Check(EditorSceneManager.SaveScene(scene, scenePath), "Fixture scene did not save", result);
                    string output = Environment.GetEnvironmentVariable("HEPHAERA_FIXTURE_BUILD_OUTPUT");
                    if (String.IsNullOrEmpty(output)) throw new InvalidOperationException("Build output missing");
                    var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
                    {
                        scenes = new[] { scenePath },
                        locationPathName = output,
                        target = target,
                        options = BuildOptions.Development
                    });
                    Check(report.summary.result == BuildResult.Succeeded, "BuildReport did not succeed", result);
                    Check(report.summary.totalErrors == 0, "BuildReport contained errors", result);
                    result.buildStatus = "pass";
                    result.buildReason = "BuildPipeline returned a successful BuildReport";
                }
            }
            result.status = "pass";
            result.message = "Actual Unity lifecycle and state checks completed";
        }
        catch (Exception exception)
        {
            result.status = "fail";
            result.message = exception.Message;
            Debug.LogException(exception);
        }
        string destination = Environment.GetEnvironmentVariable("HEPHAERA_FIXTURE_REPORT");
        if (String.IsNullOrEmpty(destination)) throw new InvalidOperationException("Report destination missing");
        File.WriteAllText(destination, JsonUtility.ToJson(result, true));
        EditorApplication.Exit(result.status == "pass" ? 0 : 1);
    }
}
