package boltspark.engine;

import boltspark.project.ComponentData;

private typedef ComponentRegistration = {
    final label:String;
    final addable:Bool;
    final create:Void->Component;
    final decode:ComponentData->Component;
}

/** Extensible component factory used by scene loading and Add Component. */
class ComponentRegistry {
    static final registrations:Map<String, ComponentRegistration> = [];
    static final registrationOrder:Array<String> = [];
    static var initialized:Bool = initializeBuiltIns();

    public static function register(typeId:String, label:String,
            create:Void->Component, decode:ComponentData->Component,
            addable:Bool = true):Void {
        if (typeId == null || StringTools.trim(typeId).length == 0) {
            throw "Component type ID cannot be empty";
        }
        if (registrations.exists(typeId)) {
            throw 'Component type ${typeId} is already registered';
        }
        registrations.set(typeId, {
            label: label,
            addable: addable,
            create: create,
            decode: decode
        });
        registrationOrder.push(typeId);
    }

    public static function create(typeId:String):Component {
        ensureInitialized();
        var registration = registrations.get(typeId);
        if (registration == null) throw 'Unknown component type: ${typeId}';
        return registration.create();
    }

    public static function deserialize(data:ComponentData):Component {
        ensureInitialized();
        var registration = registrations.get(data.type);
        return registration == null
            ? new UnknownComponent(data)
            : registration.decode(data);
    }

    public static function serialize(component:Component):Null<ComponentData> {
        return component == null ? null : component.toComponentData();
    }

    public static function addableTypes():Array<ComponentTypeInfo> {
        ensureInitialized();
        var result:Array<ComponentTypeInfo> = [];
        for (typeId in registrationOrder) {
            var registration = registrations.get(typeId);
            if (registration.addable) {
                result.push(new ComponentTypeInfo(typeId, registration.label));
            }
        }
        return result;
    }

    static function initializeBuiltIns():Bool {
        register(MeshRenderer.TYPE_ID, "Mesh Renderer",
            function() return new MeshRenderer(),
            MeshRenderer.fromComponentData);
        return true;
    }

    static inline function ensureInitialized():Void {
        if (!initialized) throw "Component registry initialization failed";
    }
}
