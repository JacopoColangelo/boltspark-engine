import boltspark.engine.Material;
import boltspark.engine.MaterialCulling;
import boltspark.engine.MaterialTextureLibrary;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.DocumentStore;
import boltspark.project.MaterialCodec;
import boltspark.project.MaterialDocument;
import boltspark.project.ProjectSession;
import haxe.io.Path;

/** Headless coverage for material documents and the material asset lifecycle. */
class MaterialEditorRepro {
    static var root:String;
    static var checks:Int = 0;

    static function main() {
        root = Path.join([Sys.getCwd(), "bin", "test-results", "material-editor-repro"]);
        deleteRecursively(root);
        sys.FileSystem.createDirectory(root);
        try {
            testCodec();
            testSession();
            Sys.println('[material-editor-repro] all ${checks} checks passed');
        } catch (e:Dynamic) {
            Sys.println('[material-editor-repro] FAILED: ${Std.string(e)}');
            Sys.exit(1);
        }
    }

    static function testCodec():Void {
        var document = new MaterialDocument("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "Brick", 0xAA3300, "Content/Brick.png", "front", true);
        document.metallic = 0.75;
        document.smoothness = 0.3;
        document.smoothnessSource = boltspark.engine.Material.SMOOTHNESS_ALBEDO_ALPHA;
        document.metallicTexture = "Content/Metal.png";
        document.normalTexture = "Content/Normal.png";
        document.roughnessTexture = "Content/Roughness.png";
        document.occlusionTexture = "Content/AO.png";
        document.emissionColor = 0x224466;
        document.emissionIntensity = 2.5;
        document.tilingX = 3;
        document.tilingY = 4;
        document.offsetX = 0.5;
        Reflect.setField(document.extraFields, "future", "kept");
        var json = MaterialCodec.encode(document);
        var decoded = MaterialCodec.decode(json);
        assertTrue(decoded.id == document.id && decoded.name == "Brick",
            "material identity round-trips");
        assertTrue(decoded.baseColor == 0xAA3300 && decoded.albedoTexture == "Content/Brick.png",
            "color and albedo reference round-trip");
        assertTrue(decoded.metallic == 0.75 && decoded.smoothness == 0.3,
            "metallic/smoothness round-trip");
        assertTrue(decoded.smoothnessSource == boltspark.engine.Material.SMOOTHNESS_ALBEDO_ALPHA
            && decoded.metallicTexture == "Content/Metal.png"
            && decoded.normalTexture == "Content/Normal.png"
            && decoded.roughnessTexture == "Content/Roughness.png"
            && decoded.occlusionTexture == "Content/AO.png",
            "PBR texture slots and smoothness source round-trip");
        assertTrue(decoded.emissionColor == 0x224466 && decoded.emissionIntensity == 2.5,
            "emission color and intensity round-trip");
        assertTrue(decoded.tilingX == 3 && decoded.tilingY == 4 && decoded.offsetX == 0.5,
            "tiling/offset round-trip");
        assertTrue(decoded.culling == "front" && decoded.shadows,
            "culling and shadow flag round-trip");
        assertTrue(Reflect.field(decoded.extraFields, "future") == "kept",
            "unknown material fields are preserved");

        // Legacy schema-1 documents migrate to neutral PBR values.
        var legacy = StringTools.replace(json, '"version": 2', '"version": 1');
        legacy = StringTools.replace(legacy, '"metallic": 0.75', '"specularAmount": 0.4');
        var migrated = MaterialCodec.decode(legacy);
        assertTrue(migrated.metallic == 0 && migrated.smoothness == 0.5,
            "specular materials migrate to metallic/smoothness defaults");
        assertTrue(Reflect.field(migrated.extraFields, "future") == "kept",
            "migration preserves unknown fields");

        var path = Path.join([root, "Brick.boltmaterial"]);
        DocumentStore.saveMaterial(path, document);
        var reloaded = DocumentStore.loadMaterial(path);
        assertTrue(reloaded.name == "Brick", "atomic material save and load round-trip");
        assertTrue(sys.FileSystem.exists(path + ".bak") == false,
            "first material save has no backup");

        var broken = StringTools.replace(json, '"version": 2', '"version": 99');
        assertThrows(function() MaterialCodec.decode(broken),
            "unsupported material schema version is rejected");
    }

    static function testSession():Void {
        var previousCwd = Sys.getCwd();
        var scratch = Path.join([root, "scratch"]);
        sys.FileSystem.createDirectory(scratch);
        Sys.setCwd(scratch);
        var success = false;
        {
            var session = new ProjectSession();
            assertTrue(session.isUntitled(), "session starts untitled");

            var source = session.newMaterial("Brick");
            assertTrue(session.isMaterialPath(source), "new material has the material extension");
            assertTrue(sys.FileSystem.exists(Path.join([scratch, source])),
                "material document was written to the scratch folder");
            var doc = session.loadMaterialDocument(source);
            assertTrue(doc.name == "Brick", "created material loads back");
            assertTrue(Material.findBySource(source) != null,
                "created material is registered in the catalog");

            doc.albedoTexture = "Content/Wall.png";
            doc.baseColor = 0x112233;
            session.saveMaterialDocument(source, doc);
            var saved = session.loadMaterialDocument(source);
            assertTrue(saved.albedoTexture == "Content/Wall.png" && saved.baseColor == 0x112233,
                "edited material persists");
            assertTrue(Material.findBySource(source).albedoTexture == "Content/Wall.png",
                "runtime catalog reflects the saved albedo texture");

            var found = 0;
            for (info in session.scanAllAssets()) {
                if (info.kind == AssetTypeRegistry.KIND_MATERIAL) found++;
            }
            assertTrue(found == 1, "browser scans the material document");

            // Materials honor the folder the caller chooses; Engine is off
            // limits and no folder means the Content root, never a preset
            // subfolder.
            var custom = session.newMaterial("Custom Folder", "Content/MyFolder");
            assertTrue(custom == "Content/MyFolder/Custom Folder.boltmaterial",
                'material honors the chosen content folder: ${custom}');
            assertTrue(sys.FileSystem.exists(Path.join([scratch, custom])),
                "folder-directed material was written to the chosen folder");
            var root = session.newMaterial("Root Folder", "");
            assertTrue(root == "Content/Root Folder.boltmaterial",
                'material with no folder uses the Content root: ${root}');
            var engine = session.newMaterial("No Engine", "Engine/Materials");
            assertTrue(StringTools.startsWith(engine, "Content/"),
                'user material never lands under Engine: ${engine}');

            var renamed = session.renameMaterial(source, "Stone");
            assertTrue(session.loadMaterialDocument(renamed).name == "Stone",
                "renamed material keeps its document");
            assertTrue(Material.find(doc.id).name == "Stone",
                "renamed material updates the live catalog name in place");

            // Browser inline rename goes through renameAnyAsset, not the
            // material-specific path; it must update the document too.
            var browserRenamed = session.renameAnyAsset(renamed, "Metal");
            assertTrue(browserRenamed.indexOf("Metal") >= 0,
                "inline material rename changes the asset path");
            assertTrue(session.loadMaterialDocument(browserRenamed).name == "Metal",
                "inline rename updates the material document name");
            assertTrue(Material.find(doc.id).name == "Metal",
                "inline rename updates the live material name");
            assertTrue(Material.find(doc.id).source == browserRenamed
                && Material.findBySource(browserRenamed) != null,
                "inline rename keeps the runtime source lookup current for drag payloads");
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, source])),
                "old material file is removed on rename");

            session.deleteMaterial(browserRenamed);
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, browserRenamed])),
                "deleted material file is removed");
            assertTrue(Material.findBySource(browserRenamed) == null,
                "deleted material leaves the runtime catalog");
            success = true;
        }
        Sys.setCwd(previousCwd);
        Material.setProjectMaterials([]);
        MaterialTextureLibrary.clear();
        if (!success) throw 'MaterialEditorRepro: session checks did not complete';
    }

    static function assertTrue(condition:Bool, message:String):Void {
        checks++;
        if (!condition) throw 'MaterialEditorRepro: ${message}';
    }

    static function assertThrows(action:Void->Void, message:String):Void {
        checks++;
        var threw = false;
        try {
            action();
        } catch (e:Dynamic) {
            threw = true;
        }
        if (!threw) throw 'MaterialEditorRepro: ${message}';
    }

    static function deleteRecursively(path:String):Void {
        if (!sys.FileSystem.exists(path)) return;
        for (entry in sys.FileSystem.readDirectory(path)) {
            var child = Path.join([path, entry]);
            if (sys.FileSystem.isDirectory(child)) deleteRecursively(child);
            else sys.FileSystem.deleteFile(child);
        }
        sys.FileSystem.deleteDirectory(path);
    }
}
