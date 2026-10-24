using System;
using System.Collections;
using System.IO;
using UnityEngine;

public sealed class OpenCawFixtureProbe : MonoBehaviour
{
    [Serializable]
    private sealed class Result
    {
        public string fixture = "opencaw-native-unity-player";
        public string status;
        public string engineVersion = Application.unityVersion;
        public int checks;
        public string message;
    }

    private IEnumerator Start()
    {
        var result = new Result { status = "pass", checks = 0 };
        OpenCawFixtureActor.Awakes = 0;
        OpenCawFixtureActor.Enables = 0;
        OpenCawFixtureActor.Disables = 0;
        OpenCawFixtureActor.Destructions = 0;
        var child = new GameObject("Lifecycle actor");
        var actor = child.AddComponent<OpenCawFixtureActor>();
        yield return null;
        if (OpenCawFixtureActor.Awakes != 1 || OpenCawFixtureActor.Enables != 1)
            result.status = "fail";
        else result.checks += 2;
        actor.Value = 23;
        if (actor.Value != 23) result.status = "fail";
        else result.checks++;
        actor.enabled = false;
        if (OpenCawFixtureActor.Disables != 1) result.status = "fail";
        else result.checks++;
        Destroy(child);
        yield return null;
        if (OpenCawFixtureActor.Destructions != 1 || child != null) result.status = "fail";
        else result.checks++;
        result.message = "Actual player component lifecycle and state checks";
        string destination = Environment.GetEnvironmentVariable("OPENCAW_FIXTURE_REPORT");
        if (String.IsNullOrEmpty(destination)) { Application.Quit(1); yield break; }
        File.WriteAllText(destination, JsonUtility.ToJson(result, true));
        Application.Quit(result.status == "pass" ? 0 : 1);
    }
}
