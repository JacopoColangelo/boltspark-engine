package boltspark.assets;

import haxe.io.Bytes;
import haxe.io.Path;

/**
 * Compact glTF reader for the first imported mesh primitive. Supports JSON
 * `.gltf` with embedded base64 or sibling buffers, and binary `.glb` chunks.
 * Animation, skinning, materials, and multiple primitives are out of scope.
 */
class GltfParser {
    public static function parse(path:String, name:String = ""):MeshGeometry {
        var bytes = sys.io.File.getBytes(path);
        var isGlb = StringTools.endsWith(path.toLowerCase(), ".glb");
        var jsonText:String = null;
        var binary:Bytes = null;
        if (isGlb) {
            if (bytes.length < 20 || word(bytes, 0) != 0x46546C67) {
                throw 'Invalid GLB header: ${path}';
            }
            var offset = 12;
            while (offset + 8 <= bytes.length) {
                var length = word(bytes, offset);
                var type = word(bytes, offset + 4);
                var start = offset + 8;
                if (type == 0x4E4F534A) {
                    jsonText = bytes.getString(start, length);
                } else if (type == 0x004E4942) {
                    binary = bytes.sub(start, length);
                }
                offset = start + length;
            }
            if (jsonText == null) throw 'GLB has no JSON chunk: ${path}';
        } else {
            jsonText = bytes.toString();
        }

        var root:Dynamic;
        try {
            root = haxe.Json.parse(jsonText);
        } catch (e:Dynamic) {
            throw 'glTF JSON could not be parsed: ${Std.string(e)}';
        }
        var buffers:Array<Dynamic> = root.buffers;
        var bufferViews:Array<Dynamic> = root.bufferViews;
        var accessors:Array<Dynamic> = root.accessors;
        var meshes:Array<Dynamic> = root.meshes;
        if (meshes == null || meshes.length == 0) throw 'glTF has no meshes: ${path}';
        var primitives:Array<Dynamic> = meshes[0].primitives;
        if (primitives == null || primitives.length == 0) throw 'glTF mesh has no primitives: ${path}';
        var primitive = primitives[0];
        if (Reflect.hasField(primitive, "mode") && primitive.mode != 4) {
            throw 'Only TRIANGLES glTF primitives are supported: ${path}';
        }

        var attributes:Dynamic = primitive.attributes;
        var positionAccessor = readAccessor(accessors, bufferViews, buffers,
            attributes.POSITION, path, binary);
        var positions = positionAccessor.values;
        var normals = attributes.NORMAL == null
            ? zeroFilled(positions.length, 3)
            : readAccessor(accessors, bufferViews, buffers, attributes.NORMAL, path, binary).values;
        var uvs = attributes.TEXCOORD_0 == null
            ? zeroFilled(Std.int(positions.length / 3), 2)
            : readAccessor(accessors, bufferViews, buffers, attributes.TEXCOORD_0, path, binary).values;
        var indices = primitive.indices == null
            ? sequentialIndices(Std.int(positions.length / 3))
            : [for (value in readAccessor(accessors, bufferViews, buffers,
                primitive.indices, path, binary).values) Std.int(value)];
        for (index in indices) {
            if (index < 0 || index >= Std.int(positions.length / 3)) {
                throw 'glTF index out of range: ${path}';
            }
        }
        var displayName = name != "" ? name
            : (root.meshes[0].name != null ? root.meshes[0].name : "Imported Mesh");
        return {
            name: displayName,
            positions: positions,
            normals: normals,
            uvs: uvs,
            indices: indices
        };
    }

