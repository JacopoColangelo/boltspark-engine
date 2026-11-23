package boltspark.project;

import boltspark.editor.EditorSession;
import haxe.io.Path;

/** One asset discovered under the project root for the Asset Browser. */
typedef AssetFileInfo = {
    /** Project-relative, slash-separated path. */
    var source:String;
    var name:String;
    var folder:String;
    var kind:String;
    var active:Bool;
    var registered:Bool;
    /** Lower-case extension without the dot ("" for extensionless files). */
    var extension:String;
    /** Human-readable type label from AssetTypeRegistry. */
    var kindLabel:String;
    /** True only when the engine has a real loader for this file. */
    var loadable:Bool;
};

/** One validated external file waiting to be copied into the project. */
typedef PendingImport = {
    var from:String;
    var destination:String;
    var extension:String;
};

/** On-demand metadata for one asset, fetched for the inspector only. */
typedef AssetDetails = {
    var source:String;
    var name:String;
    var folder:String;
    var kind:String;
    var kindLabel:String;
    var extension:String;
    var loadable:Bool;
    var registered:Bool;
    var active:Bool;
    /** Absolute path on disk. */
    var absolutePath:String;
    /** Byte length, or -1 when the file disappeared. */
    var size:Int;
    /** Last-modified epoch seconds, or -1 when unavailable. */
    var modified:Float;
};

/**
 * Renderer-independent controller for the on-disk project and scene documents.
 *
 * `project/` already owns the versioned contracts and atomic storage; this
 * class owns the missing session layer: current paths, durable documents,
 * project-relative path resolution, dirty state, and the mapping to and from
 * the renderer-independent `EditorSession`. Native dialogs and Heaps scene
 * views deliberately stay outside this class so it can run in headless tests.
 */
class ProjectSession {
    public static inline var PROJECT_EXT:String = "boltproject";
    public static inline var SCENE_EXT:String = "boltscene";
    /** Default destination for external imports: the Content root, no extra subfolder. */
    public static inline var TEXTURE_FOLDER:String = "Content";

    public var project(default, null):ProjectDocument;
    public var scene(default, null):SceneDocument;
    /** Project-relative, slash-separated path of the active scene. */
    public var sceneSource(default, null):String = "";
    /** Absolute path to the project manifest; empty for an untitled project. */
    public var projectPath(default, null):String = "";
    /** Absolute path to the active scene document. */
    public var scenePath(default, null):String = "";
    public var dirty(default, null):Bool = false;
    /** History revision at the last save; edits since then mean unsaved work. */
    public var savedRevision:Int = 0;
    /** Fired whenever title-relevant state changes. */
    public var onStateChanged:Null<Void->Void>;

    public function new() {
        resetDocuments();
    }

    /** Start a fresh untitled project with a single scene document. */
    public function resetDocuments():Void {
        project = new ProjectDocument(StableId.create("project"), "Untitled Project");
        scene = new SceneDocument(StableId.create("scene"), "Main Scene");
        sceneSource = "Scenes/" + safeFileName(scene.name) + "." + SCENE_EXT;
        projectPath = "";
        scenePath = "";
        dirty = false;
        savedRevision = 0;
        stateChanged();
    }

    /**
     * Create a new project at `path` (an absolute `*.boltproject` path) and
     * save its manifest plus initial scene immediately. Existing files are
     * never overwritten by this path.
     */
    public function createProject(path:String, name:String):Void {
        var trimmed = StringTools.trim(name);
        if (trimmed.length == 0) throw "Project name cannot be empty.";
        path = withExtension(path, PROJECT_EXT);
        requireExtension(path, PROJECT_EXT);
        var absolute = sys.FileSystem.absolutePath(path);
        if (sys.FileSystem.exists(absolute)) {
            throw 'Project already exists: ${absolute}';
        }

        // A new project starts with a fresh empty scene; the current editor
        // graph is not carried over (Save As is the path that persists it).
        // This first scene uses a fixed source: a fresh project must not be
        // renamed just because another project shares the same directory.
        project.name = trimmed;
        project.assets.resize(0);
        savedRevision = 0;
        projectPath = absolute;
        var allocated = { name: "Main Scene", source: "Scenes/Main Scene.boltscene" };
        scene = new SceneDocument(StableId.create("scene"), allocated.name);
        sceneSource = allocated.source;
        var _ = bindSceneAsset();
        scenePath = resolvePath(sceneSource);
        saveDocuments();
    }

    /** Load a project manifest and its default scene from disk. */
    public function openProject(path:String):Void {
        path = withExtension(path, PROJECT_EXT);
        requireExtension(path, PROJECT_EXT);
        requireExists(path);
        var loadedProject = DocumentStore.loadProject(path);
        var source = defaultSceneSource(loadedProject);
        var sceneFile = resolveAgainst(new Path(path).dir, source);
        var loadedScene = DocumentStore.loadScene(sceneFile);
        // Commit only after both reads and all validation have succeeded.
        project = loadedProject;
        scene = loadedScene;
        sceneSource = source;
        projectPath = sys.FileSystem.absolutePath(path);
        scenePath = sceneFile;
        dirty = false;
        savedRevision = 0;
        stateChanged();
    }

    /** Open an existing scene inside the current project or untitled scratch root. */
    public function openScene(path:String):Void {
        path = withExtension(path, SCENE_EXT);
        requireExtension(path, SCENE_EXT);
        requireExists(path);
        var loaded = DocumentStore.loadScene(path);
        var relative = isUntitled()
            ? relativeToRoot(projectRootDir(), path)
            : relativeToProject(projectPath, path);
        scene = loaded;
        sceneSource = relative;
        scenePath = sys.FileSystem.absolutePath(path);
        // Switching scenes is not an edit: registering a previously unknown
        // file is the only reason this can dirty the manifest.
        var manifestChanged = bindSceneAsset(false);
        dirty = manifestChanged;
        savedRevision = 0;
        stateChanged();
    }

