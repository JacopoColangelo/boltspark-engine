import boltspark.project.DocumentStore;
import boltspark.project.ProjectCodec;
import boltspark.project.ProjectPath;
import boltspark.project.ProjectValidator;
import boltspark.project.SceneEntityData;
import boltspark.project.SceneCodec;
import boltspark.project.StableId;
import sys.FileSystem;
import sys.io.File;

/** Headless versioning, validation, unknown-field, and atomic-save regression. */
class ProjectSerializationRepro {
    static function main():Void {
        var projectText = File.getContent("tests/fixtures/project/sample.boltproject");
        var sceneText = File.getContent("tests/fixtures/project/Scenes/Main.boltscene");
        var project = ProjectCodec.decode(projectText);
        var scene = SceneCodec.decode(sceneText);
        assertTrue(project.assets.length == 1, "fixture asset missing");
        assertTrue(scene.entities.length == 1, "fixture entity missing");
        assertTrue(scene.entities[0].transform.scaleY == -2, "signed scale changed");

        var projectRoundTrip = ProjectCodec.decode(ProjectCodec.encode(project));
        var sceneRoundTrip = SceneCodec.decode(SceneCodec.encode(scene));
        assertTrue(Reflect.field(projectRoundTrip.extraFields, "fixtureProjectNote") == "preserve me",
            "unknown project field was lost");
        assertTrue(Reflect.field(projectRoundTrip.assets[0].extraFields,
            "fixtureAssetNote") == "preserve me", "unknown asset field was lost");
        assertTrue(Reflect.field(sceneRoundTrip.extraFields, "fixtureSceneNote") == "preserve me",
            "unknown scene field was lost");
        assertTrue(Reflect.field(sceneRoundTrip.entities[0].components[0].extraFields,
            "fixtureComponentNote") == "preserve me", "unknown component field was lost");

        assertThrows(function() ProjectPath.normalizeRelative("../escape.scene"),
            "path traversal was accepted");
        assertThrows(function() ProjectCodec.decode(StringTools.replace(projectText,
            "Scenes/Main.boltscene", "C:\\outside.scene")), "absolute path was accepted");
        assertThrows(function() ProjectCodec.decode(StringTools.replace(projectText,
            '"version": 1', '"version": 99')), "unsupported schema was accepted");

        var duplicateScene = SceneCodec.decode(sceneText);
        duplicateScene.entities.push(duplicateScene.entities[0]);
        assertThrows(function() ProjectValidator.validateScene(duplicateScene),
            "duplicate entity ID was accepted");

        var missingParentScene = SceneCodec.decode(sceneText);
        missingParentScene.entities[0].parentId = "44444444444444444444444444444444";
        assertThrows(function() ProjectValidator.validateScene(missingParentScene),
            "missing parent reference was accepted");

        var cycleScene = SceneCodec.decode(sceneText);
        var second = new SceneEntityData("44444444444444444444444444444444",
            "Cycle Peer", cycleScene.entities[0].id);
        cycleScene.entities[0].parentId = second.id;
        cycleScene.entities.push(second);
        assertThrows(function() ProjectValidator.validateScene(cycleScene),
            "parent cycle was accepted");

        var singularScene = SceneCodec.decode(sceneText);
        singularScene.entities[0].transform.scaleX = 0;
        assertThrows(function() ProjectValidator.validateScene(singularScene),
            "singular scale was accepted");

        var generatedA = StableId.create("test");
        var generatedB = StableId.create("test");
        assertTrue(StableId.isValid(generatedA) && generatedA != generatedB,
            "generated stable IDs were invalid or repeated");

        var outputDir = "bin/test-results/project-serialization";
        if (!FileSystem.exists("bin")) FileSystem.createDirectory("bin");
        if (!FileSystem.exists("bin/test-results")) FileSystem.createDirectory("bin/test-results");
        if (!FileSystem.exists(outputDir)) FileSystem.createDirectory(outputDir);
        var projectPath = outputDir + "/roundtrip.boltproject";
        DocumentStore.saveProject(projectPath, project);
        project.name = "Serialization Fixture Updated";
        DocumentStore.saveProject(projectPath, project);
        assertTrue(FileSystem.exists(projectPath + ".bak"), "atomic save backup missing");
        assertTrue(DocumentStore.loadProject(projectPath).name == project.name,
            "atomic project reload mismatch");

        Sys.println("[project-serialization] versioned round-trip, validation, and atomic save passed");
    }

    static function assertThrows(action:Void->Void, message:String):Void {
        try {
            action();
        } catch (_:Dynamic) {
            return;
        }
        throw message;
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
