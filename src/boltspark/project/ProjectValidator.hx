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

    public static function validateMaterial(material:MaterialDocument):Void {
        StableId.require(material.id, "material.id");
        requireName(material.name, "material.name");
        if (!Math.isFinite(material.specularAmount)
                || material.specularAmount < 0 || material.specularAmount > 1) {
            throw 'Material ${material.id} has invalid specular amount';
        }
        if (!Math.isFinite(material.specularPower) || material.specularPower < 0) {
            throw 'Material ${material.id} has invalid specular power';
        }
        if (material.albedoTexture != null && material.albedoTexture.length > 0) {
            material.albedoTexture = ProjectPath.normalizeRelative(material.albedoTexture);
        }
    }

    public static function validateScene(scene:SceneDocument):Void {
        StableId.require(scene.id, "scene.id");
        requireName(scene.name, "scene.name");
        var ids:Map<String, Bool> = [];
        var entitiesById:Map<String, SceneEntityData> = [];
        for (entity in scene.entities) {
            StableId.require(entity.id, "entity.id");
            if (ids.exists(entity.id)) throw 'Duplicate entity ID ${entity.id}';
            ids.set(entity.id, true);
            entitiesById.set(entity.id, entity);
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
            }
        }
        assertNoParentCycles(scene.entities, entitiesById);
    }

    /** Linear-time, iterative cycle validation for very deep scene files. */
    static function assertNoParentCycles(entities:Array<SceneEntityData>,
            byId:Map<String, SceneEntityData>):Void {
        // 1 = visiting the current chain, 2 = fully validated.
        var state:Map<String, Int> = [];
        for (start in entities) {
            if (state.get(start.id) == 2) continue;
            var path:Array<SceneEntityData> = [];
            var current:Null<SceneEntityData> = start;
            while (current != null) {
                var currentState = state.exists(current.id) ? state.get(current.id) : 0;
                if (currentState == 1) {
                    throw 'Parent cycle contains entity ${current.id}';
                }
                if (currentState == 2) break;
                state.set(current.id, 1);
                path.push(current);
                current = current.parentId == null ? null : byId.get(current.parentId);
            }
            for (entry in path) state.set(entry.id, 2);
        }
    }

    static function validateTransform(transform:TransformData, id:String):Void {
        if (transform == null) throw 'Entity ${id} has no transform';
        for (value in [transform.positionX, transform.positionY, transform.positionZ,
                transform.rotationX, transform.rotationY, transform.rotationZ,
                transform.scaleX, transform.scaleY, transform.scaleZ,
                transform.shearXY, transform.shearXZ, transform.shearYZ]) {
            if (value != value || value == Math.POSITIVE_INFINITY
                    || value == Math.NEGATIVE_INFINITY) {
                throw 'Entity ${id} transform contains a non-finite value';
            }
        }
        if (transform.scaleX == 0 || transform.scaleY == 0 || transform.scaleZ == 0) {
            throw 'Entity ${id} transform contains singular zero scale';
        }
        if (transform.quaternionValid) {
            var maxQuaternion = 0.0;
            for (value in [transform.quaternionX, transform.quaternionY,
                    transform.quaternionZ, transform.quaternionW]) {
                if (!Math.isFinite(value)) {
                    throw 'Entity ${id} quaternion contains a non-finite value';
                }
                maxQuaternion = Math.max(maxQuaternion, Math.abs(value));
            }
            if (maxQuaternion <= 0.000000000001) {
                throw 'Entity ${id} quaternion has zero length';
            }
        }
    }

    static function requireName(value:String, context:String):Void {
        if (value == null || StringTools.trim(value).length == 0) {
            throw '${context} cannot be empty';
        }
    }
}
