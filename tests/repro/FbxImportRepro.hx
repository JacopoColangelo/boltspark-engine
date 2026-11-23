import boltspark.assets.FbxParser;
import haxe.io.Path;

/** Runtime-only FBX decode coverage using a tiny ASCII FBX 7.4 fixture. */
class FbxImportRepro {
    static function main() {
        var root = Path.join([Sys.getCwd(), "bin", "test-results", "fbx-import-repro"]);
        deleteRecursively(root);
        sys.FileSystem.createDirectory(root);
        var path = Path.join([root, "tri.fbx"]);
        sys.io.File.saveContent(path,
            '; FBX 7.4.0 project file\n'
            + 'FBXHeaderExtension:  {\n'
            + ' FBXHeaderVersion: 1003\n'
            + ' FBXVersion: 7400\n'
            + '}\n'
            + 'GlobalSettings:  {\n'
            + ' Version: 1000\n'
            + ' Properties70:  {\n'
            + '  P: "UpAxis", "int", "Integer", "",1\n'
            + '  P: "OriginalUpAxis", "int", "Integer", "",1\n'
            + '  P: "UnitScaleFactor", "double", "Number", "",1\n'
            + ' }\n'
            + '}\n'
            + 'Objects:  {\n'
            + ' Geometry: 1000, "Geometry::TestMesh", "Mesh" {\n'
            + '  Vertices: *9 {\n'
            + '   a: 0,0,0,1,0,0,0,1,0\n'
            + '  }\n'
            + '  PolygonVertexIndex: *3 {\n'
            + '   a: 0,1,-3\n'
            + '  }\n'
            + '  LayerElementNormal: 0 {\n'
            + '   Version: 101\n'
            + '   MappingInformationType: "ByPolygonVertex"\n'
            + '   ReferenceInformationType: "Direct"\n'
            + '   Normals: *9 {\n'
            + '    a: 0,0,1,0,0,1,0,0,1\n'
            + '   }\n'
            + '  }\n'
            + '  LayerElementUV: 0 {\n'
            + '   Version: 101\n'
            + '   MappingInformationType: "ByPolygonVertex"\n'
            + '   ReferenceInformationType: "IndexToDirect"\n'
            + '   UV: *6 {\n'
            + '    a: 0,0,1,0,0,1\n'
            + '   }\n'
            + '   UVIndex: *3 {\n'
            + '    a: 0,1,2\n'
            + '   }\n'
            + '  }\n'
            + ' }\n'
            + '}\n'
            + 'Connections:  {\n'
            + '}\n');
        var geometry:Dynamic = null;
        try {
            geometry = FbxParser.parse(path);
        } catch (e:Dynamic) {
            Sys.println('FBX parse error: ${Std.string(e)}');
            Sys.println(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            Sys.exit(1);
        }
        assertTrue(geometry.positions.length == 9, "FBX vertices decode");
        assertTrue(geometry.indices.length == 3, "FBX triangle decodes");
        assertTrue(geometry.normals.length == 9 && geometry.uvs.length == 6,
            "FBX normals and UVs decode");
        assertTrue((geometry.positions[3] == 1 || geometry.positions[6] == 1)
            && (geometry.positions[7] == 1 || geometry.positions[4] == 1),
            "FBX vertex values decode");
        Sys.println('[fbx-import-repro] all 4 checks passed');
    }

    static function assertTrue(condition:Bool, message:String):Void {
        if (!condition) throw 'FbxImportRepro: ${message}';
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
