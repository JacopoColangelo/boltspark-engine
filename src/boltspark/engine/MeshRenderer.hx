package boltspark.engine;

import boltspark.engine.inspector.AssetOption;
import boltspark.engine.inspector.AssetType;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.project.ComponentData;

/** Generic geometry renderer; it has no knowledge of cubes or other shapes. */
class MeshRenderer extends Component {
    public static inline var TYPE_ID:String = "meshRenderer";
    public static inline var VERSION:Int = 1;

    public var mesh(get, set):Null<Mesh>;
    public var material(get, set):Material;
    public var primitiveSettings(get, set):PrimitiveSettings;

    var meshValue:Null<Mesh>;
    var materialValue:Material;
    var settingsValue:PrimitiveSettings;
    var componentExtraFields:Dynamic;
    var dataTemplate:Dynamic;

    public function new(?mesh:Mesh, ?material:Material,
            ?dataTemplate:Dynamic, ?componentExtraFields:Dynamic,
            ?settings:PrimitiveSettings) {
        super();
        meshValue = mesh;
        materialValue = material == null ? Material.defaultMaterial() : material;
        settingsValue = settings == null
            ? PrimitiveMeshes.defaultSettings(mesh == null ? null : mesh.primitiveId)
            : settings.clone();
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
            dataTemplate, componentExtraFields, settingsValue);
    }

    override public function inspectorData(componentIndex:Int):ComponentInspectorData {
        var meshOptions = [AssetOption.none()];
        for (mesh in PrimitiveMeshes.all()) {
            meshOptions.push(new AssetOption(mesh.id, mesh.name));
        }
        var materialOptions = [for (material in Material.all())
            new AssetOption(material.id, material.name)];
        var properties = [
            ComponentPropertyData.asset("mesh", "Mesh", AssetType.MeshAsset,
                meshValue == null ? "" : meshValue.id,
                meshValue == null ? "None" : meshValue.name, meshOptions),
            ComponentPropertyData.asset("material", "Material", AssetType.MaterialAsset,
                materialValue.id, materialValue.name, materialOptions)
        ];
        // Geometry controls are generated from the primitive's own schema, so
        // MeshRenderer stays independent of any specific primitive type.
        if (meshValue != null) {
            for (parameter in PrimitiveMeshes.parameters(meshValue.primitiveId)) {
                switch (parameter.kind) {
                    case PrimitiveParameter.INTEGER:
                        properties.push(ComponentPropertyData.integer(parameter.id,
                            parameter.label, Std.int(settingNumber(parameter.id)),
                            Std.int(parameter.min), Std.int(parameter.max), true));
                    case PrimitiveParameter.BOOLEAN:
                        properties.push(ComponentPropertyData.boolean(parameter.id,
                            parameter.label, settingBool(parameter.id), true));
                    default:
                        properties.push(ComponentPropertyData.number(parameter.id,
                            parameter.label, settingNumber(parameter.id),
                            parameter.min, parameter.max, parameter.step, true));
                }
            }
        }
        return new ComponentInspectorData(componentIndex, TYPE_ID,
            "MeshRenderer", properties);
    }

    function settingNumber(id:String):Float {
        return switch (id) {
            case "segments": settingsValue.segments;
            case "rings": settingsValue.rings;
            case "radius": settingsValue.radius;
            case "height": settingsValue.height;
            case "width": settingsValue.width;
            case "depth": settingsValue.depth;
            default: 0;
        };
    }

    function settingBool(id:String):Bool {
        return id == "capped" && settingsValue.capped;
    }

    /**
     * Assign a shared asset reference by id. Unknown ids are ignored so a
     * future asset type cannot silently wipe an existing assignment.
     */
    override public function setInspectorAsset(propertyId:String,
            assetId:String):Bool {
        switch (propertyId) {
            case "mesh":
                var next:Null<Mesh> = null;
                if (assetId != null && assetId.length > 0) {
                    next = PrimitiveMeshes.find(assetId);
                    if (next == null) return false;
                }
                mesh = next;
                return true;
            case "material":
                var next = assetId == null || assetId.length == 0
                    ? Material.defaultMaterial() : Material.find(assetId);
                // An unknown/material-less reference falls back to Default.
                material = next == null ? Material.defaultMaterial() : next;
                return true;
            default:
                return false;
        }
    }

    override public function setInspectorNumber(propertyId:String, axis:Int,
            value:Float):Bool {
        if (meshValue == null || !Math.isFinite(value)) return false;
        var parameter = findParameter(propertyId);
        if (parameter == null || parameter.kind == PrimitiveParameter.BOOLEAN) return false;
        if (value < parameter.min || value > parameter.max) return false;
        switch (propertyId) {
            case "segments": settingsValue.segments = Std.int(value);
            case "rings": settingsValue.rings = Std.int(value);
            case "radius": settingsValue.radius = value;
            case "height": settingsValue.height = value;
            case "width": settingsValue.width = value;
            case "depth": settingsValue.depth = value;
            default: return false;
        }
        changed();
        return true;
    }

    override public function setInspectorBool(propertyId:String,
            value:Bool):Bool {
        if (propertyId != "capped" || settingsValue.capped == value) return false;
        settingsValue.capped = value;
        changed();
        return true;
    }

    /** Restore one geometry parameter to its primitive's default value. */
    override public function resetInspectorProperty(propertyId:String):Bool {
        if (meshValue == null) return false;
        if (findParameter(propertyId) == null) return false;
        var defaults = PrimitiveMeshes.defaultSettings(meshValue.primitiveId);
        switch (propertyId) {
            case "segments": settingsValue.segments = defaults.segments;
            case "rings": settingsValue.rings = defaults.rings;
            case "radius": settingsValue.radius = defaults.radius;
            case "height": settingsValue.height = defaults.height;
            case "width": settingsValue.width = defaults.width;
            case "depth": settingsValue.depth = defaults.depth;
            case "capped": settingsValue.capped = defaults.capped;
            default: return false;
        }
        changed();
        return true;
    }

    /** True when `id` is a geometry parameter of the assigned primitive. */
    public function isPrimitiveParameter(id:String):Bool {
        return findParameter(id) != null;
    }

    /** Display label for a geometry parameter; falls back to the raw id. */
    public function parameterLabel(id:String):String {
        var parameter = findParameter(id);
        return parameter == null ? id : parameter.label;
    }

    function findParameter(id:String):Null<PrimitiveParameter> {
        if (meshValue == null) return null;
        for (parameter in PrimitiveMeshes.parameters(meshValue.primitiveId)) {
            if (parameter.id == id) return parameter;
        }
        return null;
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
        if (meshValue != null) {
            Reflect.setField(data, "primitiveSettings", settingsValue.toData());
        } else {
            Reflect.deleteField(data, "primitiveSettings");
        }
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

        var settings = mesh == null ? null
            : PrimitiveMeshes.defaultSettings(mesh.primitiveId);
        if (settings != null && Reflect.hasField(data.data, "primitiveSettings")) {
            settings = PrimitiveSettings.fromData(
                Reflect.field(data.data, "primitiveSettings"));
        }

        var material = Material.defaultMaterial();
        if (Reflect.hasField(data.data, "material")) {
            var rawMaterial = Reflect.field(data.data, "material");
            if (Std.isOfType(rawMaterial, String)) {
                var found = Material.find(rawMaterial);
                if (found != null) material = found;
            }
        }
        return new MeshRenderer(mesh, material, data.data, data.extraFields, settings);
    }

    inline function get_mesh():Null<Mesh> return meshValue;
    function set_mesh(value:Null<Mesh>):Null<Mesh> {
        if (meshValue == value) return value;
        var previousPrimitive = meshValue == null ? null : meshValue.primitiveId;
        var nextPrimitive = value == null ? null : value.primitiveId;
        meshValue = value;
        if (previousPrimitive != nextPrimitive) {
            settingsValue = PrimitiveMeshes.defaultSettings(nextPrimitive);
        }
        changed();
        return value;
    }

    inline function get_primitiveSettings():PrimitiveSettings return settingsValue;
    function set_primitiveSettings(value:PrimitiveSettings):PrimitiveSettings {
        if (value == null || settingsValue.sameAs(value)) return settingsValue;
        settingsValue = value.clone();
        changed();
        return settingsValue;
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
