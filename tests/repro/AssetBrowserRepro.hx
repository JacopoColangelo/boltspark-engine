import boltspark.editor.EditorSession;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.inspector.AssetType;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.EngineAssetCatalog;
import boltspark.project.ProjectSession;
import boltspark.ui.AssetDragPayload;
import boltspark.ui.widgets.AssetBrowserStore;
import haxe.io.Path;

/**
 * Headless coverage for the Asset Browser's data layer: the asset type
 * registry, all-files discovery, on-demand metadata, generic file/folder
 * operations, and persisted favorites/recent/view state.
 */
class AssetBrowserRepro {
    static var root:String;
    static var checks:Int = 0;

    static function main():Void {
        root = Path.join([Sys.getCwd(), "bin", "test-results", "asset-browser-repro"]);
        deleteRecursively(root);
        sys.FileSystem.createDirectory(root);

        testRegistry();
        testEngineAssets();
        testDiscoveryAndMetadata();
        testGenericOperations();
        testFolderOperations();
        testStore();

        Sys.println('[asset-browser-repro] all ${checks} checks passed');
    }

    static function testRegistry():Void {
        var scene = AssetTypeRegistry.infoFor("Level.boltscene");
        assertTrue(scene.kind == "scene" && scene.loadable && scene.extension == "boltscene",
            "scene extension is recognized and loadable");
        var file = AssetTypeRegistry.infoFor("notes.txt");
        assertTrue(file.kind == "file" && !file.loadable,
            "unknown extension is a generic, non-loadable file");
        assertTrue(!AssetTypeRegistry.isInternal("Scenes"), "folders are not internal");
        assertTrue(AssetTypeRegistry.isInternal("Demo.boltproject"),
            "project manifest is internal");
        assertTrue(AssetTypeRegistry.isInternal("Scene.boltscene.bak"),
            "atomic-save backups are internal");
        assertTrue(AssetTypeRegistry.isInternal(".hidden"), "dot files are internal");
    }

    static function testEngineAssets():Void {
        var engine = EngineAssetCatalog.all();
        assertTrue(engine.length >= 6,
            "engine catalog should include primitives and materials");
        var meshCount = 0;
        var materialCount = 0;
        var cubePayload:Null<AssetDragPayload> = null;
        var materialPayload:Null<AssetDragPayload> = null;
        for (entry in engine) {
            assertTrue(entry.kind == AssetTypeRegistry.KIND_ENGINE,
                "catalog entry is not an engine asset");
            assertTrue(entry.folder == EngineAssetCatalog.FOLDER
                    && entry.kindLabel == AssetTypeRegistry.ENGINE_INFO_LABEL,
                "engine asset lost its Engine folder / display metadata");
            var payload = EngineAssetCatalog.dragPayload(entry);
            assertTrue(payload != null && payload.assetId.length > 0,
                "engine asset could not produce a drag payload");
            if (payload.assetType == AssetType.MeshAsset) {
                meshCount++;
                if (payload.assetId == PrimitiveMeshes.CUBE_ID) cubePayload = payload;
            } else {
                materialCount++;
                assertTrue(payload.assetType == AssetType.MaterialAsset,
                    "non-mesh engine asset is not a material");
                if (materialPayload == null) materialPayload = payload;
            }
        }
        assertTrue(meshCount >= 5 && materialCount >= 1,
            "engine catalog is missing primitives or materials");
        assertTrue(cubePayload != null && materialPayload != null,
            "representative engine payloads were not found");
        var info = AssetTypeRegistry.engineInfo();
        assertTrue(info.kind == AssetTypeRegistry.KIND_ENGINE && info.loadable,
            "engine kind is not registered as a loadable asset kind");

        assertTrue(cubePayload.assetType == AssetType.MeshAsset
                && materialPayload.assetType == AssetType.MaterialAsset,
            "engine drag payloads lost their type-aware identity");
    }

