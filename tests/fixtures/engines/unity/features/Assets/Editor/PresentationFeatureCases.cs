using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Audio;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;
#if OPENCAW_UNITY_UGUI
using UnityEngine.EventSystems;
#endif
#if OPENCAW_UNITY_TMP
using TMPro;
#endif
#if OPENCAW_UNITY_LOCALIZATION
using UnityEngine.AddressableAssets;
using UnityEngine.Localization;
using UnityEngine.Localization.Settings;
using UnityEngine.ResourceManagement.AsyncOperations;
#endif

public sealed class OpenCawUnityFixtureFocusWindow : EditorWindow { }

public static class OpenCawUnityPresentationCases
{
    public static IEnumerator UIFocus(OpenCawUnityFeatureContext context)
    {
        context.RequireGraphics();
        var window = ScriptableObject.CreateInstance<OpenCawUnityFixtureFocusWindow>();
        try
        {
            window.titleContent = new GUIContent("OpenCaw focus fixture");
            window.ShowUtility();
            var content = new VisualElement();
            var prior = new UnityEngine.UIElements.Button { text = "Prior focus" };
            var modal = new VisualElement();
            var confirm = new UnityEngine.UIElements.Button { text = "Modal focus" };
            content.Add(prior);
            modal.Add(confirm);
            window.rootVisualElement.Add(content);
            window.rootVisualElement.Add(modal);
            window.Focus();
            yield return null;
            prior.Focus();
            yield return null;
            context.Check(prior.focusController != null && prior.focusController.focusedElement == prior,
                "Attached UI Toolkit control acquires initial focus.");
            content.SetEnabled(false);
            confirm.Focus();
            yield return null;
            context.Check(!prior.enabledInHierarchy && confirm.focusController.focusedElement == confirm,
                "Modal owns focus while underlying content is disabled.");
            modal.RemoveFromHierarchy();
            content.SetEnabled(true);
            prior.Focus();
            yield return null;
            context.Check(prior.focusController.focusedElement == prior,
                "Closing modal restores a live, enabled control.");
            prior.RemoveFromHierarchy();
            yield return null;
            context.Check(prior.panel == null,
                "Removed control is detached from its panel.");
            context.Check(window.rootVisualElement.focusController.focusedElement != prior,
                "Detached control is no longer the focus owner.");
            context.Note("Native Editor UI Toolkit focus only; runtime UIDocument input, visual layout and device navigation require player evidence.");
        }
        finally
        {
            if (window != null) window.Close();
        }
    }

    public static IEnumerator UGUIFocus(OpenCawUnityFeatureContext context)
    {
#if OPENCAW_UNITY_UGUI
        if (!EditorApplication.isPlaying) context.Blocked("uGUI selection fixture requires Play Mode.");
        var savedSystem = EventSystem.current;
        var root = new GameObject("OpenCaw uGUI fixture");
        var eventObject = new GameObject("OpenCaw EventSystem", typeof(EventSystem));
        var system = eventObject.GetComponent<EventSystem>();
        UnityEngine.UI.Button prior = null;
        try
        {
            prior = new GameObject("Prior", typeof(RectTransform), typeof(UnityEngine.UI.Button))
                .GetComponent<UnityEngine.UI.Button>();
            prior.transform.SetParent(root.transform, false);
            var modal = new GameObject("Modal", typeof(RectTransform), typeof(UnityEngine.UI.Button))
                .GetComponent<UnityEngine.UI.Button>();
            modal.transform.SetParent(root.transform, false);
            int existingCalls = 0;
            int ownedCalls = 0;
            UnityEngine.Events.UnityAction existing = () => existingCalls++;
            UnityEngine.Events.UnityAction owned = () => ownedCalls++;
            prior.onClick.AddListener(existing);
            prior.onClick.AddListener(owned);
            prior.onClick.Invoke();
            prior.onClick.RemoveListener(owned);
            prior.onClick.Invoke();
            context.Check(existingCalls == 2 && ownedCalls == 1,
                "Removing owned Button listener preserves the existing listener.");
            EventSystem.current = system;
            system.SetSelectedGameObject(prior.gameObject);
            context.Check(system.currentSelectedGameObject == prior.gameObject,
                "EventSystem owns initial selectable.");
            prior.interactable = false;
            system.SetSelectedGameObject(modal.gameObject);
            context.Check(system.currentSelectedGameObject == modal.gameObject,
                "Modal selection is explicit while underlying control is unavailable.");
            modal.gameObject.SetActive(false);
            prior.interactable = true;
            system.SetSelectedGameObject(prior.gameObject);
            context.Check(system.currentSelectedGameObject == prior.gameObject,
                "Closing modal restores valid uGUI selection.");
            prior.onClick.RemoveListener(existing);
            context.Note("Native EventSystem selection and listener ownership; does not simulate physical input, player-paired modules or layout.");
            yield return null;
        }
        finally
        {
            system.SetSelectedGameObject(null);
            UnityEngine.Object.DestroyImmediate(root);
            UnityEngine.Object.DestroyImmediate(eventObject);
            EventSystem.current = savedSystem;
        }
#else
        context.Blocked("Selected and checked com.unity.ugui package is required for native uGUI coverage.");
        yield break;
#endif
    }

