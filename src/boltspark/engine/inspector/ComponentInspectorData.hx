package boltspark.engine.inspector;

/** One Inspector section projected from an attached Component. */
class ComponentInspectorData {
    public final componentIndex:Int;
    public final typeId:String;
    public final title:String;
    public final properties:Array<ComponentPropertyData>;
    public final removable:Bool;

    public function new(componentIndex:Int, typeId:String, title:String,
            ?properties:Array<ComponentPropertyData>, removable:Bool = true) {
        this.componentIndex = componentIndex;
        this.typeId = typeId;
        this.title = title;
        this.properties = properties == null ? [] : properties;
        this.removable = removable;
    }
}
