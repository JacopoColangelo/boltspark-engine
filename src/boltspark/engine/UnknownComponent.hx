package boltspark.engine;

import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.project.ComponentData;

/** Opaque forward-compatible component retained when its type is unavailable. */
class UnknownComponent extends Component {
    final source:ComponentData;

    public function new(source:ComponentData) {
        super();
        if (source == null) throw "UnknownComponent requires serialized data";
        this.source = copyComponentData(source);
    }

    override function get_typeId():String return source.type;
    override function get_displayName():String return source.type;

    override public function cloneComponent():Component {
        return new UnknownComponent(source);
    }

    override public function inspectorData(componentIndex:Int):ComponentInspectorData {
        return new ComponentInspectorData(componentIndex, source.type,
            source.type, [ComponentPropertyData.text("status", "Status",
                "Unsupported component (data preserved)")]);
    }

    override public function toComponentData():Null<ComponentData> {
        return copyComponentData(source);
    }

    static function copyComponentData(value:ComponentData):ComponentData {
        return new ComponentData(value.type, value.version,
            Component.copyData(value.data), Component.copyData(value.extraFields));
    }
}