    public static IEnumerator UIFontCoverage(OpenCawUnityFeatureContext context)
    {
#if OPENCAW_UNITY_TMP
        string path = context.Setting("tmpFontAsset");
        string required = context.Setting("tmpRequiredCharacters");
        var font = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(path);
        if (font == null) context.Blocked("tmpFontAsset must identify a real TMP font asset in this fixture project.");
        var enumerator = StringInfo.GetTextElementEnumerator(required);
        int inspected = 0;
        while (enumerator.MoveNext())
        {
            string element = enumerator.GetTextElement();
            for (int offset = 0; offset < element.Length;)
            {
                int scalar = char.ConvertToUtf32(element, offset);
                context.Check(font.HasCharacter(scalar), "Primary TMP font contains U+" + scalar.ToString("X"));
                inspected++;
                offset += char.IsSurrogatePair(element, offset) ? 2 : 1;
            }
        }
        context.Check(inspected > 0, "At least one explicit required Unicode scalar was checked.");
        context.Note("Primary-font lookup only; fallback traversal, TextCore shaping, atlas growth and visual readability require target-specific fixtures.");
        yield return null;
#else
        context.Blocked("Selected and checked TMP API is required for native font coverage.");
        yield break;
#endif
    }

    public static IEnumerator LocalizationLifecycle(OpenCawUnityFeatureContext context)
    {
#if OPENCAW_UNITY_LOCALIZATION
        if (!EditorApplication.isPlaying) context.Blocked("Localization SDK lifecycle fixture requires Play Mode.");
        string localeACode = context.Setting("localizationLocaleA");
        string localeBCode = context.Setting("localizationLocaleB");
        string table = context.Setting("localizationTable");
        string entry = context.Setting("localizationEntry");
        string expectedA = context.Setting("localizationExpectedA");
        string expectedB = context.Setting("localizationExpectedB");
        context.Check(localeACode != localeBCode && expectedA != expectedB,
            "Locale fixture uses distinct locale IDs and translated values.");
        var initialization = LocalizationSettings.InitializationOperation;
        while (!initialization.IsDone) yield return null;
        context.Check(initialization.Status == AsyncOperationStatus.Succeeded,
            "Actual Localization initialization succeeds.");
        var localeA = LocalizationSettings.AvailableLocales.GetLocale(new LocaleIdentifier(localeACode));
        var localeB = LocalizationSettings.AvailableLocales.GetLocale(new LocaleIdentifier(localeBCode));
        if (localeA == null || localeB == null) context.Blocked("Both required locales must exist in native Localization settings.");
        var originalLocale = LocalizationSettings.SelectedLocale;
        var reference = new LocalizedString(table, entry);
        var oldRequest = new LocalizedString(table, entry) { LocaleOverride = localeA };
        string observed = null;
        string visible = null;
        int observerCalls = 0;
        int ownedCalls = 0;
        int generation = 1;
        int staleIgnored = 0;
        bool acquired = false;
        AsyncOperationHandle<string> operation = default;
        Action<AsyncOperationHandle<string>> completion = null;
        LocalizedString.ChangeHandler observer = value => { observed = value; visible = value; observerCalls++; };
        LocalizedString.ChangeHandler owned = value => ownedCalls++;
        try
        {
            LocalizationSettings.SelectedLocale = localeA;
            reference.StringChanged += observer;
            reference.StringChanged += owned;
            while (observed != expectedA || ownedCalls == 0) yield return null;
            context.Check(observed == expectedA, "Locale A resolves through the actual table binding.");
            int originalOwnedCalls = ownedCalls;
            int originalObserverCalls = observerCalls;
            reference.StringChanged -= owned;
            operation = oldRequest.GetLocalizedStringAsync();
            Addressables.ResourceManager.Acquire(operation);
            acquired = true;
            int capturedGeneration = generation;
            generation++;
            completion = result =>
            {
                if (capturedGeneration != generation) { staleIgnored++; return; }
                visible = result.Result;
            };
            operation.Completed += completion;
            LocalizationSettings.SelectedLocale = localeB;
            while (observed != expectedB || staleIgnored == 0) yield return null;
            context.Check(operation.Status == AsyncOperationStatus.Succeeded,
                "The obsolete request also has a real successful SDK result.");
            context.Check(visible == expectedB && staleIgnored == 1,
                "Obsolete completion cannot overwrite the current locale result.");
            context.Check(ownedCalls == originalOwnedCalls && observerCalls > originalObserverCalls,
                "Removing the owned subscription preserves independent locale updates.");
            context.Note("Invalidated request generation was deliberately made stale before registering the real SDK completion; this proves rejection, not forced network ordering or cancellation.");
        }
        finally
        {
            generation++;
            reference.StringChanged -= observer;
            reference.StringChanged -= owned;
            if (acquired && operation.IsValid())
            {
                if (completion != null) operation.Completed -= completion;
                Addressables.Release(operation);
            }
            LocalizationSettings.SelectedLocale = originalLocale;
        }
#else
        context.Blocked("Selected and checked Localization/Addressables packages plus native table assets are required.");
        yield break;
#endif
    }