    /**
     * Replace the active scene with a new empty document. The previous scene
     * stays registered and on disk: a fresh identity, name, and source path are
     * allocated so a second "New Scene" can never overwrite the first one.
     */
    public function newScene(name:String = "Main Scene", folder:String = "Scenes"):Void {
        var trimmed = StringTools.trim(name);
        if (trimmed.length == 0) throw "Scene name cannot be empty.";
        var allocated = allocateScene(trimmed, folder);
        scene = new SceneDocument(StableId.create("scene"), allocated.name);
        sceneSource = allocated.source;
        scenePath = resolvePath(sceneSource);
        bindSceneAsset();
        dirty = true;
        savedRevision = 0;
        stateChanged();
    }

    /** True until the session has a persisted `.boltproject` manifest. */
    public function isUntitled():Bool return projectPath == "";

    /**
     * Scratch root for untitled sessions. It lives under the working directory
     * so users can try folders/imports without creating a project, while the
     * generated binaries and test output next to it stay out of the browser.
     */
    public static inline var UNTITLED_FOLDER:String = "Content";

    function scanRootDir():String {
        return isUntitled() ? Path.join([projectRootDir(), UNTITLED_FOLDER])
            : projectRootDir();
    }

    function scanPrefix():String {
        return isUntitled() ? UNTITLED_FOLDER : "";
    }

    static function prefixed(prefix:String, relative:String):String {
        if (relative == "") return prefix;
        return prefix == "" ? relative : prefix + "/" + relative;
    }

    /**
     * Scan the project root on disk for asset files. The Asset Browser shows
     * real files (including ones not yet registered in the manifest) so a
     * project can be repaired by opening or deleting a discovered asset.
     * Untitled sessions scan their scratch `Content/` folder instead.
     */
    public function scanAssets():Array<AssetFileInfo> {
        var result:Array<AssetFileInfo> = [];
        collectAssets(scanRootDir(), "", scanPrefix(), result);
        result.sort(function(a, b) {
            var folderOrder = a.folder == b.folder ? 0 : (a.folder < b.folder ? -1 : 1);
            return folderOrder != 0 ? folderOrder
                : (a.name == b.name ? 0 : (a.name < b.name ? -1 : 1));
        });
        var registered = registeredAssetSources();
        for (asset in result) {
            asset.active = asset.source == sceneSource;
            asset.registered = registered.indexOf(asset.source) >= 0;
        }
        return result;
    }

    static function collectAssets(root:String, relative:String, prefix:String,
            output:Array<AssetFileInfo>):Void {
        var directory = relative == "" ? root : Path.join([root, relative]);
        if (!sys.FileSystem.exists(directory)
                || !sys.FileSystem.isDirectory(directory)) return;
        for (entry in sys.FileSystem.readDirectory(directory)) {
            if (entry == "" || StringTools.startsWith(entry, ".")) continue;
            var childRelative = relative == "" ? entry : relative + "/" + entry;
            var fullPath = Path.join([root, childRelative]);
            if (sys.FileSystem.isDirectory(fullPath)) {
                collectAssets(root, childRelative, prefix, output);
                continue;
            }
            var lower = entry.toLowerCase();
            if (!StringTools.endsWith(lower, "." + SCENE_EXT)) continue;
            var info = AssetTypeRegistry.infoFor(entry);
            var name = new Path(entry).file;
            output.push({
                source: prefixed(prefix, childRelative),
                name: name,
                folder: prefixed(prefix, relative),
                kind: info.kind,
                active: false,
                registered: false,
                extension: info.extension,
                kindLabel: info.label,
                loadable: info.loadable
            });
        }
    }

    /** All folders under the project root, including empty ones. */
    public function scanFolders():Array<String> {
        var result:Array<String> = [];
        var prefix = scanPrefix();
        collectFolders(scanRootDir(), "", prefix, result);
        // The scratch root itself must be browsable even while it is empty.
        if (prefix != "" && result.indexOf(prefix) < 0) result.push(prefix);
        result.sort(function(a, b) return a < b ? -1 : (a == b ? 0 : 1));
        return result;
    }

    static function collectFolders(root:String, relative:String, prefix:String,
            output:Array<String>):Void {
        var directory = relative == "" ? root : Path.join([root, relative]);
        if (!sys.FileSystem.exists(directory)
                || !sys.FileSystem.isDirectory(directory)) return;
        for (entry in sys.FileSystem.readDirectory(directory)) {
            if (entry == "" || StringTools.startsWith(entry, ".")) continue;
            var child = relative == "" ? entry : relative + "/" + entry;
            var full = Path.join([root, child]);
            if (!sys.FileSystem.isDirectory(full)) continue;
            var source = prefixed(prefix, child);
            if (output.indexOf(source) < 0) output.push(source);
            collectFolders(root, child, prefix, output);
        }
    }

    /**
     * Scan every user-visible file under the project root. Recognized formats
     * get their engine kind; unknown files stay listed as generic files so the
     * browser mirrors the filesystem without implying the engine can import
     * them. Internal files (manifest, backups, dot files) are skipped.
     * Untitled sessions scan their scratch `Content/` folder instead.
     */
    public function scanAllAssets():Array<AssetFileInfo> {
        var result:Array<AssetFileInfo> = [];
        collectAllAssets(scanRootDir(), "", scanPrefix(), result);
        result.sort(function(a, b) {
            var folderOrder = a.folder == b.folder ? 0 : (a.folder < b.folder ? -1 : 1);
            if (folderOrder != 0) return folderOrder;
            return a.name == b.name ? 0 : (a.name < b.name ? -1 : 1);
        });
        var registered = registeredAssetSources();
        for (asset in result) {
            asset.active = asset.loadable && asset.source == sceneSource;
            asset.registered = registered.indexOf(asset.source) >= 0;
        }
        return result;
    }

