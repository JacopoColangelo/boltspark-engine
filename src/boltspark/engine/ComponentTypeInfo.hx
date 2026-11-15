package boltspark.engine;

/** Add-Component menu entry published by ComponentRegistry. */
class ComponentTypeInfo {
    public final typeId:String;
    public final label:String;

    public function new(typeId:String, label:String) {
        this.typeId = typeId;
        this.label = label;
    }
}