    public static IEnumerator AudioLifecycle(OpenCawUnityFeatureContext context)
    {
        if (!EditorApplication.isPlaying) context.Blocked("Audio playback fixture requires Play Mode.");
        string mixerPath = context.Setting("audioMixerAsset");
        string groupName = context.Setting("audioMixerGroupName");
        var mixer = AssetDatabase.LoadAssetAtPath<AudioMixer>(mixerPath);
        if (mixer == null) context.Blocked("A real native AudioMixer asset is required.");
        var groups = mixer.FindMatchingGroups(groupName).Where(group => group.name == groupName).ToArray();
        if (groups.Length != 1) context.Blocked("Select exactly one native mixer group by name.");
        var owner = new GameObject("OpenCaw audio owner", typeof(AudioSource));
        var listenerObject = new GameObject("OpenCaw audio listener", typeof(AudioListener));
        var source = owner.GetComponent<AudioSource>();
        AudioClip clip = null;
        try
        {
            int rate = AudioSettings.outputSampleRate;
            if (rate <= 0) context.Blocked("Audio output has no usable sample rate.");
            double initialDsp = AudioSettings.dspTime;
            double deadline = EditorApplication.timeSinceStartup + 3.0;
            while (AudioSettings.dspTime <= initialDsp && EditorApplication.timeSinceStartup < deadline) yield return null;
            if (AudioSettings.dspTime <= initialDsp) context.Blocked("Audio DSP clock is unavailable or suspended.");
            clip = AudioClip.Create("OpenCaw owned PCM", rate / 2, 1, rate, false);
            var samples = new float[rate / 2];
            for (int index = 0; index < samples.Length; index++) samples[index] = 0.01f * Mathf.Sin(2 * Mathf.PI * 220 * index / rate);
            context.Check(clip.SetData(samples, 0), "Known PCM is written to an actual native AudioClip.");
            source.clip = clip;
            source.outputAudioMixerGroup = groups[0];
            source.loop = true;
            source.volume = 0.1f;
            source.Play();
            int startSample = source.timeSamples;
            deadline = EditorApplication.timeSinceStartup + 2.0;
            while (source.timeSamples == startSample && EditorApplication.timeSinceStartup < deadline) yield return null;
            context.Check(source.isPlaying && source.timeSamples != startSample,
                "Actual source playback advances PCM samples.");
            context.Check(source.outputAudioMixerGroup == groups[0], "Source retains the selected native mixer route.");
            source.Stop();
            context.Check(!source.isPlaying, "Owner cancellation stops playback.");
            source.clip = null;
            source.outputAudioMixerGroup = null;
            source.loop = false;
            source.pitch = 1;
            source.spatialBlend = 0;
            context.Check(source.clip == null && source.outputAudioMixerGroup == null && !source.loop,
                "Source lease clears clip, routing and loop state before reuse.");
            source.clip = clip;
            source.Play();
            yield return null;
            context.Check(source.isPlaying, "Reset source can start a new owned request.");
            source.Stop();
            var configuration = AudioSettings.GetConfiguration();
            context.Note("Observed sample rate=" + configuration.sampleRate + ", buffer=" + configuration.dspBufferSize
                + "; configuration is not a DSP CPU measurement. Playback smoke does not certify audibility, mix quality or device interruption.");
        }
        finally
        {
            source.Stop();
            source.clip = null;
            UnityEngine.Object.DestroyImmediate(owner);
            UnityEngine.Object.DestroyImmediate(listenerObject);
            if (clip != null) UnityEngine.Object.DestroyImmediate(clip);
        }
    }

