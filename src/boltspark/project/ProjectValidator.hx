package boltspark.project;

class ProjectValidator {
    public static function validateProject(project:ProjectDocument):Void {
        StableId.require(project.id, "project.id");
        requireName(project.name, "project.name");
        var ids:Map<String, Bool> = [];
        for (asset in project.assets) {
            StableId.require(asset.id, "asset.id");
            if (ids.exists(asset.id)) throw 'Duplicate asset ID ${asset.id}';
            ids.set(asset.id, true);
            requireName(asset.type, "asset.type");
            asset.source = ProjectPath.normalizeRelative(asset.source);
            if (asset.importSettings == null || !Reflect.isObject(asset.importSettings)) {
                throw 'Import settings for asset ${asset.id} must be an object';
            }
        }
        if (project.defaultSceneId != null) {
            StableId.require(project.defaultSceneId, "project.defaultSceneId");
            var found = false;
            for (asset in project.assets) {
                if (asset.id == project.defaultSceneId && asset.type == "scene") found = true;
            }
            if (!found) throw 'Default scene ${project.defaultSceneId} is not a scene asset';
        }
    }

    public static function validateScene(scene:SceneDocument):Void {
        StableId.require(scene.id, "scene.id");
        requireName(scene.name, "scene.name");
        var ids:Map<String, Bool> = [];
        for (entity in scene.entities) {
            StableId.require(entity.id, "entity.id");
            if (ids.exists(entity.id)) throw 'Duplicate entity ID ${entity.id}';
            ids.set(entity.id, true);
            requireName(entity.name, "entity.name");
            validateTransform(entity.transform, entity.id);
            for (component in entity.components) {
                requireName(component.type, "component.type");
                if (component.version < 1) throw 'Component ${component.type} has invalid version';
                if (component.data == null || !Reflect.isObject(component.data)) {
                    throw 'Component ${component.type} data must be an object';
                }
            }
        }
        for (entity in scene.entities) {
            if (entity.parentId != null) {
                StableId.require(entity.parentId, "entity.parentId");
                if (entity.parentId == entity.id) throw 'Entity ${entity.id} cannot parent itself';
                if (!ids.exists(entity.parentId)) {
                    throw 'Entity ${entity.id} references missing parent ${entity.parentId}';
                }
                assertNoParentCycle(entity, scene.entities);
            }
        }
    }

    static function assertNoParentCycle(start:SceneEntityData,
            entities:Array<SceneEntityData>):Void {
        var visited:Map<String, Bool> = [];
        var current:Null<SceneEntityData> = start;
        while (current != null && current.parentId != null) {
            if (visited.exists(current.id)) throw 'Parent cycle contains entity ${current.id}';
            visited.set(current.id, true);
            current = findEntity(entities, current.parentId);
        }
    }

    static function findEntity(entities:Array<SceneEntityData>, id:String):Null<SceneEntityData> {
        for (entity in entities) if (entity.id == id) return entity;
        return null;
    }

    static function validateTransform(transform:TransformData, id:String):Void {
        if (transform == null) throw 'Entity ${id} has no transform';
        for (value in [transform.positionX, transform.positionY, transform.positionZ,
                transform.rotationX, transform.rotationY, transform.rotationZ,
                transform.scaleX, transform.scaleY, transform.scaleZ]) {
            if (value != value || value == Math.POSITIVE_INFINITY
                    || value == Math.NEGATIVE_INFINITY) {
                throw 'Entity ${id} transform contains a non-finite value';
            }
        }
        if (transform.scaleX == 0 || transform.scaleY == 0 || transform.scaleZ == 0) {
            throw 'Entity ${id} transform contains singular zero scale';
        }
    }

    static function requireName(value:String, context:String):Void {
        if (value == null || StringTools.trim(value).length == 0) {
            throw '${context} cannot be empty';
        }
    }
}
