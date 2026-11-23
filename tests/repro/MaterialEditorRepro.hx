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
            "Brick", 0xAA3300, "Content/Brick.png", 0.4, 32, "front", true);
        Reflect.setField(document.extraFields, "future", "kept");
        var json = MaterialCodec.encode(document);
        var decoded = MaterialCodec.decode(json);
        assertTrue(decoded.id == document.id && decoded.name == "Brick",
            "material identity round-trips");
        assertTrue(decoded.baseColor == 0xAA3300 && decoded.albedoTexture == "Content/Brick.png",
            "color and albedo reference round-trip");
        assertTrue(decoded.specularAmount == 0.4 && decoded.specularPower == 32,
            "specular values round-trip");
        assertTrue(decoded.culling == "front" && decoded.shadows,
            "culling and shadow flag round-trip");
        assertTrue(Reflect.field(decoded.extraFields, "future") == "kept",
            "unknown material fields are preserved");

        var path = Path.join([root, "Brick.boltmaterial"]);
        DocumentStore.saveMaterial(path, document);
        var reloaded = DocumentStore.loadMaterial(path);
        assertTrue(reloaded.name == "Brick", "atomic material save and load round-trip");
        assertTrue(sys.FileSystem.exists(path + ".bak") == false,
            "first material save has no backup");

        var broken = StringTools.replace(json, '"version": 1', '"version": 99');
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

            var renamed = session.renameMaterial(source, "Stone");
            assertTrue(session.loadMaterialDocument(renamed).name == "Stone",
                "renamed material keeps its document");
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, source])),
                "old material file is removed on rename");

            session.deleteMaterial(renamed);
            assertTrue(!sys.FileSystem.exists(Path.join([scratch, renamed])),
                "deleted material file is removed");
            assertTrue(Material.findBySource(renamed) == null,
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
