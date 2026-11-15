package boltspark.engine;

import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.project.ComponentData;

/** Generic geometry renderer; it has no knowledge of cubes or other shapes. */
class MeshRenderer extends Component {
    public static inline var TYPE_ID:String = "meshRenderer";
    public static inline var VERSION:Int = 1;

    public var mesh(get, set):Null<Mesh>;
    public var material(get, set):Material;

    var meshValue:Null<Mesh>;
    var materialValue:Material;
    var componentExtraFields:Dynamic;
    var dataTemplate:Dynamic;

    public function new(?mesh:Mesh, ?material:Material,
            ?dataTemplate:Dynamic, ?componentExtraFields:Dynamic) {
        super();
        meshValue = mesh;
        materialValue = material == null ? Material.defaultMaterial() : material;
        this.dataTemplate = Component.copyData(dataTemplate);
        this.componentExtraFields = Component.copyData(componentExtraFields);
    }

    override function get_typeId():String return TYPE_ID;
    override function get_displayName():String return "MeshRenderer";

    public function cullingForScale(mirrored:Bool):MaterialCulling {
        if (!mirrored) return materialValue.culling;
        return switch (materialValue.culling) {
            case Back: Front;
            case Front: Back;
            case None: None;
            case Both: Both;
        };
    }

    override public function cloneComponent():Component {
        return new MeshRenderer(meshValue, materialValue,
            dataTemplate, componentExtraFields);
    }

    override public function inspectorData(componentIndex:Int):ComponentInspectorData {
        return new ComponentInspectorData(componentIndex, TYPE_ID,
            "MeshRenderer", [
                ComponentPropertyData.text("mesh", "Mesh",
                    meshValue == null ? "None" : meshValue.name),
                ComponentPropertyData.text("material", "Material",
                    materialValue.name)
            ]);
    }

    override public function toComponentData():Null<ComponentData> {
        var data = Component.copyData(dataTemplate);
        if (meshValue == null) {
            Reflect.deleteField(data, "primitive");
            Reflect.setField(data, "mesh", null);
        } else {
            Reflect.setField(data, "mesh", meshValue.id);
            if (meshValue.primitiveId != null) {
                // Preserve the schema-1 primitive field consumed by existing
                // scenes while also writing the generic mesh identity.
                Reflect.setField(data, "primitive", meshValue.primitiveId);
            } else {
                Reflect.deleteField(data, "primitive");
            }
        }
        Reflect.setField(data, "material", materialValue.id);
        return new ComponentData(TYPE_ID, VERSION, data,
            Component.copyData(componentExtraFields));
    }

    public static function fromComponentData(data:ComponentData):MeshRenderer {
        var mesh:Null<Mesh> = null;
        var meshId:Null<String> = null;
        if (Reflect.hasField(data.data, "mesh")) {
            var rawMesh = Reflect.field(data.data, "mesh");
            if (Std.isOfType(rawMesh, String)) meshId = rawMesh;
        }
        if (meshId == null && Reflect.hasField(data.data, "primitive")) {
            var rawPrimitive = Reflect.field(data.data, "primitive");
            if (Std.isOfType(rawPrimitive, String)) meshId = rawPrimitive;
        }
        if (meshId != null) mesh = PrimitiveMeshes.find(meshId);

        var material = Material.defaultMaterial();
        if (Reflect.hasField(data.data, "material")) {
            var rawMaterial = Reflect.field(data.data, "material");
            if (Std.isOfType(rawMaterial, String)) {
                var found = Material.find(rawMaterial);
                if (found != null) material = found;
            }
        }
        return new MeshRenderer(mesh, material, data.data, data.extraFields);
    }

    inline function get_mesh():Null<Mesh> return meshValue;
    function set_mesh(value:Null<Mesh>):Null<Mesh> {
        if (meshValue == value) return value;
        meshValue = value;
        changed();
        return value;
    }

    inline function get_material():Material return materialValue;
    function set_material(value:Material):Material {
        if (value == null) throw "MeshRenderer material cannot be null";
        if (materialValue == value) return value;
        materialValue = value;
        changed();
        return value;
    }
}