    static function testDiscoveryAndMetadata():Void {
        var projectPath = Path.join([root, "Browser Data.boltproject"]);
        var session = new ProjectSession();
        session.createProject(projectPath, "Browser Data");
        sys.io.File.saveContent(Path.join([root, "Scenes", "notes.txt"]), "hello");
        sys.FileSystem.createDirectory(Path.join([root, "Scenes", "Archive"]));
        sys.io.File.saveContent(Path.join([root, "Scenes", "Archive", "readme.md"]), "# notes");
        sys.io.File.saveContent(Path.join([root, "Browser Data.boltproject.bak"]), "stale");

        var assets = session.scanAllAssets();
        assertTrue(assets.length == 3, "scan finds scenes and generic files, skips internal files");
        var sceneCount = 0;
        var fileCount = 0;
        var active = 0;
        for (asset in assets) {
            if (asset.kind == "scene") sceneCount++;
            if (asset.kind == "file") fileCount++;
            if (asset.active) active++;
            assertTrue(asset.folder.indexOf("\\") < 0, "asset folder uses slashes");
        }
        assertTrue(sceneCount == 1 && fileCount == 2, "kinds split into scene and generic files");
        assertTrue(active == 1, "only the open scene is marked active");

        var details = session.assetDetails("Scenes/notes.txt");
        assertTrue(details.size == 5, "metadata reports real byte size");
        assertTrue(details.extension == "txt", "metadata reports extension");
        assertTrue(!details.loadable && !details.registered, "generic file is not loadable or registered");
        assertTrue(StringTools.endsWith(details.absolutePath, "notes.txt"),
            "metadata resolves the absolute path");
        assertTrue(session.isScenePath("Scenes/Main Scene.boltscene"), "scene path detection");
        assertTrue(!session.isScenePath("Scenes/notes.txt"), "generic path is not a scene");

        // The "All" folder has an empty relative path. Reveal/Copy Path must
        // resolve against the asset root instead of normalizeRelative("").
        assertTrue(StringTools.endsWith(session.assetRootPath(), "asset-browser-repro"),
            "asset root path resolves to the project directory");
        var untitled = new ProjectSession();
        assertTrue(untitled.assetRootPath() == sys.FileSystem.absolutePath(Sys.getCwd()),
            "asset root falls back to the working directory before a project exists");
    }

    static function testGenericOperations():Void {
        var session = new ProjectSession();
        session.openProject(Path.join([root, "Browser Data.boltproject"]));

        var renamed = session.renameAnyAsset("Scenes/notes.txt", "renamed");
        assertTrue(renamed == "Scenes/renamed.txt", "generic rename preserves the extension");
        assertTrue(!sys.FileSystem.exists(Path.join([root, "Scenes", "notes.txt"])),
            "old file removed after rename");
        assertTrue(sys.FileSystem.exists(Path.join([root, renamed])), "renamed file written");

        var duplicated = session.duplicateAnyAsset(renamed);
        assertTrue(duplicated != renamed && StringTools.endsWith(duplicated, ".txt"),
            "duplicate receives a unique name");

        var copied = session.copyAnyAsset(renamed, "Scenes/Archive");
        assertTrue(copied == "Scenes/Archive/renamed.txt", "copy into another folder");
        var copiedAgain = session.copyAnyAsset(renamed, "Scenes/Archive");
        assertTrue(copiedAgain == "Scenes/Archive/renamed 2.txt",
            "copy resolves a naming conflict with a suffix");

        var moved = session.moveAnyAsset(copiedAgain, "Scenes");
        assertTrue(moved != copiedAgain && StringTools.startsWith(moved, "Scenes/renamed")
            && sys.FileSystem.exists(Path.join([root, moved])),
            "generic move resolves a collision with a unique name");
        session.deleteAnyAsset(moved);
        assertTrue(!sys.FileSystem.exists(Path.join([root, moved])), "generic delete removes the file");
    }

