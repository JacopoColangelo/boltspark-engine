package boltspark.project;

class SceneEntityData {
    public var id:String;
    public var name:String;
    public var parentId:Null<String>;
    public var transform:TransformData;
    public final components:Array<ComponentData>;
    public var extraFields:Dynamic;

    public function new(id:String, name:String, ?parentId:String,
            ?transform:TransformData, ?components:Array<ComponentData>,
            ?extraFields:Dynamic) {
        this.id = id;
        this.name = name;
        this.parentId = parentId;
        this.transform = transform == null ? new TransformData() : transform;
        this.components = components == null ? [] : components;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
