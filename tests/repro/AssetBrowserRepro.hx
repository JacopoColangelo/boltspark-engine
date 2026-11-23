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
        testImport();
        testUntitledSession();
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
        for (extension in AssetTypeRegistry.TEXTURE_EXTENSIONS) {
            var info = AssetTypeRegistry.infoFor("Waterfall." + extension.toUpperCase());
            assertTrue(info.kind == AssetTypeRegistry.KIND_TEXTURE && info.loadable,
                'texture extension ${extension} is recognized and loadable');
            assertTrue(AssetTypeRegistry.isTextureFile("dir/Waterfall." + extension),
                'texture path detection accepts ${extension}');
        }
        assertTrue(!AssetTypeRegistry.isTextureFile("notes.txt"),
            "plain text is not an importable texture");
        assertTrue(AssetTypeRegistry.filterKinds().length == 4,
            "type filter offers the texture kind");
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
            assertTrue(entry.folder == EngineAssetCatalog.MESH_FOLDER
                    || entry.folder == EngineAssetCatalog.MATERIAL_FOLDER,
                "engine asset lost its typed Engine folder");
            var payload = EngineAssetCatalog.dragPayload(entry);
            assertTrue(payload != null && payload.assetId.length > 0,
                "engine asset could not produce a drag payload");
            assertTrue(entry.folder == EngineAssetCatalog.folderFor(payload.assetType)
                    && entry.kindLabel == EngineAssetCatalog.labelFor(payload.assetType),
                "engine asset folder / type caption does not match its asset type");
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

    static function testImport():Void {
        var session = new ProjectSession();
        session.openProject(Path.join([root, "Browser Data.boltproject"]));
        // Keep the source files outside the project root so the browser scan
        // only sees the copies the importer made.
        var external = Path.join([Sys.getCwd(), "bin", "test-results", "asset-browser-external"]);
        deleteRecursively(external);
        sys.FileSystem.createDirectory(external);
        var png = Path.join([external, "Imported Rock.png"]);
        var jpg = Path.join([external, "Bricks.JPG"]);
        var text = Path.join([external, "notes.txt"]);
        writeTinyPng(png, 2, 2, 11);
        // Import core copies bytes; decoding is covered by the thumbnail path.
        sys.io.File.saveBytes(jpg, haxe.io.Bytes.ofHex("FFD8FFD9"));
        sys.io.File.saveContent(text, "not an image");

        var imported = session.importAssets([png, jpg], "");
        assertTrue(imported.length == 2, "both external files import in input order");
        assertTrue(imported[0] == "Content/Imported Rock.png",
            "imported PNG lands directly in the Content root");
        assertTrue(imported[1] == "Content/Bricks.jpg",
            "imported JPG uses a lower-case extension");
        for (source in imported) {
            assertTrue(sys.FileSystem.exists(Path.join([root, source])),
                'imported file was copied into the project: ${source}');
        }
        assertTrue(session.dirty, "import marks the project dirty");

        var textures = 0;
        var registered = 0;
        for (asset in session.scanAllAssets()) {
            if (asset.kind != AssetTypeRegistry.KIND_TEXTURE) continue;
            textures++;
            if (asset.registered) registered++;
            assertTrue(asset.extension == "png" || asset.extension == "jpg",
                "texture scan reports the real extension");
        }
        assertTrue(textures == 2 && registered == 2,
            "imported textures are discovered and registered in the browser");

        var document = haxe.Json.parse(sys.io.File.getContent(session.projectPath));
        var records:Array<Dynamic> = document.assets;
        var textureRecords = 0;
        for (record in records) {
            if (record.type != "texture") continue;
            textureRecords++;
            assertTrue(imported.indexOf(record.source) >= 0,
                "manifest texture record points at the copied file");
            assertTrue(record.id.length > 0 && record.importSettings.format != null,
                "manifest texture record has an id and import settings");
        }
        assertTrue(textureRecords == 2, "manifest persisted both texture records");

        var again = session.importAssets([png], "");
        assertTrue(again[0] == "Content/Imported Rock 2.png",
            "re-import resolves a name collision with a numeric suffix");

        var rejected = false;
        try {
            session.importAssets([text], "");
        } catch (_:Dynamic) {
            rejected = true;
        }
        assertTrue(rejected, "unsupported import extension is rejected");
        assertTrue(!sys.FileSystem.exists(Path.join([root, "Content", "notes.txt"])),
            "rejected import did not copy a file");
        var afterReject = haxe.Json.parse(sys.io.File.getContent(session.projectPath));
        assertTrue(afterReject.assets.length == records.length + 1,
            "rejected import did not write a manifest record");

        var escaped = false;
        try {
            session.importAssets([png], "../outside");
        } catch (_:Dynamic) {
            escaped = true;
        }
        assertTrue(escaped, "import rejects a folder that escapes the project root");
    }

    static function testUntitledSession():Void {
        // An untitled session uses the working directory's scratch Content
        // folder. Point cwd at a disposable directory so the repo stays clean.
        var previousCwd = Sys.getCwd();
        var scratch = Path.join([root, "untitled-scratch"]);
        var source = Path.join([root, "untitled-source.png"]);
        deleteRecursively(scratch);
        sys.FileSystem.createDirectory(scratch);
        writeTinyPng(source, 2, 2, 41);
        Sys.setCwd(scratch);
        try {
            var session = new ProjectSession();
            assertTrue(session.isUntitled(), "new session starts untitled");

            var created = session.createFolder("", "Notes");
            assertTrue(created == "Content/Notes",
                "untitled folders are created inside the scratch Content folder");
            assertTrue(sys.FileSystem.exists(Path.join([scratch, created])),
                "untitled folder was written to disk");

            var imported = session.importAssets([source], "");
            assertTrue(imported.length == 1
                    && imported[0] == "Content/untitled-source.png",
                "untitled import lands directly in the scratch Content folder");
            assertTrue(sys.FileSystem.exists(Path.join([scratch, imported[0]])),
                "untitled imported file was copied");
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, "Untitled.boltproject"])),
                "untitled import does not create a project manifest");

            var textures = 0;
            for (asset in session.scanAllAssets()) {
                if (asset.kind == AssetTypeRegistry.KIND_TEXTURE) textures++;
            }
            assertTrue(textures == 1, "untitled browser discovers the imported texture");
            var folders = session.scanFolders();
            assertTrue(folders.indexOf("Content") >= 0
                    && folders.indexOf("Content/Notes") >= 0,
                "untitled browser lists the scratch folder tree");

            session.newScene("Scratch Scene", "Scenes");
            session.persistSceneDocument();
            assertTrue(session.sceneSource == "Content/Scenes/Scratch Scene.boltscene",
                "untitled scenes live inside the scratch Content folder");
            assertTrue(sys.FileSystem.exists(session.scenePath),
                "untitled scene document was written");
            var scenes = 0;
            for (asset in session.scanAssets()) {
                if (asset.kind == AssetTypeRegistry.KIND_SCENE) scenes++;
            }
            assertTrue(scenes == 1, "untitled browser discovers the scratch scene");

            assertTrue(session.canDeleteFolder("Content/Notes"),
                "untitled folders can be deleted without a project");
            session.deleteFolder("Content/Notes", true);
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, "Content", "Notes"])),
                "untitled folder delete removes the directory");
            assertTrue(!session.canDeleteFolder("Content/Scenes"),
                "the folder holding the active untitled scene stays protected");
        } catch (error:Dynamic) {
            Sys.setCwd(previousCwd);
            throw error;
        }
        Sys.setCwd(previousCwd);
    }

    static function writeTinyPng(path:String, width:Int, height:Int, seed:Int):Void {
        var bytes = haxe.io.Bytes.alloc(width * height * 4);
        for (index in 0...width * height) {
            bytes.set(index * 4, (index * 37 + seed) & 0xFF);
            bytes.set(index * 4 + 1, (index * 71 + seed) & 0xFF);
            bytes.set(index * 4 + 2, (index * 13 + seed) & 0xFF);
            bytes.set(index * 4 + 3, 0xFF);
        }
        var output = new haxe.io.BytesOutput();
        new format.png.Writer(output).write(format.png.Tools.build32BGRA(width, height, bytes));
        sys.io.File.saveBytes(path, output.getBytes());
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