    static function collectAllAssets(root:String, relative:String, prefix:String,
            output:Array<AssetFileInfo>):Void {
        var directory = relative == "" ? root : Path.join([root, relative]);
        if (!sys.FileSystem.exists(directory)
                || !sys.FileSystem.isDirectory(directory)) return;
        for (entry in sys.FileSystem.readDirectory(directory)) {
            if (AssetTypeRegistry.isInternal(entry)) continue;
            var childRelative = relative == "" ? entry : relative + "/" + entry;
            var fullPath = Path.join([root, childRelative]);
            if (sys.FileSystem.isDirectory(fullPath)) {
                collectAllAssets(root, childRelative, prefix, output);
                continue;
            }
            var info = AssetTypeRegistry.infoFor(entry);
            output.push({
                source: prefixed(prefix, childRelative),
                name: new Path(entry).file,
                folder: prefixed(prefix, relative),
                kind: info.kind,
                active: false,
                registered: false,
                // The real extension, not the kind's canonical filter extension:
                // a .jpg texture must not be reported as .png in detail/search.
                extension: AssetTypeRegistry.extensionOf(entry),
                kindLabel: info.label,
                loadable: info.loadable
            });
        }
    }

    /** Metadata for one asset, fetched on demand by the inspector. */
    public function assetDetails(source:String):AssetDetails {
        // Engine assets are virtual (`engine://...`) and have no file on disk.
        // Detail/table views still ask for their metadata, so answer with
        // placeholder size/date rather than routing them through path rules.
        if (StringTools.startsWith(source, EngineAssetCatalog.SOURCE_PREFIX)) {
            return engineAssetDetails(source);
        }
        var normalized = ProjectPath.normalizeRelative(source);
        var info = AssetTypeRegistry.infoFor(new Path(normalized).file);
        var rawExtension = new Path(normalized).ext;
        var actualExtension = rawExtension == null ? "" : rawExtension.toLowerCase();
        var absolute = resolveAgainst(projectRootDir(), normalized);
        var size = -1;
        var modified = -1.0;
        try {
            if (sys.FileSystem.exists(absolute)) {
                var stat = sys.FileSystem.stat(absolute);
                size = stat.size;
                modified = stat.mtime.getTime() / 1000;
            }
        } catch (_:Dynamic) {}
        return {
            source: normalized,
            name: new Path(normalized).file,
            folder: normalizeFolder(new Path(normalized).dir),
            kind: info.kind,
            kindLabel: info.label,
            extension: actualExtension,
            loadable: info.loadable,
            registered: isRegisteredAsset(normalized),
            active: info.loadable && normalized == sceneSource,
            absolutePath: absolute,
            size: size,
            modified: modified
        };
    }

    function engineAssetDetails(source:String):AssetDetails {
        var name = source;
        var folder = EngineAssetCatalog.FOLDER;
        var kindLabel = AssetTypeRegistry.ENGINE_INFO_LABEL;
        for (entry in EngineAssetCatalog.all()) {
            if (entry.source == source) {
                name = entry.name;
                folder = entry.folder;
                kindLabel = entry.kindLabel;
                break;
            }
        }
        return {
            source: source,
            name: name,
            folder: folder,
            kind: AssetTypeRegistry.KIND_ENGINE,
            kindLabel: kindLabel,
            extension: "",
            loadable: true,
            registered: false,
            active: false,
            absolutePath: "",
            size: -1,
            modified: -1.0
        };
    }

    /** True when a source uses the one format the engine can load. */
    public function isScenePath(source:String):Bool {
        return StringTools.endsWith(ProjectPath.normalizeRelative(source).toLowerCase(),
            "." + SCENE_EXT);
    }

    /** Absolute path of a project-relative source, for reveal/copy-path. */
    public function absoluteAssetPath(source:String):String {
        return resolveAgainst(projectRootDir(), ProjectPath.normalizeRelative(source));
    }

    /**
     * Absolute path of the asset root itself. An empty relative source (the
     * "All / Content" folder) has no ProjectPath representation, so callers
     * that reveal or copy a path must use this instead of normalizeRelative("").
     * Before a project is created the working directory is the asset root.
     */
    public function assetRootPath():String {
        return sys.FileSystem.absolutePath(projectRootDir());
    }

    /**
     * Absolute directory the Asset Browser actually scans. Kept here so the
     * external-change watcher follows project/untitled switches automatically
     * instead of duplicating the scratch `Content/` rule.
     */
    public function assetWatchRoot():String {
        return sys.FileSystem.absolutePath(scanRootDir());
    }

    // ------------------------------------------------------------------
    // Generic asset operations
    //
    // The scene-specific methods above keep their manifest bookkeeping. These
    // helpers extend the same commands to generic files and folders so the
    // browser never offers an action it cannot actually perform.
    // ------------------------------------------------------------------

    public function renameAnyAsset(source:String, newName:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        if (isRegisteredScene(normalized)) {
            renameScene(normalized, newName);
            return sceneSource;
        }
        var path = new Path(normalized);
        var base = sanitizeAssetName(newName, path.ext == null ? "" : path.ext);
        var target = path.dir == "" ? base : path.dir + "/" + base;
        target = ProjectPath.normalizeRelative(target);
        var from = resolveAgainst(projectRootDir(), normalized);
        var to = resolveAgainst(projectRootDir(), target);
        requireExists(from);
        if (to != from && sys.FileSystem.exists(to)) {
            throw 'A file already exists at ${target}';
        }
        sys.FileSystem.rename(from, to);
        return target;
    }

    public function deleteAnyAsset(source:String):Void {
        var normalized = ProjectPath.normalizeRelative(source);
        if (isRegisteredScene(normalized)) {
            deleteScene(normalized);
            return;
        }
        var path = resolveAgainst(projectRootDir(), normalized);
        requireExists(path);
        sys.FileSystem.deleteFile(path);
        removeBackup(path);
    }

