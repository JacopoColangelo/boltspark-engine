import boltspark.editor.EditorObject;
import boltspark.editor.EditorSession;
import boltspark.engine.MeshRenderer;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.project.ProjectSession;
import haxe.io.Path;

/** Headless coverage for the integrated project/scene session layer. */
class ProjectSessionRepro {
    static var root:String;

    static function main():Void {
        root = Path.join([Sys.getCwd(), "bin", "test-results", "project-session"]);
        deleteRecursively(root);
        sys.FileSystem.createDirectory(root);

        var projectPath = Path.join([root, "Demo Project.boltproject"]);
        var untitled = new ProjectSession();
        var sourceSession = new EditorSession();
        var parent = sourceSession.addInitialObject("Parent", null, null,
            PrimitiveGameObjects.cubeComponents());
        sourceSession.createChild(parent.id, "Child");
        parent.transform.value.positionX = 12;
        parent.transform.value.positionY = -4;
        parent.transform.value.positionZ = 7;
        untitled.captureScene(sourceSession);
        assertTrue(!untitled.dirty, "untitled capture starts clean");
        assertTrue(untitled.projectPath == "", "untitled manifest path is empty");

        // Save As persists the current editor graph; New Project starts empty.
        untitled.saveAs(projectPath, sourceSession);
        assertTrue(sys.FileSystem.exists(projectPath), "project manifest written");
        assertTrue(sys.FileSystem.exists(untitled.scenePath), "default scene written");
        assertTrue(untitled.project.name == "Demo Project", "project name persisted");
        assertTrue(untitled.project.defaultSceneId == untitled.scene.id,
            "default scene id bound");
        assertTrue(untitled.project.assets.length == 1, "one scene asset registered");

        var reopened = new ProjectSession();
        reopened.openProject(projectPath);
        assertTrue(reopened.project.name == "Demo Project", "reopened project name");
        assertTrue(reopened.scene.name == "Main Scene", "reopened scene name");
        assertTrue(reopened.scene.entities.length == 2, "both entities round-tripped");
        assertTrue(!reopened.dirty, "fresh open is clean");
        assertTrue(reopened.sceneSource.indexOf("\\") < 0, "scene asset path uses slashes");

        var loadedSession = reopened.createSession();
        assertTrue(loadedSession.objects.length == 2, "editor session rebuilt");
        var loadedParent = findByName(loadedSession, "Parent");
        var loadedChild = findByName(loadedSession, "Child");
        assertTrue(loadedParent != null && loadedChild != null, "object names restored");
        assertTrue(loadedChild.parent == loadedParent, "hierarchy restored");
        assertTrue(Math.abs(loadedParent.transform.value.positionX - 12) < 0.001,
            "transform restored");
        assertTrue(hasMeshRenderer(loadedSession), "components restored");

        // Dirty state follows history, not selection/view notifications.
        loadedSession.selectObject(loadedParent.id);
        reopened.syncDirty(loadedSession);
        assertTrue(!reopened.dirty, "selection does not mark the project dirty");
        var beforeEdit = loadedParent.transform.value.clone();
        loadedParent.transform.value.positionX = 13;
        loadedSession.commitAppliedTransform(loadedParent.id, beforeEdit,
            loadedParent.transform.value, "test edit");
        reopened.syncDirty(loadedSession);
        assertTrue(reopened.dirty, "history edit marks the project dirty");
        reopened.clearDirty();

        // Save clears dirty state and upgrades the atomic-save backup.
        reopened.markDirty();
        assertTrue(reopened.dirty, "edits mark the project dirty");
        assertTrue(StringTools.endsWith(reopened.title(), " *"), "dirty marker in title");
        loadedParent.transform.value.positionX = 20;
        reopened.captureScene(loadedSession);
        reopened.save(loadedSession);
        assertTrue(!reopened.dirty, "save clears dirty state");
        assertTrue(sys.FileSystem.exists(projectPath + ".bak"), "atomic save backup created");
        var verified = new ProjectSession();
        verified.openProject(projectPath);
        var verifiedSession = verified.createSession();
        assertTrue(Math.abs(findByName(verifiedSession, "Parent").transform.value.positionX
            - 20) < 0.001, "saved edit reloads");

        // New scene registration and Save As.
        verified.newScene("Second Level");
        assertTrue(verified.dirty, "new scene is dirty until saved");
        assertTrue(verified.project.assets.length == 2, "new scene asset registered");
        assertTrue(verified.project.defaultSceneId == verified.scene.id,
            "new scene becomes default");
        var secondPath = Path.join([root, "Renamed Project.boltproject"]);
        verified.saveAs(secondPath, verified.createSession());
        assertTrue(verified.projectPath == sys.FileSystem.absolutePath(secondPath),
            "save as updates project path");
        assertTrue(sys.FileSystem.exists(verified.scenePath), "save as writes scene");
        assertTrue(!verified.dirty, "save as clears dirty state");

        verified.saveScene(verified.createSession());
        assertTrue(!verified.dirty, "scene-only save clears dirty state");

        // Failure paths must not corrupt the current documents.
        assertThrows(function() verified.openProject(Path.join([root, "missing.boltproject"])),
            "missing project rejected");
        assertThrows(function() verified.openProject(Path.join([root, "bad.txt"])),
            "non-project path does not resolve without a .boltproject file");
        var bomProject = Path.join([root, "Bom.boltproject"]);
        sys.io.File.saveContent(bomProject,
            String.fromCharCode(0xFEFF) + sys.io.File.getContent(projectPath));
        var bomSession = new ProjectSession();
        bomSession.openProject(bomProject);
        assertTrue(bomSession.project.name == "Demo Project", "UTF-8 BOM tolerated on load");

        var badVersion = Path.join([root, "future.boltproject"]);
        sys.io.File.saveContent(badVersion, '{"version":99}');
        assertThrows(function() verified.openProject(badVersion),
            "unsupported schema version rejected");
        var outside = Path.join([Sys.getCwd(), "bin", "outside.boltscene"]);
        sys.io.File.saveContent(outside, '{"version":1,"id":"44444444444444444444444444444444","name":"Outside","entities":[]}');
        assertThrows(function() verified.openScene(outside), "outside scene rejected");
        assertTrue(verified.project.name == "Renamed Project",
            "failed opens keep current project");

        var fresh = new ProjectSession();
        var freshPath = Path.join([root, "Fresh Project.boltproject"]);
        fresh.createProject(freshPath, "Fresh Project");
        assertTrue(fresh.scene.entities.length == 0, "new project starts with empty scene");
        assertTrue(fresh.createSession().objects.length == 0, "empty scene rebuilds cleanly");
        assertTrue(sys.FileSystem.exists(freshPath), "new project manifest written");
        assertThrows(function() fresh.createProject(freshPath, "Duplicate"),
            "existing project is not overwritten");

        // The native picker can return a bare name without the filter
        // extension; all project paths normalize it to the implied suffix.
        var barePath = Path.join([root, "Bare Name"]);
        var bare = new ProjectSession();
        var bareSession = new EditorSession();
        bareSession.addInitialObject("Bare Cube", null, null,
            PrimitiveGameObjects.cubeComponents());
        bare.saveAs(barePath, bareSession);
        assertTrue(sys.FileSystem.exists(barePath + ".boltproject"),
            "extensionless save appends .boltproject");
        assertTrue(sys.FileSystem.exists(bare.scenePath), "bare-name scene written");
        var bareReopen = new ProjectSession();
        bareReopen.openProject(barePath);
        assertTrue(bareReopen.createSession().objects.length == 1,
            "extensionless open loads the project");
        assertTrue(bareReopen.project.name == "Bare Name", "bare-name project title");

        var bareFreshPath = Path.join([root, "Bare Fresh"]);
        var bareFresh = new ProjectSession();
        bareFresh.createProject(bareFreshPath, "Bare Fresh");
        assertTrue(sys.FileSystem.exists(bareFreshPath + ".boltproject"),
            "extensionless create appends .boltproject");

        // A new scene must not overwrite the previous one: each gets a fresh
        // identity, display name, and source path, and prior scenes stay usable.
        var multi = new ProjectSession();
        var multiPath = Path.join([root, "Multi Scene.boltproject"]);
        multi.saveAs(multiPath, sourceSession);
        var firstSource = multi.sceneSource;
        var firstPath = multi.scenePath;
        assertTrue(multi.sceneSources().length == 1, "one initial scene registered");

        multi.newScene();
        assertTrue(multi.scene.name == "Main Scene 2", "second scene gets a unique name");
        assertTrue(multi.sceneSource != firstSource, "second scene gets a unique path");
        assertTrue(multi.sceneSources().length == 2, "both scenes registered");
        assertTrue(sys.FileSystem.exists(firstPath), "first scene file preserved");
        assertTrue(multi.createSession().objects.length == 0, "new scene is empty");

        multi.newScene("Main Scene");
        assertTrue(multi.scene.name == "Main Scene 3",
            "explicit duplicate name is disambiguated");
        assertTrue(multi.sceneSources().length == 3, "third scene registered");

        multi.newScene("Custom Level");
        assertTrue(multi.scene.name == "Custom Level", "distinct scene name is kept");
        multi.save(multi.createSession());
        var reloaded = new ProjectSession();
        reloaded.openProject(multiPath);
        assertTrue(reloaded.sceneSources().length == 4, "all scenes survive reload");
        reloaded.openSceneSource(firstSource);
        var restored = reloaded.createSession();
        assertTrue(restored.objects.length == 2,
            "switching back restores the original scene graph");
        assertTrue(ProjectSession.sceneDisplayName(firstSource) == "Main Scene",
            "scene display name derived from source");

        // Rename and delete are manifest-aware and never leave a dangling
        // default scene or an orphaned file behind.
        var sceneDir = new Path(multiPath).dir;
        reloaded.renameScene("Scenes/Custom Level.boltscene", "Final Level");
        assertTrue(reloaded.sceneSources().indexOf("Scenes/Final Level.boltscene") >= 0,
            "renamed scene registered under its new source");
        assertTrue(!sys.FileSystem.exists(Path.join([sceneDir, "Scenes",
            "Custom Level.boltscene"])), "old renamed scene file removed");
        assertTrue(sys.FileSystem.exists(Path.join([sceneDir, "Scenes",
            "Final Level.boltscene"])), "renamed scene file written");

        reloaded.deleteScene("Scenes/Main Scene 2.boltscene");
        assertTrue(reloaded.sceneSources().length == 3, "deleted scene unregistered");
        var checked = new ProjectSession();
        checked.openProject(multiPath);
        assertTrue(checked.sceneSources().length == 3, "deletion persisted in manifest");
        checked.deleteScene(checked.sceneSources()[1]);
        checked.deleteScene(checked.sceneSources()[0]);
        assertThrows(function() checked.deleteScene(checked.sceneSources()[0]),
            "last remaining scene cannot be deleted");

        // The Asset Browser reads real files under the project root, including
        // unregistered ones and scenes in nested folders.
        var discovered = checked.scanAssets();
        assertTrue(discovered.length >= 1, "asset scan finds scene files on disk");
        assertTrue(discovered[0].folder == "Scenes", "asset scan reports folder");
        assertTrue(discovered[0].kind == "scene", "asset scan reports asset kind");

        var folderSession = new ProjectSession();
        folderSession.saveAs(Path.join([root, "Folder Scene.boltproject"]), sourceSession);
        folderSession.newScene("Nested", "Levels/Second");
        assertTrue(folderSession.sceneSource == "Levels/Second/Nested.boltscene",
            "new scene honors the chosen folder");
        folderSession.save(folderSession.createSession());
        assertTrue(sys.FileSystem.exists(Path.join([root, "Levels", "Second",
            "Nested.boltscene"])), "nested scene file written");
        var nested = false;
        for (asset in folderSession.scanAssets()) {
            if (asset.source == "Levels/Second/Nested.boltscene") nested = true;
        }
        assertTrue(nested, "asset scan finds scenes in nested folders");

        // Folders are first-class: create, move, and copy assets between them.
        var createdFolder = folderSession.createFolder("Scenes", "Archive");
        assertTrue(createdFolder == "Scenes/Archive", "folder created with unique path");
        assertTrue(folderSession.scanFolders().indexOf("Scenes/Archive") >= 0,
            "new folder discovered by scan");
        folderSession.moveScene("Scenes/Main Scene.boltscene", "Scenes/Archive");
        assertTrue(folderSession.sceneSources().indexOf(
            "Scenes/Archive/Main Scene.boltscene") >= 0,
            "moved scene updated in manifest");
        var renamedFolder = folderSession.renameFolder("Scenes/Archive", "Vault");
        assertTrue(renamedFolder == "Scenes/Vault", "folder renamed");
        assertTrue(folderSession.scanFolders().indexOf("Scenes/Vault") >= 0,
            "renamed folder discovered");
        assertTrue(folderSession.sceneSources().indexOf(
            "Scenes/Vault/Main Scene.boltscene") >= 0,
            "asset paths repointed after folder rename");
        var copiedScene = folderSession.copyScene(
            "Scenes/Vault/Main Scene.boltscene", "Scenes");
        assertTrue(copiedScene == "Scenes/Main Scene.boltscene",
            "copied scene restored to the free source path");
        assertTrue(sys.FileSystem.exists(Path.join([root, copiedScene])),
            "copied scene file written");

        // Switching between registered scenes is a navigation action, not an
        // edit: it must not dirty the project or force a resave.
        var switcher = new ProjectSession();
        var switchPath = Path.join([root, "Switch.boltproject"]);
        switcher.saveAs(switchPath, sourceSession);
        switcher.newScene("Second Scene", "Scenes");
        switcher.persistSceneDocument();
        switcher.openSceneSource("Scenes/Main Scene.boltscene");
        assertTrue(!switcher.dirty, "switching to a registered scene stays clean");
        switcher.openSceneSource("Scenes/Second Scene.boltscene");
        assertTrue(!switcher.dirty, "switching back stays clean");

        Sys.println("[ProjectSessionRepro] all project session checks passed");
    }

    static function hasMeshRenderer(session:EditorSession):Bool {
        for (object in session.objects) {
            for (component in object.components) {
                if (Std.isOfType(component, MeshRenderer)) return true;
            }
        }
        return false;
    }

    static function findByName(session:EditorSession, name:String):EditorObject {
        for (object in session.objects) if (object.name == name) return object;
        return null;
    }

    static function assertTrue(condition:Bool, message:String):Void {
        if (!condition) throw 'FAIL: ${message}';
    }

    static function assertThrows(action:Void->Void, message:String):Void {
        var threw = false;
        try action() catch (e:Dynamic) threw = true;
        if (!threw) throw 'FAIL: ${message}';
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
