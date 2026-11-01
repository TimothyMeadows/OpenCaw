using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.U2D;
#if HEPHAERA_UNITY_SPRITE
using UnityEditor.U2D.Sprites;
#endif
#if HEPHAERA_UNITY_TILEMAP
using UnityEngine.Tilemaps;
#endif

// These are real Editor API probes, not a simulation of a Unity process.
// Package-dependent branches stay blocked unless the isolated project's
// declared prerequisites enabled their symbol. No source file installs packages.
public static class HephaeraUnityContentCases
{
    public static IEnumerator SpriteIdentity(HephaeraUnityFeatureContext context)
    {
#if HEPHAERA_UNITY_SPRITE
        string file = context.AssetDirectory + "/identity.png";
        var texture = new Texture2D(32, 16, TextureFormat.RGBA32, false);
        try
        {
            texture.SetPixels(Enumerable.Repeat(Color.white, 32 * 16).ToArray());
            texture.Apply();
            File.WriteAllBytes(file, texture.EncodeToPNG());
        }
        finally { UnityEngine.Object.DestroyImmediate(texture); }
        AssetDatabase.ImportAsset(file, ImportAssetOptions.ForceSynchronousImport);
        var importer = AssetImporter.GetAtPath(file) as TextureImporter;
        context.Check(importer != null, "Native texture importer exists");
        importer.textureType = TextureImporterType.Sprite;
        importer.spriteImportMode = SpriteImportMode.Multiple;
        importer.SaveAndReimport();

        var factory = new SpriteDataProviderFactories();
        factory.Init();
        var provider = factory.GetSpriteEditorDataProviderFromObject(importer);
        context.Check(provider != null, "Sprite data provider exists");
        provider.InitSpriteEditorDataProvider();
        var ids = new[] { GUID.Generate(), GUID.Generate() };
        var rects = new[]
        {
            new SpriteRect { name = "left", spriteID = ids[0], rect = new Rect(0, 0, 16, 16), pivot = new Vector2(.5f, .5f), alignment = SpriteAlignment.Custom },
            new SpriteRect { name = "right", spriteID = ids[1], rect = new Rect(16, 0, 16, 16), pivot = new Vector2(.5f, .5f), alignment = SpriteAlignment.Custom }
        };
        provider.SetSpriteRects(rects);
        var names = provider.GetDataProvider<ISpriteNameFileIdDataProvider>();
        if (names == null) context.Blocked("Installed sprite provider lacks the selected name/GUID mapping API.");
        names.SetNameFileIdPairs(rects.Select(r => new SpriteNameFileIdPair(r.name, r.spriteID)));
        provider.Apply();
        importer.SaveAndReimport();
        var before = SpriteIdentities(file, context);

        // A real import change must retain both provider identity and consumed
        // native GUID/local-file-ID references, not merely sprite count.
        importer = AssetImporter.GetAtPath(file) as TextureImporter;
        provider = factory.GetSpriteEditorDataProviderFromObject(importer);
        provider.InitSpriteEditorDataProvider();
        rects = provider.GetSpriteRects();
        foreach (var rect in rects) { rect.pivot = new Vector2(.25f, .75f); rect.alignment = SpriteAlignment.Custom; }
        provider.SetSpriteRects(rects);
        provider.Apply();
        importer.SaveAndReimport();
        var after = SpriteIdentities(file, context);
        context.Check(before.Count == 2 && after.Count == 2, "Both sliced sprites survived native reimport");
        foreach (var entry in before) context.Check(after.ContainsKey(entry.Key) && after[entry.Key] == entry.Value, "Stable native identity: " + entry.Key);
        provider = factory.GetSpriteEditorDataProviderFromObject(AssetImporter.GetAtPath(file));
        provider.InitSpriteEditorDataProvider();
        var reread = provider.GetSpriteRects();
        context.Check(reread.Length == 2 && reread.Any(r => r.spriteID == ids[0]) && reread.Any(r => r.spriteID == ids[1]), "SpriteRect IDs retained");
        context.Check(reread.All(r => Vector2.Distance(r.pivot, new Vector2(.25f, .75f)) < .001f), "Reimport applied the actual pivot edit");
        context.Note("Native importer identities verified; real prefab/animation consumers require their own reload test.");
        yield return null;
#else
        context.Blocked("SpriteIdentity requires the explicitly selected 2D Sprite data-provider package and HEPHAERA_UNITY_SPRITE.");
        yield break;
#endif
    }

#if HEPHAERA_UNITY_SPRITE
    private static Dictionary<string, string> SpriteIdentities(string file, HephaeraUnityFeatureContext context)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var sprite in AssetDatabase.LoadAllAssetsAtPath(file).OfType<Sprite>())
        {
            string guid; long local;
            context.Check(AssetDatabase.TryGetGUIDAndLocalFileIdentifier(sprite, out guid, out local), "Native sprite identity available");
            result.Add(sprite.name, guid + ":" + local);
        }
        return result;
    }
