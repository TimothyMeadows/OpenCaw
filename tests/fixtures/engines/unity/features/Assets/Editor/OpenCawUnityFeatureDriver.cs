using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

public sealed class OpenCawUnityFeatureBlocked : Exception
{
    public OpenCawUnityFeatureBlocked(string message) : base(message) { }
}

// Test-only observations. This type does not grant installation, service or
// human acceptance permission, and is not part of a host game's runtime API.
public sealed class OpenCawUnityFeatureContext
{
    public readonly string AssetDirectory;
    public readonly string OutputDirectory;
    public int Checks { get; private set; }
    public readonly List<string> Observations = new List<string>();

    public OpenCawUnityFeatureContext(string assetDirectory, string outputDirectory)
    {
        AssetDirectory = assetDirectory;
        OutputDirectory = outputDirectory;
    }

    public void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        ++Checks;
        Observations.Add("CHECK " + message);
    }

    public void Note(string message) { Observations.Add("NOTE " + message); }
    public void Blocked(string message) { throw new OpenCawUnityFeatureBlocked(message); }
    public string Setting(string key)
    {
        string value = Environment.GetEnvironmentVariable("OPENCAW_UNITY_FIXTURE_" + key);
        if (String.IsNullOrWhiteSpace(value)) Blocked("Missing explicit fixture setting: " + key);
        return value;
    }
    public void RequireGraphics()
    {
        if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null)
            Blocked("A real graphics device is required for this scoped fixture.");
    }
}

public static class OpenCawUnityFeatureDriver
{
    [Serializable]
    private sealed class Report
    {
        public int schemaVersion = 1;
        public string fixture = "opencaw-unity-feature";
        public string caseName;
        public string runId;
        public string inputSha256;
        public string engineVersion;
        public string status = "fail";
        public int checks;
        public string[] observations;
        public string reason;
        public string startedUtc;
        public bool fixturePlayMode;
        public bool fixtureDomainReloadDisabled;
    }

    private static Report report;
    private static OpenCawUnityFeatureContext context;
    private static readonly Stack<IEnumerator> steps = new Stack<IEnumerator>();
    private static DateTime deadline;
    private static string destination;
    private static string methodName;
    private static bool enteringPlay;
    private static bool leavingPlay;
    private static bool previousOptionsEnabled;
    private static EnterPlayModeOptions previousOptions;
    private static readonly List<string> nativeErrors = new List<string>();

    public static void Run()
    {
        try
        {
            string runId = Required("OPENCAW_UNITY_FEATURE_RUN");
            Guid parsed;
            if (!Guid.TryParseExact(runId, "D", out parsed)) throw new InvalidOperationException("Invalid invocation identity.");
            string project = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            destination = OwnedPath(project, Required("OPENCAW_UNITY_FEATURE_REPORT"));
            string output = OwnedPath(project, Required("OPENCAW_UNITY_FEATURE_OUTPUT"));
            if (File.Exists(destination)) throw new InvalidOperationException("A fresh report destination is required.");
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            Directory.CreateDirectory(output);
            string assetDirectory = "Assets/OpenCawFixtureGenerated/" + parsed.ToString("N");
            Directory.CreateDirectory(assetDirectory);
            AssetDatabase.Refresh();
            context = new OpenCawUnityFeatureContext(assetDirectory, output);
            report = new Report {
                caseName = Required("OPENCAW_UNITY_FEATURE_CASE"), runId = runId,
                inputSha256 = Required("OPENCAW_UNITY_FEATURE_INPUT_SHA256"),
                engineVersion = Application.unityVersion,
                startedUtc = DateTime.UtcNow.ToString("O"),
                fixturePlayMode = Environment.GetEnvironmentVariable("OPENCAW_UNITY_FEATURE_PLAYMODE") == "1"
            };
            methodName = Required("OPENCAW_UNITY_FEATURE_METHOD");
            int timeout;
            if (!Int32.TryParse(Required("OPENCAW_UNITY_FEATURE_TIMEOUT_MS"), out timeout) || timeout < 1000 || timeout > 600000)
                throw new InvalidOperationException("Invalid bounded feature timeout.");
            deadline = DateTime.UtcNow.AddMilliseconds(timeout);
            nativeErrors.Clear();
            Application.logMessageReceived += ObserveLog;
            previousOptionsEnabled = EditorSettings.enterPlayModeOptionsEnabled;
            previousOptions = EditorSettings.enterPlayModeOptions;
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorApplication.update += Update;
            if (report.fixturePlayMode)
            {
                // One isolated process per case. This keeps this driver alive;
                // it does not certify the host game's reload configuration.
                EditorSettings.enterPlayModeOptionsEnabled = true;
                EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
                report.fixtureDomainReloadDisabled = true;
                enteringPlay = true;
                EditorApplication.EnterPlaymode();
            }
            else StartCase();
        }
        catch (Exception error) { Finish(error); }
    }

