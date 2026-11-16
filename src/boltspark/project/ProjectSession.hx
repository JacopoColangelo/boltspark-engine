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
        project.name = trimmed;
        project.assets.resize(0);
        savedRevision = 0;
        var allocated = allocateScene("Main Scene", "Scenes");
        scene = new SceneDocument(StableId.create("scene"), allocated.name);
        sceneSource = allocated.source;
        var _ = bindSceneAsset();
        projectPath = absolute;
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

    /** Open an existing scene inside the current project. */
    public function openScene(path:String):Void {
        if (projectPath == "") throw "Open or create a project before opening a scene.";
        path = withExtension(path, SCENE_EXT);
        requireExtension(path, SCENE_EXT);
        requireExists(path);
        var loaded = DocumentStore.loadScene(path);
        var relative = relativeToProject(projectPath, path);
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
        if (projectPath == "") throw "Open or create a project before creating a scene.";
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

    /**
     * Scan the project root on disk for asset files. The Asset Browser shows
     * real files (including ones not yet registered in the manifest) so a
     * project can be repaired by opening or deleting a discovered asset.
     */
    public function scanAssets():Array<AssetFileInfo> {
        var result:Array<AssetFileInfo> = [];
        if (projectPath == "") return result;
        collectAssets(projectRootDir(), "", result);
        result.sort(function(a, b) {
            var folderOrder = a.folder == b.folder ? 0 : (a.folder < b.folder ? -1 : 1);
            return folderOrder != 0 ? folderOrder
                : (a.name == b.name ? 0 : (a.name < b.name ? -1 : 1));
        });
        var registered = sceneSources();
        for (asset in result) {
            asset.active = asset.source == sceneSource;
            asset.registered = registered.indexOf(asset.source) >= 0;
        }
        return result;
    }

    static function collectAssets(root:String, relative:String,
            output:Array<AssetFileInfo>):Void {
        var directory = relative == "" ? root : Path.join([root, relative]);
        if (!sys.FileSystem.exists(directory)
                || !sys.FileSystem.isDirectory(directory)) return;
        for (entry in sys.FileSystem.readDirectory(directory)) {
            if (entry == "" || StringTools.startsWith(entry, ".")) continue;
            var childRelative = relative == "" ? entry : relative + "/" + entry;
            var fullPath = Path.join([root, childRelative]);
            if (sys.FileSystem.isDirectory(fullPath)) {
                collectAssets(root, childRelative, output);
                continue;
            }
            var lower = entry.toLowerCase();
            if (!StringTools.endsWith(lower, "." + SCENE_EXT)) continue;
            var kind = "scene";
            var name = new Path(entry).file;
            output.push({
                source: childRelative,
                name: name,
                folder: relative,
                kind: kind,
                active: false,
                registered: false
            });
        }
    }

    /** All folders under the project root, including empty ones. */
    public function scanFolders():Array<String> {
        var result:Array<String> = [];
        if (projectPath == "") return result;
        collectFolders(projectRootDir(), "", result);
        result.sort(function(a, b) return a < b ? -1 : (a == b ? 0 : 1));
        return result;
    }

    static function collectFolders(root:String, relative:String,
            output:Array<String>):Void {
        var directory = relative == "" ? root : Path.join([root, relative]);
        if (!sys.FileSystem.exists(directory)
                || !sys.FileSystem.isDirectory(directory)) return;
        for (entry in sys.FileSystem.readDirectory(directory)) {
            if (entry == "" || StringTools.startsWith(entry, ".")) continue;
            var child = relative == "" ? entry : relative + "/" + entry;
            var full = Path.join([root, child]);
            if (!sys.FileSystem.isDirectory(full)) continue;
            if (output.indexOf(child) < 0) output.push(child);
            collectFolders(root, child, output);
        }
    }

    /** Create a folder under the project root; returns its relative path. */
    public function createFolder(parent:String, name:String):String {
        if (projectPath == "") throw "Open or create a project before creating folders.";
        var root = assetFolder(parent);
        var base = safeFileName(name);
        var relative = root + "/" + base;
        var suffix = 2;
        while (sys.FileSystem.exists(resolveAgainst(projectRootDir(), relative))) {
            relative = root + "/" + base + " " + suffix;
            suffix++;
        }
        sys.FileSystem.createDirectory(resolveAgainst(projectRootDir(), relative));
        return relative;
    }

    /** Rename a folder and repoint every asset path inside it. */
    public function renameFolder(folder:String, newName:String):String {
        if (projectPath == "") throw "Open or create a project before renaming folders.";
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
        DocumentStore.saveProject(projectPath, project);
        dirty = true;
        stateChanged();
        return target;
    }

    /** Move a registered scene into another folder. */
    public function moveScene(source:String, targetFolder:String):Void {
        if (projectPath == "") throw "Open or create a project before moving assets.";
        var normalized = ProjectPath.normalizeRelative(source);
        var asset = requireSceneAsset(normalized);
        var folder = assetFolder(targetFolder);
        var destination = folder + "/" + new Path(normalized).file + "." + SCENE_EXT;
        if (destination == normalized) return;
        var from = resolveAgainst(projectRootDir(), normalized);
        var to = resolveAgainst(projectRootDir(), destination);
        requireExists(from);
        if (sys.FileSystem.exists(to)) {
            throw 'An asset already exists at ${destination}';
        }
        sys.FileSystem.createDirectory(new Path(to).dir);
        sys.FileSystem.rename(from, to);
        asset.source = destination;
        if (sceneSource == normalized) {
            sceneSource = destination;
            scenePath = to;
        }
        DocumentStore.saveProject(projectPath, project);
        dirty = true;
        stateChanged();
    }

    /** Copy a scene into another folder with fresh identities. */
    public function copyScene(source:String, targetFolder:String):String {
        if (projectPath == "") throw "Open or create a project before copying assets.";
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
        sys.FileSystem.createDirectory(new Path(to).dir);
        DocumentStore.saveScene(to, document);
        project.assets.push(new AssetRecord(document.id, "scene", destination));
        DocumentStore.saveProject(projectPath, project);
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
        if (projectPath == "") throw "Open or create a project before renaming a scene.";
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
        DocumentStore.saveScene(newPath, document);
        asset.source = allocated.source;
        DocumentStore.saveProject(projectPath, project);
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
        if (projectPath == "") throw "Open or create a project before deleting a scene.";
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
        DocumentStore.saveProject(projectPath, project);
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
        if (projectPath == "") throw "No project path; use Save Project As.";
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

    static function assetFolder(folder:String):String {
        var trimmed = StringTools.trim(folder).split("\\").join("/");
        if (trimmed.length == 0) return "Scenes";
        return ProjectPath.normalizeRelative(trimmed);
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
        return projectPath == "" ? Sys.getCwd() : new Path(projectPath).dir;
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
        var root = normalizeSlashes(sys.FileSystem.absolutePath(new Path(projectPath).dir));
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