#endif

    public static IEnumerator RuleTileTopology(HephaeraUnityFeatureContext context)
    {
#if HEPHAERA_UNITY_TILEMAP
        var rule = RequiredAsset<RuleTile>(context, "ContentRuleTile");
        var isolated = RequiredAsset<Sprite>(context, "ContentRuleIsolatedSprite");
        var neighbor = RequiredAsset<Sprite>(context, "ContentRuleNeighborSprite");
        context.Check(isolated != neighbor, "Declared isolated/east-neighbor outcomes differ");
        var root = new GameObject("HephaeraRuleGrid", typeof(Grid));
        var child = new GameObject("HephaeraRuleMap", typeof(Tilemap));
        child.transform.SetParent(root.transform);
        try
        {
            var map = child.GetComponent<Tilemap>();
            map.SetTile(Vector3Int.zero, rule);
            map.RefreshAllTiles();
            context.Check(map.GetSprite(Vector3Int.zero) == isolated, "Isolated topology selects its declared sprite");
            map.SetTile(Vector3Int.right, rule);
            map.RefreshAllTiles();
            context.Check(map.GetSprite(Vector3Int.zero) == neighbor, "East-neighbor topology selects its declared sprite");
            map.SetTile(Vector3Int.right, null);
            map.RefreshAllTiles();
            context.Check(map.GetSprite(Vector3Int.zero) == isolated, "Removing a neighbor restores the isolated result");
            context.Note("Only the fixture's declared isolated/east-neighbor topology was checked; artistic adjacency and other neighborhoods remain separate acceptance.");
            yield return null;
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
#else
        context.Blocked("RuleTileTopology requires explicitly selected Tilemap/Tilemap Extras packages and HEPHAERA_UNITY_TILEMAP.");
        yield break;
#endif
    }

    private sealed class AtlasPending
    {
        public readonly List<Action<SpriteAtlas>> Callbacks = new List<Action<SpriteAtlas>>();
        public AssetBundleRequest Load;
        public SpriteAtlas Atlas;
        public int Delivered;
    }

    public static IEnumerator AtlasLifecycle(HephaeraUnityFeatureContext context)
    {
        context.RequireGraphics();
        string spriteFile = RequiredAssetFile(context, "ContentSpriteBundle");
        string atlasFile = RequiredAssetFile(context, "ContentAtlasBundle");
        context.Check(spriteFile != atlasFile, "Sprite and deferred atlas bundles are separate content");
        var spriteNames = TwoDistinct(context.Setting("ContentSpriteNames"), context);
        var tags = TwoDistinct(context.Setting("ContentAtlasTags"), context);
        var pending = new Dictionary<string, AtlasPending>(StringComparer.Ordinal);
        var registered = new HashSet<string>(StringComparer.Ordinal);
        AssetBundleCreateRequest atlasOpen = null;
        AssetBundleCreateRequest spriteOpen = null;
        AssetBundle atlasBundle = null;
        AssetBundle spriteBundle = null;
        GameObject root = null;
        RenderTexture target = null;
        bool alive = true;
        Action<string, Action<SpriteAtlas>> requested = (tag, callback) =>
        {
            if (!alive || !tags.Contains(tag)) return;
            AtlasPending record;
            if (!pending.TryGetValue(tag, out record)) { record = new AtlasPending(); pending.Add(tag, record); }
            if (record.Atlas != null) { callback(record.Atlas); record.Delivered++; }
            else record.Callbacks.Add(callback);
            if (atlasOpen == null) atlasOpen = AssetBundle.LoadFromFileAsync(atlasFile);
        };
        Action<SpriteAtlas> observed = atlas => { if (alive && atlas != null && tags.Contains(atlas.tag)) registered.Add(atlas.tag); };
        SpriteAtlasManager.atlasRequested += requested;
        SpriteAtlasManager.atlasRegistered += observed;
        try
        {
            double deadline = EditorApplication.timeSinceStartup + 45;
            spriteOpen = AssetBundle.LoadFromFileAsync(spriteFile);
            while (!spriteOpen.isDone) { CheckDeadline(context, deadline, "Opening sprite bundle"); yield return null; }
            spriteBundle = spriteOpen.assetBundle;
            context.Check(spriteBundle != null, "Native sprite bundle loaded");
            // Start both requests before awaiting either; no shared handle is overwritten.
            var sprites = spriteNames.Select(n => spriteBundle.LoadAssetAsync<Sprite>(n)).ToArray();
            while (sprites.Any(r => !r.isDone)) { CheckDeadline(context, deadline, "Loading two late-bound sprites"); yield return null; }
            root = new GameObject("HephaeraAtlasFixture");
            var cameraObject = new GameObject("Camera", typeof(Camera));
            cameraObject.transform.SetParent(root.transform);
            var camera = cameraObject.GetComponent<Camera>();
            camera.enabled = false;
            camera.orthographic = true;
            camera.orthographicSize = 3;
            camera.transform.position = new Vector3(0, 0, -10);
            target = new RenderTexture(64, 64, 24);
            context.Check(target.Create(), "Atlas test render target created");
            camera.targetTexture = target;
            for (int i = 0; i < sprites.Length; i++)
            {
                context.Check(sprites[i].asset is Sprite, "Native late-bound sprite loaded: " + spriteNames[i]);
                var actor = new GameObject("Sprite" + i, typeof(SpriteRenderer));
                actor.transform.SetParent(root.transform);
                actor.transform.position = new Vector3(i - .5f, 0, 0);
                actor.GetComponent<SpriteRenderer>().sprite = (Sprite)sprites[i].asset;
            }
            while (registered.Count != 2 || pending.Count != 2 || pending.Values.Any(p => p.Delivered == 0))
            {
                CheckDeadline(context, deadline, "Actual late-binding requests/registrations; rebuild deferred fixture content if no requests occur");
                if (atlasOpen != null && atlasOpen.isDone && atlasBundle == null)
                {
                    atlasBundle = atlasOpen.assetBundle;
                    context.Check(atlasBundle != null, "Native atlas bundle loaded");
                }
                if (atlasBundle != null)
                {
                    foreach (var entry in pending.ToArray())
                    {
                        var record = entry.Value;
                        if (record.Load == null) record.Load = atlasBundle.LoadAssetAsync<SpriteAtlas>(entry.Key);
                        if (!record.Load.isDone || record.Atlas != null) continue;
                        record.Atlas = record.Load.asset as SpriteAtlas;
                        context.Check(record.Atlas != null && record.Atlas.tag == entry.Key, "Loaded atlas matches the requested tag");
                        var callbacks = record.Callbacks.ToArray();
                        record.Callbacks.Clear();
                        foreach (var callback in callbacks) { callback(record.Atlas); record.Delivered++; }
                    }
                }
                RenderCamera(context, camera, target);
                yield return null;
            }
            context.Check(pending.Values.Sum(p => p.Delivered) >= 2, "Every observed atlas request received its registration callback");
            context.Check(pending.Values.All(p => p.Callbacks.Count == 0), "No outstanding callback remains");
            context.Note("Native two-atlas late binding observed. Same-tag coalescing, failure injection, teardown-in-flight and Addressables release still require the selected player's lifecycle scenarios.");
        }
        finally
        {
            alive = false;
            SpriteAtlasManager.atlasRequested -= requested;
            SpriteAtlasManager.atlasRegistered -= observed;
            foreach (var record in pending.Values) record.Callbacks.Clear();
            if (root != null) UnityEngine.Object.DestroyImmediate(root);
            if (target != null) { target.Release(); UnityEngine.Object.DestroyImmediate(target); }
            if (spriteBundle != null) spriteBundle.Unload(true);
            else UnloadWhenReady(spriteOpen);
            if (atlasBundle != null) atlasBundle.Unload(true);
            else UnloadWhenReady(atlasOpen);
        }
    }

    private static void UnloadWhenReady(AssetBundleCreateRequest request)
    {
        if (request == null) return;
        if (request.isDone) { if (request.assetBundle != null) request.assetBundle.Unload(true); }
        else request.completed += operation => { if (request.assetBundle != null) request.assetBundle.Unload(true); };
    }

    public static IEnumerator Physics3D(HephaeraUnityFeatureContext context)
    {
        var scene = SceneManager.CreateScene("HephaeraPhysics3D_" + Guid.NewGuid().ToString("N"), new CreateSceneParameters(LocalPhysicsMode.Physics3D));
        try
        {
            var world = scene.GetPhysicsScene();
            context.Check(world.IsValid(), "Isolated native 3D physics world exists");
            var floor = new GameObject("Floor", typeof(BoxCollider));
            SceneManager.MoveGameObjectToScene(floor, scene);
            floor.transform.position = new Vector3(0, -.5f, 0);
            floor.GetComponent<BoxCollider>().size = new Vector3(20, 1, 20);
            var actor = new GameObject("Body", typeof(BoxCollider), typeof(Rigidbody));
            SceneManager.MoveGameObjectToScene(actor, scene);
            actor.transform.position = new Vector3(0, 3, 0);
            var body = actor.GetComponent<Rigidbody>();
            body.position = actor.transform.position;
            Physics.SyncTransforms();
            for (int i = 0; i < 120; i++) world.Simulate(.02f);
            context.Check(body.position.y > .35f && body.position.y < .75f, "3D body fell and made bounded floor contact");
            RaycastHit hit;
            context.Check(world.Raycast(new Vector3(5, 2, 0), Vector3.down, out hit, 5, ~0, QueryTriggerInteraction.Ignore) && hit.collider == floor.GetComponent<BoxCollider>(), "3D query found the owned floor");
            body.Sleep();
            context.Check(body.IsSleeping(), "Dynamic body entered sleep");
            float before = body.position.x;
            body.AddForce(Vector3.right * 2, ForceMode.Impulse);
            world.Simulate(.02f);
            context.Check(!body.IsSleeping() && body.position.x > before, "Nonzero AddForce woke and moved the eligible sleeping body");
            yield return null;
        }
        finally { EditorSceneManager.CloseScene(scene, true); }
    }

    public static IEnumerator Physics2D(HephaeraUnityFeatureContext context)
    {
        var scene = SceneManager.CreateScene("HephaeraPhysics2D_" + Guid.NewGuid().ToString("N"), new CreateSceneParameters(LocalPhysicsMode.Physics2D));
        try
        {
            var world = scene.GetPhysicsScene2D();
            context.Check(world.IsValid(), "Isolated native classic 2D physics world exists");
            var floor = new GameObject("Floor", typeof(BoxCollider2D));
            SceneManager.MoveGameObjectToScene(floor, scene);
            floor.transform.position = new Vector3(0, -.5f, 0);
            floor.GetComponent<BoxCollider2D>().size = new Vector2(20, 1);
            var actor = new GameObject("Body", typeof(BoxCollider2D), typeof(Rigidbody2D));
            SceneManager.MoveGameObjectToScene(actor, scene);
            actor.transform.position = new Vector3(0, 3, 0);
            var body = actor.GetComponent<Rigidbody2D>();
            body.position = actor.transform.position;
            Physics2D.SyncTransforms();
            for (int i = 0; i < 120; i++) context.Check(world.Simulate(.02f), "Classic 2D simulation advanced");
            context.Check(body.position.y > .35f && body.position.y < .75f, "Classic 2D body fell and made bounded floor contact");
            var filter = new ContactFilter2D();
            filter.NoFilter();
            var hits = new RaycastHit2D[4];
            int count = world.Raycast(new Vector2(5, 2), Vector2.down, 5, filter, hits);
            context.Check(count > 0 && count < hits.Length && hits.Take(count).Any(h => h.collider == floor.GetComponent<BoxCollider2D>()), "Bounded classic 2D query found the floor without saturation");
            body.Sleep();
            body.WakeUp();
            float before = body.position.x;
            body.AddForce(Vector2.right * 2, ForceMode2D.Impulse);
            context.Check(world.Simulate(.02f), "Classic 2D impulse simulation advanced");
            context.Check(body.position.x > before, "Classic 2D impulse changed the native body state");
            context.Note("This exercises Rigidbody2D, not a newer explicitly selected Physics Core implementation.");
            yield return null;
        }
        finally { EditorSceneManager.CloseScene(scene, true); }
    }

    public static IEnumerator NavigationCancellation(HephaeraUnityFeatureContext context)
    {
        if (NavMesh.GetSettingsCount() == 0) context.Blocked("No native agent build settings are configured.");
        var settings = NavMesh.GetSettingsByIndex(0);
        var origin = new Vector3(10000, 0, 10000);
        var sources = new List<NavMeshBuildSource>
        {
            new NavMeshBuildSource { shape = NavMeshBuildSourceShape.Box, transform = Matrix4x4.TRS(origin - Vector3.up * .25f, Quaternion.identity, Vector3.one), size = new Vector3(10, .5f, 10), area = 0 }
        };
        var data = NavMeshBuilder.BuildNavMeshData(settings, sources, new Bounds(origin, new Vector3(20, 10, 20)), Vector3.zero, Quaternion.identity);
        context.Check(data != null, "Native bounded NavMesh data baked");
        var instance = NavMesh.AddNavMeshData(data);
        GameObject actor = null;
        try
        {
            NavMeshHit start;
            context.Check(NavMesh.SamplePosition(origin, out start, 2, NavMesh.AllAreas), "Baked fixture contains a usable agent location");
            var path = new NavMeshPath();
            context.Check(NavMesh.CalculatePath(start.position, origin + Vector3.right * 3, NavMesh.AllAreas, path) && path.status == NavMeshPathStatus.PathComplete, "Reachable destination has a complete native path");
            var missing = new NavMeshPath();
            bool found = NavMesh.CalculatePath(start.position, origin + Vector3.right * 100, NavMesh.AllAreas, missing);
            context.Check(!found || missing.status != NavMeshPathStatus.PathComplete, "Unavailable destination never reports complete arrival");
            actor = new GameObject("HephaeraNavAgent");
            actor.transform.position = start.position;
            var agent = actor.AddComponent<NavMeshAgent>();
            agent.agentTypeID = settings.agentTypeID;
            if (!agent.Warp(start.position) || !agent.isOnNavMesh) context.Blocked("This Editor mode cannot activate the native fixture agent; run the selected Play Mode/player scenario.");
            context.Check(agent.SetPath(path), "Agent accepted an actual native path");
            context.Check(agent.hasPath, "Agent owns the assigned path before cancellation");
            agent.ResetPath();
            context.Check(!agent.hasPath && !agent.pathPending, "ResetPath discarded the assigned path");
            agent.enabled = false;
            yield return null;
            context.Check(!agent.enabled, "Disabled agent remained torn down after an Editor update");
            context.Note("Synchronous path and agent-reset checks only. Delayed callbacks, carving, custom links and scene unloading need actual Play Mode/player acceptance.");
        }
        finally
        {
            if (actor != null) UnityEngine.Object.DestroyImmediate(actor);
            instance.Remove();
            UnityEngine.Object.DestroyImmediate(data);
        }
    }

    public static IEnumerator ShaderCompilation(HephaeraUnityFeatureContext context)
    {
        context.RequireGraphics();
        string asset = RequiredAssetFile(context, "ContentShader");
        AssetDatabase.ImportAsset(asset, ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);
        var shader = AssetDatabase.LoadAssetAtPath<Shader>(asset);
        context.Check(shader != null && shader.isSupported, "Selected native shader is supported on this Editor graphics API");
        var material = new Material(shader);
        try
        {
            context.Check(material.passCount > 0, "Native material exposes at least one pass");
            for (int pass = 0; pass < material.passCount; pass++)
            {
                ShaderUtil.CompilePass(material, pass, true);
                context.Check(ShaderUtil.IsPassCompiled(material, pass), "Actual Editor shader pass compiled: " + pass);
            }
            foreach (var message in ShaderUtil.GetShaderMessages(shader))
                context.Check(message.severity != UnityEditor.Rendering.ShaderCompilerMessageSeverity.Error, "Shader compiler: " + message.message);
            context.Note("Compiled the configured material's current keyword set on this Editor graphics API; stripping, other variants, player platforms and visuals remain separate.");
            yield return null;
        }
        finally { UnityEngine.Object.DestroyImmediate(material); }
    }

    public static IEnumerator RenderingConfiguration(HephaeraUnityFeatureContext context)
    {
        context.RequireGraphics();
        var asset = QualitySettings.renderPipeline != null ? QualitySettings.renderPipeline : GraphicsSettings.defaultRenderPipeline;
        string actual = asset == null ? "builtin" : asset.GetType().FullName;
        context.Check(context.Setting("ContentExpectedPipeline") == actual, "Effective Quality/Graphics pipeline matches declared fixture selection: " + actual);
        var root = new GameObject("HephaeraRenderCamera", typeof(Camera));
        RenderTexture target = null;
        var previousActive = RenderTexture.active;
        try
        {
            var camera = root.GetComponent<Camera>();
            camera.enabled = false;
            camera.cullingMask = 0;
            camera.clearFlags = CameraClearFlags.SolidColor;
            target = new RenderTexture(64, 64, 24);
            context.Check(target.Create(), "Initial offscreen camera resource created");
            camera.targetTexture = target;
            camera.backgroundColor = Color.red;
            RenderCamera(context, camera, target);
            Color first = ReadCenter(target);
            camera.backgroundColor = Color.green;
            RenderCamera(context, camera, target);
            Color second = ReadCenter(target);
            context.Check(Vector3.Distance(new Vector3(first.r, first.g, first.b), new Vector3(second.r, second.g, second.b)) > .2f, "Real rendered output changed between camera clear colors");
            camera.targetTexture = null;
            target.Release();
            context.Check(!target.IsCreated(), "Old render resource released before resize");
            UnityEngine.Object.DestroyImmediate(target);
            target = new RenderTexture(128, 96, 24);
            context.Check(target.Create(), "Resized offscreen camera resource created");
            camera.targetTexture = target;
            RenderCamera(context, camera, target);
            context.Check(target.width == 128 && target.height == 96 && ReadCenter(target).g > .1f, "Resized target contains actual rendered camera output");
            context.Note("Bounded offscreen camera/resource smoke only; custom graph passes, migration parity, renderer features, visual approval and target GPU budgets require their own captures/player runs.");
            yield return null;
        }
        finally
        {
            RenderTexture.active = previousActive;
            UnityEngine.Object.DestroyImmediate(root);
            if (target != null) { target.Release(); UnityEngine.Object.DestroyImmediate(target); }
        }
    }

    private static void RenderCamera(HephaeraUnityFeatureContext context, Camera camera, RenderTexture target)
    {
        var pipeline = QualitySettings.renderPipeline != null ? QualitySettings.renderPipeline : GraphicsSettings.defaultRenderPipeline;
        if (pipeline == null) { camera.Render(); return; }
#if UNITY_2022_2_OR_NEWER
        var request = new RenderPipeline.StandardRequest { destination = target };
        if (!RenderPipeline.SupportsRenderRequest(camera, request)) context.Blocked("Selected SRP does not support this native StandardRequest fixture.");
        RenderPipeline.SubmitRenderRequest(camera, request);
#else
        context.Blocked("This SRP version needs a version-qualified native render-request fixture.");
#endif
    }

    private static Color ReadCenter(RenderTexture target)
    {
        var previous = RenderTexture.active;
        var image = new Texture2D(1, 1, TextureFormat.RGBA32, false);
        try
        {
            RenderTexture.active = target;
            image.ReadPixels(new Rect(target.width / 2, target.height / 2, 1, 1), 0, 0);
            image.Apply();
            return image.GetPixel(0, 0);
        }
        finally { RenderTexture.active = previous; UnityEngine.Object.DestroyImmediate(image); }
    }

    private static T RequiredAsset<T>(HephaeraUnityFeatureContext context, string setting) where T : UnityEngine.Object
    {
        var value = AssetDatabase.LoadAssetAtPath<T>(RequiredAssetFile(context, setting));
        if (value == null) context.Blocked("Required native asset is unavailable or has the wrong type: " + setting);
        return value;
    }

    private static string RequiredAssetFile(HephaeraUnityFeatureContext context, string setting)
    {
        string asset = context.Setting(setting).Replace('\\', '/');
        string root = Path.GetFullPath("Assets");
        string file = Path.GetFullPath(asset);
        var comparison = Path.DirectorySeparatorChar == '\\' ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!asset.StartsWith("Assets/", StringComparison.Ordinal) || asset.Split('/').Any(part => part == "..") || !file.StartsWith(root + Path.DirectorySeparatorChar, comparison) || !File.Exists(file))
            context.Blocked("Required fixture content must be an existing project-local Assets file: " + setting);
        if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) context.Blocked("Linked fixture content is unsupported: " + setting);
        var directory = new DirectoryInfo(Path.GetDirectoryName(file));
        while (directory != null && directory.FullName.StartsWith(root, comparison))
        {
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) context.Blocked("Linked fixture content directory is unsupported: " + setting);
            if (string.Equals(directory.FullName, root, comparison)) break;
            directory = directory.Parent;
        }
        return asset;
    }

    private static string[] TwoDistinct(string text, HephaeraUnityFeatureContext context)
    {
        var values = text.Split(',').Select(s => s.Trim()).ToArray();
        context.Check(values.Length == 2 && values.All(s => s.Length > 0) && values.Distinct(StringComparer.Ordinal).Count() == 2, "Fixture declares two distinct names/tags");
        return values;
    }

    private static void CheckDeadline(HephaeraUnityFeatureContext context, double deadline, string operation)
    {
        context.Check(EditorApplication.timeSinceStartup < deadline, "Bounded native operation completed: " + operation);
    }
}
