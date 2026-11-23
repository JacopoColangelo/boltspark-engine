import boltspark.assets.GltfParser;
import boltspark.assets.ImportedMeshLibrary;
import boltspark.assets.MeshParser;
import boltspark.assets.ObjParser;
import boltspark.engine.PrimitiveMeshes;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.ProjectSession;
import haxe.io.Bytes;
import haxe.io.Path;

/** Headless coverage for OBJ/glTF parsing and project mesh import. */
class MeshImportRepro {
    static var root:String;
    static var checks:Int = 0;

    static function main() {
        root = Path.join([Sys.getCwd(), "bin", "test-results", "mesh-import-repro"]);
        deleteRecursively(root);
        sys.FileSystem.createDirectory(root);
        try {
            testRegistry();
            testObj();
            testGltf();
            testImport();
            Sys.println('[mesh-import-repro] all ${checks} checks passed');
        } catch (e:Dynamic) {
            Sys.println('[mesh-import-repro] FAILED: ${Std.string(e)}');
            Sys.exit(1);
        }
    }

    static function testRegistry():Void {
        for (extension in AssetTypeRegistry.MESH_EXTENSIONS) {
            assertTrue(AssetTypeRegistry.isMeshExtension(extension),
                '${extension} is a recognized mesh extension');
            assertTrue(AssetTypeRegistry.infoFor("Model." + extension.toUpperCase()).kind
                == AssetTypeRegistry.KIND_MESH, '${extension} classifies as a mesh');
        }
        assertTrue(!AssetTypeRegistry.isMeshFile("notes.txt"),
            "plain text is not an importable mesh");
    }

    static function testObj():Void {
        var source = '# cube-ish\n'
            + 'o TestMesh\n'
            + 'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\n'
            + 'vn 0 0 1\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\n'
            + 'f 1/1/1 2/2/1 3/3/1 4/4/1\n';
        var path = Path.join([root, "quad.obj"]);
        sys.io.File.saveContent(path, source);
        var geometry = MeshParser.parse(path);
        assertTrue(geometry.name == "TestMesh", "OBJ object name is preserved");
        assertTrue(Std.int(geometry.positions.length / 3) == 4,
            "OBJ vertex channels stay parallel");
        assertTrue(geometry.indices.length == 6, "OBJ quad is triangulated into two triangles");
        assertTrue(geometry.uvs.length == 8 && geometry.normals.length == 12,
            "OBJ UVs and normals are expanded per vertex");
        assertTrue(geometry.positions[0] == 0 && geometry.positions[3] == 1,
            "OBJ positions are parsed in order");

        var direct = ObjParser.parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n", "Tri");
        assertTrue(direct.indices.length == 3 && direct.normals.length == 9,
            "OBJ without normals/UVs gets zero-filled channels");
    }

    static function testGltf():Void {
        var bytes = Bytes.alloc(18);
        // 3 VEC3 positions as little-endian UNSIGNED_SHORT values.
        var values = [0, 0, 0, 1, 0, 0, 0, 1, 0];
        for (i in 0...values.length) {
            bytes.set(i * 2, values[i] & 0xFF);
            bytes.set(i * 2 + 1, (values[i] >> 8) & 0xFF);
        }
        for (i in 0...3) {
            bytes.set(12 + i * 2, i);
            bytes.set(12 + i * 2 + 1, 0);
        }
        var base64 = haxe.crypto.Base64.encode(bytes);
        var json = '{"asset":{"version":"2.0"},'
            + '"buffers":[{"byteLength":18,"uri":"data:application/octet-stream;base64,${base64}"}],'
            + '"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":12},'
            + '{"buffer":0,"byteOffset":12,"byteLength":6}],'
            + '"accessors":[{"bufferView":0,"componentType":5123,"count":3,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],'
            + '"meshes":[{"name":"GltfTri","primitives":[{"attributes":{"POSITION":0},'
            + '"indices":1,"mode":4}]}]}';
        var path = Path.join([root, "tri.gltf"]);
        sys.io.File.saveContent(path, json);
        var geometry = MeshParser.parse(path);
        assertTrue(geometry.name == "GltfTri", "glTF mesh name is preserved");
        assertTrue(geometry.positions.length == 9 && geometry.indices.length == 3,
            "glTF accessors decode positions and indices");
        assertTrue(geometry.positions[3] == 1 && geometry.positions[7] == 1,
            "glTF vertex values decode correctly");
    }

    static function testImport():Void {
        var previousCwd = Sys.getCwd();
        var scratch = Path.join([root, "scratch"]);
        sys.FileSystem.createDirectory(scratch);
        var source = Path.join([root, "imported.obj"]);
        sys.io.File.saveContent(source, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n");
        Sys.setCwd(scratch);
        var complete = false;
        try {
            var session = new ProjectSession();
            var imported = session.importMeshAssets([source], "");
            assertTrue(imported.length == 1 && AssetTypeRegistry.isMeshFile(imported[0]),
                "mesh import copies the source and registers a mesh asset");
            var found = false;
            for (asset in session.project.assets) {
                if (asset.type == "mesh") found = true;
            }
            assertTrue(found, "mesh import writes a type:mesh manifest record");
            var listed = 0;
            for (info in session.scanAllAssets()) {
                if (info.kind == AssetTypeRegistry.KIND_MESH) listed++;
            }
            assertTrue(listed == 1, "browser discovers the imported mesh");

            var loaded = session.refreshMeshAssets();
            assertTrue(loaded == 1, "mesh library parses the imported file");
            assertTrue(ImportedMeshLibrary.find(ImportedMeshLibrary.idFor(imported[0])) != null,
                "imported mesh geometry is available to the runtime binding");
            assertTrue(ImportedMeshLibrary.idFor(imported[0])
                == ImportedMeshLibrary.idFor(imported[0]),
                "imported mesh ids are deterministic");

            var renamed = session.renameAnyAsset(imported[0], "Renamed");
            assertTrue(renamed != imported[0], "mesh rename allocates a new source");
            assertTrue(hasMeshRecord(session, renamed), "mesh rename repoints the manifest record");
            assertTrue(!hasMeshRecord(session, imported[0]), "old mesh record is removed on rename");

            session.createFolder("", "Meshes");
            var moved = session.moveAnyAsset(renamed, "Content/Meshes");
            assertTrue(hasMeshRecord(session, moved), "mesh move repoints the manifest record");
            var copied = session.copyAnyAsset(moved, "Content");
            assertTrue(hasMeshRecord(session, copied), "mesh copy registers a new record");
            assertTrue(assetIdFor(session, moved) != assetIdFor(session, copied),
                "copied mesh gets its own durable asset id");
            session.deleteAnyAsset(copied);
            assertTrue(!hasMeshRecord(session, copied), "mesh delete removes the manifest record");
            complete = true;
        } catch (e:Dynamic) {
            Sys.setCwd(previousCwd);
            throw e;
        }
        Sys.setCwd(previousCwd);
        ImportedMeshLibrary.clear();
        if (!complete) throw 'MeshImportRepro: session checks did not complete';
    }

    static function hasMeshRecord(session:ProjectSession, source:String):Bool {
        for (asset in session.project.assets) {
            if (asset.type == "mesh" && asset.source == source) return true;
        }
        return false;
    }

    static function assetIdFor(session:ProjectSession, source:String):String {
        for (asset in session.project.assets) {
            if (asset.source == source) return asset.id;
        }
        return "";
    }

    static function assertTrue(condition:Bool, message:String):Void {
        checks++;
        if (!condition) throw 'MeshImportRepro: ${message}';
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