    private static string Required(string key)
    {
        string value = Environment.GetEnvironmentVariable(key);
        if (String.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Missing runner field: " + key);
        return value;
    }
    private static string OwnedPath(string project, string value)
    {
        string full = Path.GetFullPath(value);
        string prefix = project.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        StringComparison comparison = Application.platform == RuntimePlatform.WindowsEditor ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!full.StartsWith(prefix, comparison)) throw new InvalidOperationException("Fixture output escaped the isolated project.");
        return full;
    }
    private static void StartCase()
    {
        int separator = methodName.LastIndexOf('.');
        if (separator <= 0) throw new InvalidOperationException("Invalid fixture method.");
        string typeName = methodName.Substring(0, separator);
        MethodInfo method = null;
        foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            Type type = assembly.GetType(typeName, false);
            if (type == null) continue;
            if (method != null) throw new InvalidOperationException("Ambiguous fixture type.");
            method = type.GetMethod(methodName.Substring(separator + 1), BindingFlags.Public | BindingFlags.Static,
                null, new Type[] { typeof(OpenCawUnityFeatureContext) }, null);
        }
        if (method == null) throw new OpenCawUnityFeatureBlocked("Selected native fixture method is unavailable.");
        IEnumerator enumerator = method.Invoke(null, new object[] { context }) as IEnumerator;
        if (enumerator == null) throw new InvalidOperationException("Native fixture did not return an enumerator.");
        steps.Push(enumerator);
    }
    private static void Update()
    {
        try
        {
            if (DateTime.UtcNow > deadline) throw new TimeoutException("Native feature exceeded its deadline.");
            if (leavingPlay)
            {
                if (!EditorApplication.isPlaying && !EditorApplication.isPlayingOrWillChangePlaymode) WriteReport();
                return;
            }
            if (enteringPlay)
            {
                if (!EditorApplication.isPlaying) return;
                enteringPlay = false;
                StartCase();
            }
            if (steps.Count == 0) { Finish(null); return; }
            IEnumerator current = steps.Peek();
            if (!current.MoveNext())
            {
                (current as IDisposable)?.Dispose();
                steps.Pop();
                return;
            }
            object yielded = current.Current;
            if (yielded is IEnumerator) steps.Push((IEnumerator)yielded);
            else if (yielded != null) throw new InvalidOperationException("Fixture must poll native jobs using null or nested IEnumerator yields.");
        }
        catch (Exception error) { Finish(error); }
    }
    private static void Finish(Exception error)
    {
        if (error is TargetInvocationException && error.InnerException != null) error = error.InnerException;
        while (steps.Count != 0)
        {
            try { (steps.Pop() as IDisposable)?.Dispose(); }
            catch (Exception cleanup) { if (error == null) error = cleanup; }
        }
        if (error == null && nativeErrors.Count != 0)
            error = new InvalidOperationException("Native error log: " + nativeErrors[0]);
        if (report == null)
        {
            Debug.LogException(error ?? new InvalidOperationException("Fixture setup failed."));
            EditorApplication.Exit(1);
            return;
        }
        report.status = error is OpenCawUnityFeatureBlocked ? "blocked" : error != null ? "fail" : "pass";
        report.reason = error == null ? "Selected native assertions completed; claim limits remain scoped." : error.Message;
        if (error == null && (context == null || context.Checks == 0))
        {
            report.status = "fail";
            report.reason = "Empty native assertion discovery cannot pass.";
        }
        if (EditorApplication.isPlaying || EditorApplication.isPlayingOrWillChangePlaymode)
        {
            leavingPlay = true;
            EditorApplication.ExitPlaymode();
            return;
        }
        WriteReport();
    }
    private static void WriteReport()
    {
        EditorApplication.update -= Update;
        EditorSettings.enterPlayModeOptionsEnabled = previousOptionsEnabled;
        EditorSettings.enterPlayModeOptions = previousOptions;
        try
        {
            report.checks = context == null ? 0 : context.Checks;
            report.observations = context == null ? new string[0] : context.Observations.ToArray();
            if (context != null && AssetDatabase.IsValidFolder(context.AssetDirectory) && !AssetDatabase.DeleteAsset(context.AssetDirectory))
                throw new IOException("Owned fixture asset cleanup failed.");
            // Include errors from Play Mode exit, iterator disposal and cleanup.
            if (nativeErrors.Count != 0)
            {
                report.status = "fail";
                report.reason = "Native error log: " + nativeErrors[0];
            }
            Application.logMessageReceived -= ObserveLog;
            if (File.Exists(destination)) throw new IOException("Refusing an existing native report.");
            File.WriteAllText(destination, JsonUtility.ToJson(report, true));
        }
        catch (Exception error)
        {
            Application.logMessageReceived -= ObserveLog;
            Debug.LogException(error);
            EditorApplication.Exit(1);
            return;
        }
        EditorApplication.Exit(report.status == "pass" ? 0 : report.status == "blocked" ? 78 : 1);
    }
    private static void ObserveLog(string message, string stack, LogType type)
    {
        if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert)
            nativeErrors.Add(message);
    }
}