    public static IEnumerator EditorTransactions(OpenCawUnityFeatureContext context)
    {
        string scenePath = context.AssetDirectory.TrimEnd('/') + "/PresentationTransaction.unity";
        if (AssetDatabase.LoadMainAssetAtPath(scenePath) != null) throw new InvalidOperationException("Owned fixture output already exists.");
        var previous = SceneManager.GetActiveScene();
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
        OpenCawUnityPresentationProbe probe = null;
        GameObject owner = null;
        try
        {
            owner = new GameObject("OpenCaw transaction owner");
            SceneManager.MoveGameObjectToScene(owner, scene);
            probe = owner.AddComponent<OpenCawUnityPresentationProbe>();
            Undo.IncrementCurrentGroup();
            Undo.RecordObject(probe, "OpenCaw fixture owned value");
            probe.OwnedValue = 42;
            Undo.FlushUndoRecordObjects();
            Undo.PerformUndo();
            context.Check(probe.OwnedValue == 0, "Native Undo restores the original serialized value.");
            Undo.PerformRedo();
            context.Check(probe.OwnedValue == 42, "Native Redo restores the edited serialized value.");
            EditorSceneManager.MarkSceneDirty(scene);
            context.Check(EditorSceneManager.SaveScene(scene, scenePath), "Owned fixture scene saves successfully.");
            Undo.ClearUndo(probe);
            EditorSceneManager.CloseScene(scene, true);
            scene = EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Additive);
            probe = scene.GetRootGameObjects().Select(value => value.GetComponent<OpenCawUnityPresentationProbe>())
                .Single(value => value != null);
            context.Check(probe.OwnedValue == 42, "Unloaded and reopened scene preserves the real serialized component value.");
            context.Note("Owned component value transaction only; prefab/multi-object inspector and Graph Toolkit checks are separate conditional native procedures.");
            yield return null;
        }
        finally
        {
            if (probe != null) Undo.ClearUndo(probe);
            if (scene.IsValid() && scene.isLoaded) EditorSceneManager.CloseScene(scene, true);
            if (previous.IsValid() && previous.isLoaded) SceneManager.SetActiveScene(previous);
            AssetDatabase.DeleteAsset(scenePath);
        }
    }

    public static IEnumerator WebBuild(OpenCawUnityFeatureContext context)
    {
        string scene = context.Setting("webBuildScene");
        if (AssetDatabase.LoadAssetAtPath<SceneAsset>(scene) == null) context.Blocked("webBuildScene must identify a native authored fixture scene.");
        if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.WebGL, BuildTarget.WebGL))
            context.Blocked("The matching Editor's Web build support module is unavailable.");
        if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.WebGL)
            context.Blocked("Launch this isolated native case with the WebGL build target selected; batch mode must not switch targets during a build.");
        string destination = Path.Combine(context.OutputDirectory, "web-player");
        if (Directory.Exists(destination)) throw new InvalidOperationException("Web build output must be fresh.");
        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { scene },
            locationPathName = destination,
            target = BuildTarget.WebGL,
            options = BuildOptions.None
        });
        context.Check(report != null && report.summary.result == BuildResult.Succeeded,
            "The real Web build process reports success.");
        context.Check(report.summary.totalSize > 0 && report.summary.totalErrors == 0,
            "BuildReport has nonempty output and no build errors.");
        context.Check(File.Exists(Path.Combine(destination, "index.html")), "Web output includes its real entry point.");
        context.Check(Directory.GetFiles(destination, "*", SearchOption.AllDirectories).Length > 1,
            "Web output includes runtime artifacts as well as the entry point.");
        context.Note("BuildReport bytes=" + report.summary.totalSize
            + "; HTTP encoding, browser startup, runtime memory and gameplay remain not run until the emitted player is served and exercised.");
        yield return null;
    }
}