    public function moveAnyAsset(source:String, targetFolder:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        if (isRegisteredScene(normalized)) {
            moveScene(normalized, targetFolder);
            return normalized;
        }
        var folder = normalizeFolder(targetFolder);
        var fileName = new Path(normalized).file;
        var rawExtension = new Path(normalized).ext;
        var extension = rawExtension == null ? "" : rawExtension;
        var leaf = extension == "" ? fileName : fileName + "." + extension;
        var destination = uniqueAssetPath(folder, leaf, "");
        var from = resolveAgainst(projectRootDir(), normalized);
        var to = resolveAgainst(projectRootDir(), destination);
        requireExists(from);
        sys.FileSystem.createDirectory(new Path(to).dir);
        sys.FileSystem.rename(from, to);
        return destination;
    }

    public function copyAnyAsset(source:String, targetFolder:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        if (isRegisteredScene(normalized)) return copyScene(normalized, targetFolder);
        var folder = normalizeFolder(targetFolder);
        var fileName = new Path(normalized).file;
        var rawExtension = new Path(normalized).ext;
        var extension = rawExtension == null ? "" : rawExtension;
        var leaf = extension == "" ? fileName : fileName + "." + extension;
        var destination = uniqueAssetPath(folder, leaf, "");
        var from = resolveAgainst(projectRootDir(), normalized);
        var to = resolveAgainst(projectRootDir(), destination);
        requireExists(from);
        sys.FileSystem.createDirectory(new Path(to).dir);
        sys.io.File.copy(from, to);
        return destination;
    }

    /** Copy an asset beside itself with a unique name. */
    public function duplicateAnyAsset(source:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        return copyAnyAsset(normalized, normalizeFolder(new Path(normalized).dir));
    }

    /**
     * Copy external image files into the project and register each one as a
     * `texture` asset. This is the single write path shared by the native
     * Import dialog and Explorer drops; neither caller touches the manifest.
     *
     * Every input is validated before anything is copied, so a bad extension,
     * missing file, or unsafe folder leaves the project untouched. Destination
     * names are sanitized and made unique, external paths are never persisted,
     * and existing files are never overwritten.
     *
     * @return project-relative sources of the files that were imported, in
     *         input order.
     */
    public function importAssets(paths:Array<String>, targetFolder:String):Array<String> {
        if (paths == null || paths.length == 0) return [];
        var requested = targetFolder == null ? "" : StringTools.trim(targetFolder);
        var folder = requested.length == 0 ? TEXTURE_FOLDER : normalizeFolder(requested);

        var pending:Array<PendingImport> = [];
        for (path in paths) {
            if (path == null || StringTools.trim(path).length == 0) {
                throw "An import path is required.";
            }
            var absolute = sys.FileSystem.absolutePath(path);
            if (!sys.FileSystem.exists(absolute) || sys.FileSystem.isDirectory(absolute)) {
                throw 'Import file not found: ${absolute}';
            }
            var extension = AssetTypeRegistry.extensionOf(absolute);
            if (!AssetTypeRegistry.isTextureExtension(extension)) {
                throw 'Unsupported import format: ${extension == "" ? "(none)" : extension}';
            }
            var leaf = safeFileName(new Path(absolute).file + "." + extension);
            pending.push({
                from: absolute,
                destination: uniqueAssetPath(folder, leaf, ""),
                extension: extension
            });
        }

        var imported:Array<String> = [];
        for (item in pending) {
            var to = resolveAgainst(projectRootDir(), item.destination);
            ensureDirectory(new Path(to).dir);
            sys.io.File.copy(item.from, to);
            project.assets.push(new AssetRecord(StableId.create("asset"), "texture",
                item.destination, { format: item.extension }));
            imported.push(item.destination);
        }
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
        return imported;
    }