    static function readAccessor(accessors:Array<Dynamic>,
            bufferViews:Array<Dynamic>, buffers:Array<Dynamic>, accessorIndex:Dynamic,
            path:String, glbBinary:Bytes):{ values:Array<Float>, components:Int } {
        if (accessorIndex == null) throw 'Missing glTF accessor: ${path}';
        var accessor = accessors[Std.int(accessorIndex)];
        var view = bufferViews[Std.int(accessor.bufferView)];
        var components = switch (accessor.type) {
            case "SCALAR": 1;
            case "VEC2": 2;
            case "VEC3": 3;
            case "VEC4": 4;
            default: throw 'Unsupported glTF accessor type ${accessor.type}';
        };
        var componentSize = switch (accessor.componentType) {
            case 5126: 4; // FLOAT
            case 5123: 2; // UNSIGNED_SHORT
            case 5125: 4; // UNSIGNED_INT
            case 5121: 1; // UNSIGNED_BYTE
            default: throw 'Unsupported glTF component type ${accessor.componentType}';
        };
        var data = bufferBytes(buffers[Std.int(view.buffer)], path, glbBinary);
        var start = (view.byteOffset == null ? 0 : Std.int(view.byteOffset))
            + (accessor.byteOffset == null ? 0 : Std.int(accessor.byteOffset));
        var stride = view.byteStride == null ? components * componentSize : Std.int(view.byteStride);
        var count = Std.int(accessor.count);
        var result:Array<Float> = [];
        for (element in 0...count) {
            var base = start + element * stride;
            for (component in 0...components) {
                result.push(readComponent(data, base + component * componentSize,
                    Std.int(accessor.componentType)));
            }
        }
        return { values: result, components: components };
    }

    static function bufferBytes(buffer:Dynamic, path:String, glbBinary:Bytes):Bytes {
        if (buffer.uri == null) {
            if (glbBinary == null) throw 'glTF buffer has no data: ${path}';
            return glbBinary;
        }
        var uri:String = buffer.uri;
        if (StringTools.startsWith(uri, "data:")) {
            var comma = uri.indexOf(",");
            if (comma < 0) throw 'Invalid glTF data URI: ${path}';
            return haxe.crypto.Base64.decode(uri.substr(comma + 1));
        }
        var directory = new Path(path).dir;
        var resolved = directory == "" ? uri : Path.join([directory, uri]);
        return sys.io.File.getBytes(resolved);
    }

    static function readComponent(bytes:Bytes, offset:Int, componentType:Int):Float {
        return switch (componentType) {
            case 5126: float32(bytes, offset);
            case 5123: bytes.get(offset) | (bytes.get(offset + 1) << 8);
            case 5125: rawWord(bytes, offset);
            case 5121: bytes.get(offset);
            default: 0;
        };
    }

    /** Chunk magic numbers are ASCII, so the sign bit can be masked away. */
    static function word(bytes:Bytes, offset:Int):Int {
        return rawWord(bytes, offset) & 0x7FFFFFFF;
    }

    static function rawWord(bytes:Bytes, offset:Int):Int {
        return bytes.get(offset)
            | (bytes.get(offset + 1) << 8)
            | (bytes.get(offset + 2) << 16)
            | (bytes.get(offset + 3) << 24);
    }

    /** IEEE-754 single precision decode; Haxe stdlib has no bit-reinterpret helper. */
    static function float32(bytes:Bytes, offset:Int):Float {
        var bits = rawWord(bytes, offset);
        var negative = (bits & 0x80000000) != 0;
        var exponent = (bits >>> 23) & 0xFF;
        var mantissa = bits & 0x7FFFFF;
        if (exponent == 0) {
            var subnormal = Math.pow(2, -126) * (mantissa / 8388608.0);
            return negative ? -subnormal : subnormal;
        }
        if (exponent == 255) {
            if (mantissa != 0) return Math.NaN;
            return negative ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
        }
        var value = Math.pow(2, exponent - 127) * (1 + mantissa / 8388608.0);
        return negative ? -value : value;
    }

    static function zeroFilled(count:Int, components:Int):Array<Float> {
        var result:Array<Float> = [];
        for (_ in 0...count * components) result.push(0);
        return result;
    }

    static function sequentialIndices(vertexCount:Int):Array<Int> {
        var result:Array<Int> = [];
        for (index in 0...vertexCount) result.push(index);
        return result;
    }
}
