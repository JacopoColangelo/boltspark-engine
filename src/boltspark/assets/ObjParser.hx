package boltspark.assets;

/** Minimal Wavefront OBJ reader: vertices, normals, UVs, and triangulated faces. */
class ObjParser {
    public static function parse(contents:String, name:String = ""):MeshGeometry {
        var sourceV:Array<Array<Float>> = [];
        var sourceVN:Array<Array<Float>> = [];
        var sourceVT:Array<Array<Float>> = [];
        var positions:Array<Float> = [];
        var normals:Array<Float> = [];
        var uvs:Array<Float> = [];
        var indices:Array<Int> = [];
        var cache:Map<String, Int> = new Map();
        var displayName = name;

        for (raw in contents.split("\n")) {
            var line = StringTools.trim(raw);
            if (line.length == 0 || line.charAt(0) == "#") continue;
            var fields = line.split(" ");
            fields = [for (field in fields) if (field.length > 0) field];
            if (fields.length == 0) continue;
            switch (fields[0]) {
                case "o" | "g":
                    if (displayName == "" && fields.length > 1) displayName = fields[1];
                case "v":
                    if (fields.length >= 4) {
                        sourceV.push([number(fields[1]), number(fields[2]), number(fields[3])]);
                    }
                case "vn":
                    if (fields.length >= 4) {
                        sourceVN.push([number(fields[1]), number(fields[2]), number(fields[3])]);
                    }
                case "vt":
                    if (fields.length >= 2) {
                        sourceVT.push([number(fields[1]),
                            fields.length >= 3 ? number(fields[2]) : 0]);
                    }
                case "f":
                    var corners:Array<Int> = [];
                    for (index in 1...fields.length) {
                        var corner = resolveCorner(fields[index], sourceV, sourceVN,
                            sourceVT, positions, normals, uvs, cache);
                        if (corner >= 0) corners.push(corner);
                    }
                    if (corners.length >= 3) {
                        for (i in 1...corners.length - 1) {
                            indices.push(corners[0]);
                            indices.push(corners[i]);
                            indices.push(corners[i + 1]);
                        }
                    }
                default:
            }
        }
        if (displayName == "") displayName = "Imported Mesh";
        return {
            name: displayName,
            positions: positions,
            normals: normals,
            uvs: uvs,
            indices: indices
        };
    }

    static function number(value:String):Float {
        var parsed = Std.parseFloat(value);
        return Math.isFinite(parsed) ? parsed : 0;
    }

    /** Expand an OBJ v/vt/vn token into a parallel output vertex, caching duplicates. */
    static function resolveCorner(token:String, sourceV:Array<Array<Float>>,
            sourceVN:Array<Array<Float>>, sourceVT:Array<Array<Float>>,
            positions:Array<Float>, normals:Array<Float>, uvs:Array<Float>,
            cache:Map<String, Int>):Int {
        var cached = cache.get(token);
        if (cached != null) return cached;
        var parts = token.split("/");
        var vi = reference(parts[0], sourceV.length);
        if (vi < 0 || vi >= sourceV.length) return -1;
        var ni = (parts.length > 2 && parts[2] != "") ? reference(parts[2], sourceVN.length) : -1;
        var ti = (parts.length > 1 && parts[1] != "") ? reference(parts[1], sourceVT.length) : -1;

        var next = Std.int(positions.length / 3);
        var position = sourceV[vi];
        positions.push(position[0]);
        positions.push(position[1]);
        positions.push(position[2]);
        if (ni >= 0 && ni < sourceVN.length) {
            var normal = sourceVN[ni];
            normals.push(normal[0]);
            normals.push(normal[1]);
            normals.push(normal[2]);
        } else {
            normals.push(0);
            normals.push(0);
            normals.push(0);
        }
        if (ti >= 0 && ti < sourceVT.length) {
            var uv = sourceVT[ti];
            uvs.push(uv[0]);
            uvs.push(uv[1]);
        } else {
            uvs.push(0);
            uvs.push(0);
        }
        cache.set(token, next);
        return next;
    }

    /** OBJ indices are 1-based; negative values count from the end. */
    static function reference(value:String, length:Int):Int {
        var parsed = Std.parseInt(value);
        if (parsed == null) return -1;
        return parsed < 0 ? length + parsed : parsed - 1;
    }
}