    static function testFolderOperations():Void {
        var session = new ProjectSession();
        session.openProject(Path.join([root, "Browser Data.boltproject"]));

        // An empty parent means the Content root, not an implicit Scenes child.
        var loose = session.createFolder("", "Loose");
        assertTrue(loose == "Loose", "empty parent creates a root-level folder");
        assertTrue(sys.FileSystem.exists(Path.join([root, loose])),
            "root-level folder written on disk");

        // A real folder can hold .bak files from atomic saves; they must not
        // block recursive deletion.
        var withBackup = session.createFolder("", "WithBackup");
        sys.io.File.saveContent(Path.join([root, withBackup, "note.txt"]), "x");
        sys.io.File.saveContent(Path.join([root, withBackup, "note.txt.bak"]), "old");
        session.deleteFolder(withBackup, true);
        assertTrue(!sys.FileSystem.exists(Path.join([root, withBackup])),
            "folder with backup files deleted");

        var empty = session.createFolder("Scenes", "Empty");
        session.deleteFolder(empty, false);
        assertTrue(!sys.FileSystem.exists(Path.join([root, empty])), "empty folder deleted");

        session.newScene("Nested", "Scenes/Archive");
        var moved = session.moveFolder("Scenes/Archive", "Levels");
        assertTrue(moved == "Levels/Archive", "folder moved to a new parent");
        var sources = session.sceneSources();
        var nested = false;
        for (source in sources) if (StringTools.startsWith(source, "Levels/Archive/")) nested = true;
        assertTrue(nested, "scene manifest paths repointed after folder move");
        assertTrue(StringTools.startsWith(session.sceneSource, "Levels/Archive/"),
            "active scene source repointed after folder move");

        var threw = false;
        try {
            session.deleteFolder("Levels", true);
        } catch (error:Dynamic) {
            threw = true;
            Sys.println('[debug] delete folder error: ${Std.string(error)}');
        }
        assertTrue(!threw, "folder with scenes deleted when another scene remains");

        var single = new ProjectSession();
        single.createProject(Path.join([root, "Single.boltproject"]), "Single");
        var guard = false;
        try {
            single.deleteFolder("Scenes", true);
        } catch (_:Dynamic) {
            guard = true;
        }
        assertTrue(guard, "last remaining scene cannot be deleted with its folder");
        assertTrue(!single.canDeleteFolder("Scenes"),
            "delete pre-check rejects the folder holding the last scene");

        var selfMove = false;
        try {
            single.moveFolder("Scenes", "Scenes/Child");
        } catch (_:Dynamic) {
            selfMove = true;
        }
        assertTrue(selfMove, "folder cannot be moved into a descendant");
    }

    static function testStore():Void {
        var previous = Sys.getEnv("LOCALAPPDATA");
        var storeRoot = Path.join([root, "localappdata"]);
        sys.FileSystem.createDirectory(storeRoot);
        Sys.putEnv("LOCALAPPDATA", storeRoot);
        var store = new AssetBrowserStore();
        var loadError = store.load();
        assertTrue(loadError == null, "store reports no load error on first run");
        assertTrue(store.toggleFavorite("Scenes/Main Scene.boltscene"), "favorite added");
        store.markRecent("Scenes/Main Scene.boltscene");
        store.markRecent("Scenes/Second.boltscene");
        store.viewMode = 2;
        store.inspectorWidth = 260;
        store.showEngineAssets = true;
        assertTrue(store.save() == null, "store saves without error");

        var reloaded = new AssetBrowserStore();
        assertTrue(reloaded.load() == null, "store reloads without error");
        assertTrue(reloaded.isFavorite("Scenes/Main Scene.boltscene"), "favorite persisted");
        assertTrue(reloaded.recent.length == 2 && reloaded.recent[0] == "Scenes/Second.boltscene",
            "recent list persisted in most-recent-first order");
        assertTrue(reloaded.viewMode == 2 && reloaded.inspectorWidth == 260,
            "view preferences persisted");
        assertTrue(reloaded.showEngineAssets,
            "engine asset visibility preference persisted");
        assertTrue(!reloaded.toggleFavorite("Scenes/Main Scene.boltscene"),
            "favorite toggled off");
        Sys.putEnv("LOCALAPPDATA", previous == null ? "" : previous);
    }

    static function assertTrue(condition:Bool, message:String):Void {
        checks++;
        if (!condition) throw 'AssetBrowserRepro: ${message}';
    }

    static function deleteRecursively(path:String):Void {
        if (!sys.FileSystem.exists(path)) return;
        if (sys.FileSystem.isDirectory(path)) {
            for (entry in sys.FileSystem.readDirectory(path)) {
                deleteRecursively(Path.join([path, entry]));
            }
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }
}