    /**
     * Delete a folder. `recursive` must be true for non-empty folders; the UI
     * asks for confirmation first. Registered scenes inside the folder are
     * unregistered, and the last remaining scene can never be removed this way.
     */
    /** False when removing this folder would leave the project with no scene. */
    public function canDeleteFolder(folder:String):Bool {
        var normalized = normalizeFolder(folder);
        if (normalized == "") return false;
        var prefix = normalized + "/";
        // An untitled session has no manifest scene count to protect. Still
        // refuse the folder holding the in-memory active scene.
        if (isUntitled()) return !StringTools.startsWith(sceneSource, prefix);
        var scenesInside = 0;
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            if (StringTools.startsWith(ProjectPath.normalizeRelative(asset.source), prefix)) {
                scenesInside++;
            }
        }
        return sceneSources().length - scenesInside >= 1;
    }

    public function deleteFolder(folder:String, recursive:Bool):Void {
        var normalized = normalizeFolder(folder);
        if (normalized == "") throw "The content root cannot be deleted.";
        var root = projectRootDir();
        var absolute = resolveAgainst(root, normalized);
        requireExists(absolute);
        if (!sys.FileSystem.isDirectory(absolute)) throw 'Not a folder: ${normalized}';
        var prefix = normalized + "/";
        var scenesInside = 0;
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            if (StringTools.startsWith(ProjectPath.normalizeRelative(asset.source), prefix)) {
                scenesInside++;
            }
        }
        if (!isUntitled() && sceneSources().length - scenesInside < 1) {
            throw "A project must keep at least one scene.";
        }
        var entries = collectRelativeEntries(absolute, normalized);
        if (entries.length > 0 && !recursive) {
            throw 'Folder is not empty: ${normalized}';
        }
        for (relative in entries) {
            var file = resolveAgainst(root, relative);
            if (sys.FileSystem.isDirectory(file)) continue;
            sys.FileSystem.deleteFile(file);
            removeBackup(file);
        }
        // Children first, then the folder itself.
        entries.sort(function(a, b) return b.length - a.length);
        for (relative in entries) {
            var directory = resolveAgainst(root, relative);
            if (sys.FileSystem.exists(directory) && sys.FileSystem.isDirectory(directory)) {
                sys.FileSystem.deleteDirectory(directory);
            }
        }
        var removed:Array<AssetRecord> = [];
        for (asset in project.assets) {
            if (asset.type == "scene"
                    && StringTools.startsWith(ProjectPath.normalizeRelative(asset.source), prefix)) {
                removed.push(asset);
            }
        }
        for (asset in removed) project.assets.remove(asset);
        if (StringTools.startsWith(sceneSource, prefix)) {
            var next = sceneSources()[0];
            scene = DocumentStore.loadScene(resolveAgainst(root, next));
            sceneSource = next;
            scenePath = resolveAgainst(root, next);
        }
        sys.FileSystem.deleteDirectory(absolute);
        // The active scene may have lived in the removed folder. Rebind the
        // default scene id before validation so the manifest stays consistent.
        bindSceneAsset();
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
    }

    /** Move a folder (and every path inside it) under a new parent. */
    public function moveFolder(source:String, targetParent:String):String {
        var normalized = normalizeFolder(source);
        if (normalized == "") throw "The content root cannot be moved.";
        var parent = normalizeFolder(targetParent);
        if (parent == normalized || StringTools.startsWith(parent, normalized + "/")) {
            throw "A folder cannot be moved into itself.";
        }
        var parts = normalized.split("/");
        var leaf = parts[parts.length - 1];
        var destination = parent == "" ? leaf : parent + "/" + leaf;
        var root = projectRootDir();
        var from = resolveAgainst(root, normalized);
        var to = resolveAgainst(root, destination);
        requireExists(from);
        if (to == from) return normalized;
        if (sys.FileSystem.exists(to)) throw 'A folder already exists at ${destination}';
        ensureDirectory(new Path(to).dir);
        sys.FileSystem.rename(from, to);
        repointAssetPaths(normalized, destination);
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
        return destination;
    }

    static function collectRelativeEntries(absoluteDirectory:String,
            relative:String):Array<String> {
        var result:Array<String> = [];
        for (entry in sys.FileSystem.readDirectory(absoluteDirectory)) {
            if (AssetTypeRegistry.isInternal(entry)) continue;
            var child = relative == "" ? entry : relative + "/" + entry;
            var full = Path.join([absoluteDirectory, entry]);
            if (sys.FileSystem.isDirectory(full)) {
                result.push(child);
                for (nested in collectRelativeEntries(full, child)) result.push(nested);
            } else {
                result.push(child);
            }
        }
        return result;
    }

    function repointAssetPaths(oldPrefix:String, newPrefix:String):Void {
        var prefix = oldPrefix + "/";
        for (asset in project.assets) {
            var source = ProjectPath.normalizeRelative(asset.source);
            if (StringTools.startsWith(source, prefix)) {
                asset.source = newPrefix + "/" + source.substr(prefix.length);
            }
        }
        if (StringTools.startsWith(sceneSource, prefix)) {
            sceneSource = newPrefix + "/" + sceneSource.substr(prefix.length);
            scenePath = resolvePath(sceneSource);
        }
    }

    function uniqueAssetPath(folder:String, leaf:String, exclude:String):String {
        var path = new Path(leaf);
        var base = path.file;
        var extension = path.ext == null ? "" : path.ext;
        var candidate = folder == "" ? leaf : folder + "/" + leaf;
        var suffix = 2;
        while (candidate != exclude
                && sys.FileSystem.exists(resolveAgainst(projectRootDir(), candidate))) {
            var name = base + " " + suffix + (extension == "" ? "" : "." + extension);
            candidate = folder == "" ? name : folder + "/" + name;
            suffix++;
        }
        return candidate;
    }

    static function sanitizeAssetName(name:String, extension:String):String {
        var base = safeFileName(name);
        if (extension.length > 0
                && !StringTools.endsWith(base.toLowerCase(), "." + extension.toLowerCase())) {
            base += "." + extension;
        }
        return base;
    }

    /** Every manifest asset source, including imported textures and future kinds. */
    public function registeredAssetSources():Array<String> {
        var result:Array<String> = [];
        for (asset in project.assets) {
            var source = ProjectPath.normalizeRelative(asset.source);
            if (result.indexOf(source) < 0) result.push(source);
        }
        return result;
    }

    function isRegisteredAsset(source:String):Bool {
        var normalized = ProjectPath.normalizeRelative(source);
        for (asset in project.assets) {
            if (ProjectPath.normalizeRelative(asset.source) == normalized) return true;
        }
        return false;
    }

    function isRegisteredScene(source:String):Bool {
        var normalized = ProjectPath.normalizeRelative(source);
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            if (ProjectPath.normalizeRelative(asset.source) == normalized) return true;
        }
        return false;
    }

    static function normalizeFolder(folder:String):String {
        var trimmed = StringTools.trim(folder).split("\\").join("/");
        if (trimmed == "" || trimmed == "/") return "";
        while (trimmed.length > 1 && StringTools.endsWith(trimmed, "/")) {
            trimmed = trimmed.substr(0, trimmed.length - 1);
        }
        return ProjectPath.normalizeRelative(trimmed);
    }

    /**
     * Create a folder under `parent`. An empty parent means the Content root;
     * callers that want a subfolder pass an explicit folder path.
     */
    public function createFolder(parent:String, name:String):String {
        var root = normalizeFolder(parent);
        // Untitled sessions work inside the scratch Content folder, so an
        // empty parent means that folder rather than the process working dir.
        if (root == "" && isUntitled()) root = UNTITLED_FOLDER;
        var base = safeFileName(name);
        var relative = root == "" ? base : root + "/" + base;
        var suffix = 2;
        while (sys.FileSystem.exists(resolveAgainst(projectRootDir(), relative))) {
            relative = root == "" ? base + " " + suffix : root + "/" + base + " " + suffix;
            suffix++;
        }
        ensureDirectory(resolveAgainst(projectRootDir(), relative));
        return relative;
    }

    /** Rename a folder and repoint every asset path inside it. */
    public function renameFolder(folder:String, newName:String):String {
        var normalized = assetFolder(folder);
        var parts = normalized.split("/");
        var parent = parts.length > 1 ? parts.slice(0, parts.length - 1).join("/") : "";
        var base = safeFileName(newName);
        var target = parent == "" ? base : parent + "/" + base;
        var suffix = 2;
        var root = projectRootDir();
        while (target != normalized
                && sys.FileSystem.exists(resolveAgainst(root, target))) {
            var candidate = base + " " + suffix;
            target = parent == "" ? candidate : parent + "/" + candidate;
            suffix++;
        }
        if (target == normalized) return normalized;
        var from = resolveAgainst(root, normalized);
        var to = resolveAgainst(root, target);
        requireExists(from);
        sys.FileSystem.rename(from, to);
        var prefix = normalized + "/";
        for (asset in project.assets) {
            var source = ProjectPath.normalizeRelative(asset.source);
            if (StringTools.startsWith(source, prefix)) {
                asset.source = target + "/" + source.substr(prefix.length);
            }
        }
        if (StringTools.startsWith(sceneSource, prefix)) {
            sceneSource = target + "/" + sceneSource.substr(prefix.length);
            scenePath = resolvePath(sceneSource);
        }
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
        return target;
    }

    /** Move a registered scene into another folder. */
    public function moveScene(source:String, targetFolder:String):Void {
        var normalized = ProjectPath.normalizeRelative(source);
        var asset = requireSceneAsset(normalized);
        var folder = assetFolder(targetFolder);
        var fileName = new Path(normalized).file + "." + SCENE_EXT;
        var destination = uniqueAssetPath(folder, fileName, normalized);
        if (destination == normalized) return;
        var from = resolveAgainst(projectRootDir(), normalized);
        var to = resolveAgainst(projectRootDir(), destination);
        requireExists(from);
        ensureDirectory(new Path(to).dir);
        sys.FileSystem.rename(from, to);
        asset.source = destination;
        if (sceneSource == normalized) {
            sceneSource = destination;
            scenePath = to;
        }
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
    }

    /** Copy a scene into another folder with fresh identities. */
    public function copyScene(source:String, targetFolder:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        requireSceneAsset(normalized);
        var folder = assetFolder(targetFolder);
        var base = new Path(normalized).file;
        var destination = folder + "/" + base + "." + SCENE_EXT;
        var suffix = 2;
        while (sys.FileSystem.exists(resolveAgainst(projectRootDir(), destination))) {
            destination = folder + "/" + base + " " + suffix + "." + SCENE_EXT;
            suffix++;
        }
        var document = SceneSerializer.duplicate(
            DocumentStore.loadScene(resolveAgainst(projectRootDir(), normalized)),
            sceneDisplayName(destination));
        var to = resolveAgainst(projectRootDir(), destination);
        ensureDirectory(new Path(to).dir);
        DocumentStore.saveScene(to, document);
        project.assets.push(new AssetRecord(document.id, "scene", destination));
        saveManifestIfOpen();
        dirty = true;
        stateChanged();
        return destination;
    }

    /** Registered scene sources in stable asset order. */
    public function sceneSources():Array<String> {
        var result:Array<String> = [];
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            var source = ProjectPath.normalizeRelative(asset.source);
            if (result.indexOf(source) < 0) result.push(source);
        }
        return result;
    }

    /** Short display name for a folder path. */
    public static function folderDisplayName(folder:String):String {
        if (folder == "" || folder == "/") return "Content";
        var parts = folder.split("/");
        return parts[parts.length - 1];
    }

    /** Human-readable name derived from a registered scene source. */
    public static function sceneDisplayName(source:String):String {
        var file = new Path(ProjectPath.normalizeRelative(source)).file;
        return file == null || file.length == 0 ? "Scene" : file;
    }

    /** Switch to an already registered scene of the current project. */
    public function openSceneSource(source:String):Void {
        openScene(resolveAgainst(projectRootDir(), source));
    }

    /**
     * Rename a registered scene. Its display name, file name, asset source, and
     * stored document name all change together; a colliding name is made
     * unique. The active scene keeps its identity and edited graph.
     */
    public function renameScene(source:String, newName:String):Void {
        var normalized = ProjectPath.normalizeRelative(source);
        var asset = requireSceneAsset(normalized);
        var trimmed = StringTools.trim(newName);
        if (trimmed.length == 0) throw "Scene name cannot be empty.";
        var folder = new Path(normalized).dir;
        var allocated = allocateRename(normalized, trimmed, folder);
        var oldPath = resolveAgainst(projectRootDir(), normalized);
        var newPath = resolveAgainst(projectRootDir(), allocated.source);

        if (oldPath != newPath) requireExists(oldPath);
        var document = DocumentStore.loadScene(oldPath);
        document.name = allocated.name;
        // Write the new target before repointing the manifest, so every
        // intermediate state still has a readable file at the registered path.
        ensureDirectory(new Path(newPath).dir);
        DocumentStore.saveScene(newPath, document);
        asset.source = allocated.source;
        saveManifestIfOpen();
        if (oldPath != newPath) {
            sys.FileSystem.deleteFile(oldPath);
            removeBackup(oldPath);
        }
        if (sceneSource == normalized) {
            sceneSource = allocated.source;
            scenePath = newPath;
            scene.name = allocated.name;
        }
        dirty = true;
        stateChanged();
    }

    /** Delete a registered scene. The last remaining scene cannot be removed. */
    public function deleteScene(source:String):Void {
        var normalized = ProjectPath.normalizeRelative(source);
        var asset = requireSceneAsset(normalized);
        if (sceneSources().length <= 1) {
            throw "A project must keep at least one scene.";
        }
        var wasActive = sceneSource == normalized;
        var path = resolveAgainst(projectRootDir(), normalized);
        project.assets.remove(asset);
        // Repoint the manifest before removing the document so no saved state
        // ever references a file that is already gone.
        if (wasActive) {
            var nextSource = sceneSources()[0];
            var nextPath = resolveAgainst(projectRootDir(), nextSource);
            scene = DocumentStore.loadScene(nextPath);
            sceneSource = nextSource;
            scenePath = nextPath;
        }
        bindSceneAsset();
        saveManifestIfOpen();
        if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
        removeBackup(path);
        dirty = true;
        stateChanged();
    }

    /** Capture the current editor graph into the active scene document. */
    public function captureScene(session:EditorSession):Void {
        if (session == null) throw "Editor session is required.";
        scene = SceneSerializer.fromSession(session, scene.id, scene.name);
        stateChanged();
    }

    /** Build a fresh editor session from the active scene document. */
    public function createSession():EditorSession {
        return SceneSerializer.toSession(scene);
    }

    /** Write the active scene and project manifest atomically. */
    public function save(session:EditorSession):Void {
        if (projectPath == "") throw "No project path; use Save Project As.";
        captureScene(session);
        saveDocuments();
        savedRevision = session.history.revision;
    }

    /** Change the project manifest path, then save everything there. */
    public function saveAs(path:String, session:EditorSession):Void {
        path = withExtension(path, PROJECT_EXT);
        requireExtension(path, PROJECT_EXT);
        projectPath = sys.FileSystem.absolutePath(path);
        project.name = new Path(path).file;
        save(session);
    }

    /**
     * Persist the current scene document and manifest without capturing an
     * editor graph. Used by the Asset Browser right after a scene is created.
     */
    public function persistSceneDocument():Void {
        if (isUntitled()) {
            // No manifest to write yet, but the scene document must exist so
            // the browser can find it and a later Save As has a file to promote.
            ensureDirectory(new Path(scenePath).dir);
            DocumentStore.saveScene(scenePath, scene);
            return;
        }
        saveDocuments();
    }

    /** Write only the active scene document. */
    public function saveScene(session:EditorSession):Void {
        if (scenePath == "") throw "No scene path; use Save Project As.";
        captureScene(session);
        DocumentStore.saveScene(scenePath, scene);
        markSaved(session);
    }

    /** Resolve a project-relative asset path against the current manifest. */
    public function resolvePath(source:String):String {
        return resolveAgainst(projectPath == "" ? Sys.getCwd() : new Path(projectPath).dir,
            source);
    }

    public function markDirty():Void {
        if (dirty) return;
        dirty = true;
        stateChanged();
    }

    public function clearDirty():Void {
        if (!dirty) return;
        dirty = false;
        stateChanged();
    }

    /** Selection and view notifications do not advance history revision. */
    public function syncDirty(session:EditorSession):Void {
        if (session.history.revision != savedRevision) markDirty();
    }

    /** Record the current history state as the last saved point. */
    public function markSaved(session:EditorSession):Void {
        savedRevision = session.history.revision;
        clearDirty();
    }

    /** Title-strip text: project — scene, with a dirty marker. */
    public function title():String {
        return project.name + " — " + scene.name + (dirty ? " *" : "");
    }

    function saveDocuments():Void {
        bindSceneAsset();
        scenePath = resolvePath(sceneSource);
        // Scene first: a project manifest that points at a missing scene is
        // never left behind if scene writing fails.
        DocumentStore.saveScene(scenePath, scene);
        DocumentStore.saveProject(projectPath, project);
        dirty = false;
        stateChanged();
    }

    /**
     * Ensure the active scene is registered. `setDefault` is false when merely
     * switching scenes: the persisted default/startup scene changes on save,
     * not on every open, so browsing scenes never dirties the project.
     */
    function bindSceneAsset(setDefault:Bool = true):Bool {
        var normalized = ProjectPath.normalizeRelative(sceneSource);
        sceneSource = normalized;
        var changed = false;
        var match:Null<AssetRecord> = null;
        for (asset in project.assets) {
            if (asset.type == "scene"
                    && StringTools.trim(asset.source).split("\\").join("/") == normalized) {
                match = asset;
                break;
            }
        }
        if (match == null) {
            match = new AssetRecord(scene.id, "scene", normalized);
            project.assets.push(match);
            changed = true;
        } else if (match.id != scene.id) {
            match.id = scene.id;
            changed = true;
        }
        if (setDefault && project.defaultSceneId != scene.id) {
            project.defaultSceneId = scene.id;
            changed = true;
        }
        return changed;
    }

    /**
     * Choose a display name and source path that no registered asset or file on
     * disk already owns. Collisions append " 2", " 3", ... instead of reusing
     * the previous scene's document.
     */
    function allocateScene(requested:String, folder:String):{ name:String, source:String } {
        var baseName = StringTools.trim(requested);
        if (baseName.length == 0) baseName = "Scene";
        var baseFile = safeFileName(baseName);
        var directory = assetFolder(folder);
        var name = baseName;
        var source = directory + "/" + baseFile + "." + SCENE_EXT;
        var suffix = 2;
        while (isSceneSourceTaken(source)) {
            name = baseFile + " " + suffix;
            source = directory + "/" + safeFileName(name) + "." + SCENE_EXT;
            suffix++;
        }
        return { name: name, source: source };
    }

    function allocateRename(exclude:String, requested:String,
            folder:String):{ name:String, source:String } {
        var baseName = StringTools.trim(requested);
        if (baseName.length == 0) baseName = "Scene";
        var baseFile = safeFileName(baseName);
        var directory = assetFolder(folder);
        var name = baseName;
        var source = directory + "/" + baseFile + "." + SCENE_EXT;
        var suffix = 2;
        while (source != exclude && isSceneSourceTaken(source)) {
            name = baseFile + " " + suffix;
            source = directory + "/" + safeFileName(name) + "." + SCENE_EXT;
            suffix++;
        }
        return { name: name, source: source };
    }

    function assetFolder(folder:String):String {
        var trimmed = StringTools.trim(folder).split("\\").join("/");
        var normalized = trimmed.length == 0 ? "Scenes" : ProjectPath.normalizeRelative(trimmed);
        // Untitled scenes live inside the scratch Content folder so they show
        // up in the browser alongside imported textures.
        return isUntitled() ? UNTITLED_FOLDER + "/" + normalized : normalized;
    }

    function requireSceneAsset(source:String):AssetRecord {
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            if (StringTools.trim(asset.source).split("\\").join("/") == source) {
                return asset;
            }
        }
        throw 'Scene is not registered in this project: ${source}';
    }

    static function removeBackup(path:String):Void {
        var backup = path + ".bak";
        if (sys.FileSystem.exists(backup)) sys.FileSystem.deleteFile(backup);
    }

    function isSceneSourceTaken(source:String):Bool {
        var normalized = ProjectPath.normalizeRelative(source);
        for (asset in project.assets) {
            if (asset.type != "scene") continue;
            if (StringTools.trim(asset.source).split("\\").join("/") == normalized) {
                return true;
            }
        }
        return sys.FileSystem.exists(resolveAgainst(projectRootDir(), normalized));
    }

    function projectRootDir():String {
        if (!isUntitled()) return new Path(projectPath).dir;
        // Probe hook: native tests point untitled sessions at an isolated
        // workspace instead of the shared bin working directory. Production
        // behaviour is the working directory's scratch Content folder.
        var probeDir = Sys.getEnv("BOLTSPARK_PROBE_UNTITLED_DIR");
        if (probeDir != null && StringTools.trim(probeDir).length > 0) return probeDir;
        return Sys.getCwd();
    }

    /**
     * Persist manifest edits only when a real project exists. Untitled sessions
     * keep asset records in memory so folders, imports, and scene experiments
     * work without forcing a Save Project As first.
     */
    function saveManifestIfOpen():Void {
        if (!isUntitled()) DocumentStore.saveProject(projectPath, project);
    }

    /** `createDirectory` is not recursive on every target; create parents too. */
    static function ensureDirectory(path:String):Void {
        if (path == null || path == "" || sys.FileSystem.exists(path)) return;
        var parent = new Path(path).dir;
        if (parent != null && parent != path && parent.length > 0) ensureDirectory(parent);
        sys.FileSystem.createDirectory(path);
    }

    static function defaultSceneSource(project:ProjectDocument):String {
        if (project.defaultSceneId == null) {
            throw 'Project ${project.id} has no default scene.';
        }
        for (asset in project.assets) {
            if (asset.id == project.defaultSceneId) {
                if (asset.type != "scene") {
                    throw 'Default scene asset is not a scene: ${asset.id}';
                }
                return asset.source;
            }
        }
        throw 'Default scene asset not found: ${project.defaultSceneId}';
    }

    static function resolveAgainst(root:String, source:String):String {
        var normalized = ProjectPath.normalizeRelative(source);
        var absoluteRoot = sys.FileSystem.absolutePath(root);
        return Path.join([absoluteRoot, normalized]);
    }

    /** Validate that a chosen scene lives inside the current project root. */
    static function relativeToProject(projectPath:String, scenePath:String):String {
        return relativeToRoot(new Path(projectPath).dir, scenePath);
    }

    static function relativeToRoot(rootPath:String, scenePath:String):String {
        var root = normalizeSlashes(sys.FileSystem.absolutePath(rootPath));
        var absolute = normalizeSlashes(sys.FileSystem.absolutePath(scenePath));
        var lowerRoot = root.toLowerCase();
        var lowerFile = absolute.toLowerCase();
        if (lowerFile == lowerRoot || !StringTools.startsWith(lowerFile, lowerRoot + "/")) {
            throw 'Scene is outside the project root: ${scenePath}';
        }
        var relative = absolute.substr(root.length + 1);
        ProjectPath.normalizeRelative(relative);
        return relative;
    }

    /**
     * The Windows picker filter is authoritative: when the user types a bare
     * name, HashLink may return it without the filter extension. Append the
     * one implied by the dialog instead of failing the whole save/open.
     */
    static function withExtension(path:String, extension:String):String {
        if (path == null || StringTools.trim(path).length == 0) {
            throw "A file path is required.";
        }
        if (StringTools.endsWith(path.toLowerCase(), "." + extension)) return path;
        return path + "." + extension;
    }

    static function requireExtension(path:String, extension:String):Void {
        if (!StringTools.endsWith(path.toLowerCase(), "." + extension)) {
            throw 'Expected a .${extension} path: ${path}';
        }
    }

    static function requireExists(path:String):Void {
        if (!sys.FileSystem.exists(path)) throw 'File not found: ${path}';
    }

    static function normalizeSlashes(value:String):String {
        var trimmed = value.split("\\").join("/");
        while (trimmed.length > 1 && trimmed.charAt(trimmed.length - 1) == "/") {
            trimmed = trimmed.substr(0, trimmed.length - 1);
        }
        return trimmed;
    }

    static function safeFileName(name:String):String {
        var cleaned = ~/[<>:"\/\\|?*\x00-\x1F]/g.replace(StringTools.trim(name), "_");
        while (cleaned.indexOf("__") >= 0) cleaned = cleaned.split("__").join("_");
        while (cleaned.length > 0
                && (cleaned.charAt(0) == "_" || cleaned.charAt(0) == ".")) {
            cleaned = cleaned.substr(1);
        }
        while (cleaned.length > 0
                && (cleaned.charAt(cleaned.length - 1) == "_"
                    || cleaned.charAt(cleaned.length - 1) == ".")) {
            cleaned = cleaned.substr(0, cleaned.length - 1);
        }
        return cleaned.length == 0 ? "Untitled" : cleaned;
    }

    function stateChanged():Void {
        if (onStateChanged != null) onStateChanged();
    }
}
