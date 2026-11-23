package boltspark.assets;

using hxd.fmt.fbx.Data;

/**
 * FBX reader built on the pinned Heaps FBX parser. Uses the engine-free
 * `hxd.fmt.fbx.Geometry` accessors, so it works in headless imports without a
 * live h3d.Engine. Only the first geometry's first UV set is imported.
 */
class FbxParser {
    public static function parse(path:String, name:String = ""):MeshGeometry {
        var bytes = sys.io.File.getBytes(path);
        var root:hxd.fmt.fbx.Data.FbxNode;
        try {
            root = hxd.fmt.fbx.Parser.parse(bytes);
        } catch (e:Dynamic) {
            throw 'FBX could not be parsed: ${Std.string(e)}';
        }
        var library = new hxd.fmt.fbx.BaseLibrary(path);
        library.load(root);
        var nodes:Array<hxd.fmt.fbx.Data.FbxNode> = root.getAll("Objects.Geometry");
        if (nodes == null || nodes.length == 0) throw 'FBX has no geometry: ${path}';
        var geometry = new hxd.fmt.fbx.Geometry(library, nodes[0]);

        var sourceVertices:Array<Float> = geometry.getVertices();
        var sourceNormals:Array<Float> = [];
        try {
            sourceNormals = geometry.getNormals();
        } catch (e:Dynamic) {}
        if (sourceNormals == null) sourceNormals = [];
        var uvSets:Array<Dynamic> = geometry.getUVs();
        var sourceUVs:Array<Float> = [];
        var uvIndices:Array<Int> = [];
        if (uvSets != null && uvSets.length > 0) {
            sourceUVs = uvSets[0].values;
            uvIndices = uvSets[0].index;
        }
        if (sourceUVs == null) sourceUVs = [];
        if (uvIndices == null) uvIndices = [];
        var triangulated = geometry.getIndexes();
        var cornerVertices:Array<Int> = triangulated.vidx;
        var cornerIndexes:Array<Int> = triangulated.idx;

        var positions:Array<Float> = [];
        var normals:Array<Float> = [];
        var uvs:Array<Float> = [];
        var indices:Array<Int> = [];
        for (corner in cornerIndexes) {
            if (corner < 0 || corner >= cornerVertices.length) continue;
            var sourceVertex = cornerVertices[corner];
            if (sourceVertex < 0 || sourceVertex * 3 + 2 >= sourceVertices.length) continue;
            indices.push(Std.int(positions.length / 3));
            positions.push(sourceVertices[sourceVertex * 3]);
            positions.push(sourceVertices[sourceVertex * 3 + 1]);
            positions.push(sourceVertices[sourceVertex * 3 + 2]);
            if (sourceVertex * 3 + 2 < sourceNormals.length) {
                normals.push(sourceNormals[sourceVertex * 3]);
                normals.push(sourceNormals[sourceVertex * 3 + 1]);
                normals.push(sourceNormals[sourceVertex * 3 + 2]);
            } else {
                normals.push(0);
                normals.push(0);
                normals.push(0);
            }
            var uvIndex = (uvIndices != null && corner < uvIndices.length)
                ? uvIndices[corner] : corner;
            if (uvIndex * 2 + 1 < sourceUVs.length) {
                uvs.push(sourceUVs[uvIndex * 2]);
                uvs.push(sourceUVs[uvIndex * 2 + 1]);
            } else {
                uvs.push(0);
                uvs.push(0);
            }
        }
        var displayName = name;
        if (displayName == "") {
            var nodeName = nodes[0].name;
            displayName = nodeName == null || nodeName == "" ? "Imported Mesh" : nodeName;
        }
        return {
            name: displayName,
            positions: positions,
            normals: normals,
            uvs: uvs,
            indices: indices
        };
    }
}
