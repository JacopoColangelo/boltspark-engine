import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.editor.HeapsMeshFactory;
import boltspark.editor.SceneObject;
import boltspark.engine.Material;
import boltspark.engine.Mesh;
import boltspark.engine.MeshRenderer;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.inspector.AssetType;
import boltspark.engine.inspector.ComponentPropertyKind;
import boltspark.engine.inspector.ComponentPropertyData;

/**
 * Headless coverage for reusable mesh/material assets, type-aware Inspector
 * data, and per-entity renderer instances that share asset geometry only.
 */
class MeshRendererAssetRepro {
    static function main():Void {
        testCatalogs();
        testInspectorAssetProperties();
        testPrimitiveSettings();
        testPrimitiveSettingsHistory();
        testAssignmentAndFallback();
        testSharedAssetsDistinctInstances();
        Sys.println("[mesh-renderer-assets] primitive/material catalogs, asset "
            + "pickers, primitive settings, history, fallback, and shared-asset "
            + "render instances passed");
    }

    static function testCatalogs():Void {
        var meshes = PrimitiveMeshes.all();
        assertTrue(meshes.length >= 5, "built-in primitive catalog is incomplete");
        var ids = new Map<String, Bool>();
        for (mesh in meshes) {
            assertTrue(!ids.exists(mesh.id), 'duplicate mesh asset id ${mesh.id}');
            ids.set(mesh.id, true);
            assertTrue(PrimitiveMeshes.find(mesh.id) == mesh,
                'mesh asset ${mesh.id} did not resolve to the shared instance');
            // Every catalog asset must have a registered Heaps primitive.
            assertTrue(HeapsMeshFactory.resolve(mesh) != null,
                'no Heaps primitive registered for ${mesh.id}');
        }
        assertTrue(HeapsMeshFactory.resolve(PrimitiveMeshes.cube())
            == HeapsMeshFactory.resolve(PrimitiveMeshes.cube()),
            "primitive geometry was not cached per asset");

        // Future imported static meshes can join the same catalog/reference
        // model without touching MeshRenderer or the picker.
        var futureMesh = new Mesh("imported:test", "Imported Mesh");
        PrimitiveMeshes.register(futureMesh);
        assertTrue(PrimitiveMeshes.find(futureMesh.id) == futureMesh,
            "registered imported mesh was not resolvable by asset id");
        var hasFuture = false;
        for (mesh in PrimitiveMeshes.all()) {
            if (mesh == futureMesh) hasFuture = true;
        }
        assertTrue(hasFuture, "registered imported mesh missing from picker catalog");

        var defaultMaterial = Material.defaultMaterial();
        assertTrue(Material.find(Material.DEFAULT_ID) == defaultMaterial,
            "default material did not resolve");
        var found = false;
        for (material in Material.all()) {
            if (material == defaultMaterial) found = true;
        }
        assertTrue(found, "default material missing from catalog");
    }

    static function testInspectorAssetProperties():Void {
        var renderer:MeshRenderer = PrimitiveGameObjects.createCubeRenderer();
        var data = renderer.inspectorData(1);
        // Two asset rows plus one row per cube geometry parameter.
        assertTrue(data.properties.length == 5,
            "expected mesh, material, and cube geometry properties");
        var meshProperty = property(data.properties, "mesh");
        var materialProperty = property(data.properties, "material");
        assertTrue(meshProperty != null && materialProperty != null,
            "asset properties were not published");
        assertTrue(meshProperty.kind == ComponentPropertyKind.Asset
            && materialProperty.kind == ComponentPropertyKind.Asset,
            "mesh/material rows must be asset pickers");
        assertTrue(meshProperty.assetType == AssetType.MeshAsset
            && materialProperty.assetType == AssetType.MaterialAsset,
            "asset properties lost their type-aware identity");
        assertTrue(meshProperty.textValue == "Primitive Cube"
            && materialProperty.textValue == "Default Material",
            "asset labels did not carry the current value");
        assertTrue(hasOption(meshProperty, "") && hasOption(meshProperty, PrimitiveMeshes.CUBE_ID)
            && hasOption(meshProperty, PrimitiveMeshes.SPHERE_ID),
            "mesh picker options are missing None or built-in primitives");
        assertTrue(hasOption(materialProperty, Material.DEFAULT_ID),
            "material picker is missing the Default Material");

        // Geometry rows come from the primitive's own schema; MeshRenderer
        // never hardcodes which primitive it is drawing.
        var widthProperty = property(data.properties, "width");
        var heightProperty = property(data.properties, "height");
        var depthProperty = property(data.properties, "depth");
        assertTrue(widthProperty != null && heightProperty != null
            && depthProperty != null
            && widthProperty.kind == ComponentPropertyKind.Number
            && widthProperty.numberValues[0] == 1
            && widthProperty.numberMin == 0.01 && widthProperty.numberMax == 16,
            "cube geometry parameters were not published from the schema");
    }

    static function testPrimitiveSettings():Void {
        var sphere = new MeshRenderer(PrimitiveMeshes.sphere());
        assertTrue(sphere.primitiveSettings.segments == 16
            && sphere.primitiveSettings.rings == 12,
            "sphere default settings were not derived from the catalog");

        assertTrue(sphere.setInspectorNumber("segments", 0, 8),
            "sphere segments edit failed");
        assertTrue(sphere.setInspectorNumber("radius", 0, 0.75),
            "sphere radius edit failed");
        assertTrue(sphere.primitiveSettings.segments == 8
            && sphere.primitiveSettings.radius == 0.75,
            "sphere settings edits were not applied");
        assertTrue(!sphere.setInspectorNumber("capped", 0, 1),
            "non-numeric parameter accepted a number edit");
        assertTrue(!sphere.setInspectorNumber("segments", 0, 500),
            "parameter edits ignored the schema range");

        var cylinder = new MeshRenderer(PrimitiveMeshes.cylinder());
        assertTrue(cylinder.primitiveSettings.capped,
            "cylinder should be capped by default");
        assertTrue(cylinder.setInspectorBool("capped", false),
            "cylinder capped toggle failed");
        assertTrue(!cylinder.primitiveSettings.capped,
            "cylinder capped state did not update");
        assertTrue(!cylinder.setInspectorBool("capped", false),
            "redundant capped toggle should report no change");

        // Geometry is cached per settings signature: identical settings share
        // one primitive; different settings build new geometry.
        var tallCylinder = new MeshRenderer(PrimitiveMeshes.cylinder());
        tallCylinder.setInspectorNumber("height", 0, 2);
        var defaults = PrimitiveMeshes.defaultSettings(PrimitiveMeshes.CYLINDER_ID);
        assertTrue(HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(), defaults)
            == HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(), defaults),
            "identical settings did not share cached geometry");
        assertTrue(HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(),
                cylinder.primitiveSettings)
            != HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(), defaults),
            "hollow cylinder did not produce distinct geometry");
        assertTrue(HeapsMeshFactory.resolve(tallCylinder.mesh,
                tallCylinder.primitiveSettings)
            != HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(), defaults),
            "taller cylinder did not produce distinct geometry");

        // Cap triangles must wind outward: cross((P1-P0),(P2-P0)) agrees with
        // the cap normal (+Y top, -Y bottom). Inverted caps are backface-culled
        // and make the "Capped" toggle look broken even though it changes data.
        var capped = HeapsMeshFactory.resolve(PrimitiveMeshes.cylinder(), defaults);
        var polygon = Std.isOfType(capped, h3d.prim.Polygon)
            ? cast(capped, h3d.prim.Polygon) : null;
        assertTrue(polygon != null && polygon.idx != null
            && polygon.normals != null,
            "cylinder geometry is not a normal-indexed polygon");
        var topWinding = 0.0;
        var bottomWinding = 0.0;
        var index = 0;
        var indices = polygon.idx;
        while (index + 2 < indices.length) {
            var a = indices[index];
            var b = indices[index + 1];
            var c = indices[index + 2];
            var na = polygon.normals[a];
            var nb = polygon.normals[b];
            var nc = polygon.normals[c];
            if (na.y == 1 && nb.y == 1 && nc.y == 1 && topWinding == 0) {
                var pa = polygon.points[a];
                var pb = polygon.points[b];
                var pc = polygon.points[c];
                topWinding = (pb.x - pa.x) * (pc.z - pa.z)
                    - (pb.z - pa.z) * (pc.x - pa.x);
            }
            if (na.y == -1 && nb.y == -1 && nc.y == -1 && bottomWinding == 0) {
                var pa = polygon.points[a];
                var pb = polygon.points[b];
                var pc = polygon.points[c];
                bottomWinding = (pb.x - pa.x) * (pc.z - pa.z)
                    - (pb.z - pa.z) * (pc.x - pa.x);
            }
            index += 3;
        }
        assertTrue(topWinding < 0,
            "top cap triangles face away from their normal");
        assertTrue(bottomWinding > 0,
            "bottom cap triangles face away from their normal");

        // Settings live on the renderer instance, so cloning carries them
        // without aliasing the value object.
        var clone = cast(cylinder.cloneComponent(), MeshRenderer);
        assertTrue(clone.primitiveSettings.sameAs(cylinder.primitiveSettings)
            && clone.primitiveSettings != cylinder.primitiveSettings,
            "clone did not copy the primitive settings value");
        clone.setInspectorBool("capped", true);
        assertTrue(!cylinder.primitiveSettings.capped,
            "clone settings aliased the original renderer");

        // Serialization round-trips the settings block.
        var data = cylinder.toComponentData();
        var restored = MeshRenderer.fromComponentData(data);
        assertTrue(restored.primitiveSettings.sameAs(cylinder.primitiveSettings)
            && !restored.primitiveSettings.capped,
            "primitive settings did not survive serialization");

        // Switching mesh assets resets settings to that primitive's defaults.
        assertTrue(sphere.setInspectorAsset("mesh", PrimitiveMeshes.CUBE_ID),
            "mesh asset change failed");
        assertTrue(sphere.primitiveSettings.width == 1
            && sphere.primitiveSettings.segments == 16,
            "mesh asset change did not reset geometry settings");
    }

    /**
     * Primitive settings participate in undo/redo: committed edits, per-row
     * resets, and multi-object composite gestures each restore exact state.
     */
    static function testPrimitiveSettingsHistory():Void {
        var session = new EditorSession(8);
        var object = session.addInitialObject("Cube", new EditorTransform(),
            null, [PrimitiveGameObjects.createCubeRenderer()]);
        var renderer = object.getComponent(MeshRenderer);

        // A committed settings edit round-trips through undo and redo.
        var before = renderer.primitiveSettings.clone();
        renderer.setInspectorNumber("width", 0, 2);
        assertTrue(session.commitPrimitiveSettings(object.id, before,
                renderer.primitiveSettings, "Edit Cube Width"),
            "settings edit was not committed to history");
        assertTrue(session.undo() && renderer.primitiveSettings.width == 1,
            "undo did not restore the previous settings");
        assertTrue(session.redo()
                && renderer.primitiveSettings.width == 2,
            "redo did not reapply the edited settings");

        // Identical before/after values must not create a history entry.
        assertTrue(!session.commitPrimitiveSettings(object.id,
                renderer.primitiveSettings, renderer.primitiveSettings,
                "no-op"),
            "no-change settings edit created a history entry");

        // Per-row reset restores the primitive default and is undoable.
        assertTrue(property(renderer.inspectorData(0).properties, "width").resettable,
            "primitive parameter row did not publish a reset action");
        assertTrue(!property(renderer.inspectorData(0).properties, "mesh").resettable,
            "asset rows must not publish a reset action");
        var beforeReset = renderer.primitiveSettings.clone();
        assertTrue(renderer.resetInspectorProperty("width"),
            "width reset failed");
        assertTrue(renderer.primitiveSettings.width == 1,
            "reset did not restore the default width");
        assertTrue(!renderer.resetInspectorProperty("mesh"),
            "resetting a non-parameter property should fail");
        assertTrue(session.commitPrimitiveSettings(object.id, beforeReset,
                renderer.primitiveSettings, "Reset Cube Width"),
            "reset was not committed to history");
        assertTrue(session.undo() && renderer.primitiveSettings.width == 2,
            "reset did not undo");

        // A multi-object gesture commits one composite entry.
        var other = session.createObject("Other", new EditorTransform(3, 0, 0),
            -1, [PrimitiveGameObjects.createCubeRenderer()]);
        var otherRenderer = other.getComponent(MeshRenderer);
        session.selectObjects([object.id, other.id], object.id);
        var ids = [object.id, other.id];
        var befores = [renderer.primitiveSettings.clone(),
            otherRenderer.primitiveSettings.clone()];
        renderer.setInspectorNumber("width", 0, 3);
        otherRenderer.setInspectorNumber("width", 0, 2);
        var afters = [renderer.primitiveSettings.clone(),
            otherRenderer.primitiveSettings.clone()];
        assertTrue(session.commitAppliedPrimitiveSettings(ids, befores, afters,
                "Edit Width on 2 objects"),
            "composite settings commit failed");
        assertTrue(session.undo(),
            "composite settings edit did not undo");
        assertTrue(renderer.primitiveSettings.width == 2
                && otherRenderer.primitiveSettings.width == 1,
            "composite undo did not restore every object's settings");
    }

    static function testAssignmentAndFallback():Void {
        var renderer = new MeshRenderer();
        assertTrue(renderer.material == Material.defaultMaterial(),
            "Default Material was not assigned automatically");

        assertTrue(renderer.setInspectorAsset("mesh", PrimitiveMeshes.SPHERE_ID),
            "mesh assignment failed");
        assertTrue(renderer.mesh == PrimitiveMeshes.sphere(),
            "mesh asset reference was not assigned");
        assertTrue(!renderer.setInspectorAsset("mesh", "missing:asset"),
            "unknown mesh id should be ignored");
        assertTrue(renderer.mesh == PrimitiveMeshes.sphere(),
            "unknown mesh id destroyed the current assignment");
        assertTrue(renderer.setInspectorAsset("mesh", ""),
            "clearing the mesh reference failed");
        assertTrue(renderer.mesh == null, "empty mesh id should mean no geometry");

        var custom = new Material("test:metal", "Metal", 0x8899AA);
        Material.register(custom);
        assertTrue(renderer.setInspectorAsset("material", custom.id),
            "material assignment failed");
        assertTrue(renderer.material == custom, "material asset reference was not assigned");
        assertTrue(renderer.setInspectorAsset("material", ""),
            "clearing the material reference failed");
        assertTrue(renderer.material == Material.defaultMaterial(),
            "missing material reference did not fall back to Default Material");
    }

    static function testSharedAssetsDistinctInstances():Void {
        var session = new EditorSession(8);
        var first = session.addInitialObject("First", new EditorTransform(), null,
            [PrimitiveGameObjects.createCubeRenderer()]);
        var second = session.createObject("Second", new EditorTransform(3, 0, 0), -1,
            [PrimitiveGameObjects.createCubeRenderer()]);
        var firstView = new SceneObject(first.id, new h3d.scene.Object(), first.persistentId);
        var secondView = new SceneObject(second.id, new h3d.scene.Object(), second.persistentId);
        firstView.synchronizeComponents(first);
        secondView.synchronizeComponents(second);

        var firstMesh = firstView.renderMesh;
        var secondMesh = secondView.renderMesh;
        assertTrue(firstMesh != null && secondMesh != null,
            "renderer views were not mounted");
        assertTrue(firstMesh != secondMesh,
            "two entities accidentally share one scene mesh instance");
        assertTrue(firstMesh.material != secondMesh.material,
            "two entities accidentally share one mutable Heaps material");
        assertTrue(firstMesh.primitive == secondMesh.primitive,
            "two entities should share the cached geometry for one mesh asset");

        // Changing the asset reference updates that renderer's own instance
        // without touching the other entity.
        var firstRenderer = first.getComponent(MeshRenderer);
        assertTrue(firstRenderer.setInspectorAsset("mesh", PrimitiveMeshes.SPHERE_ID),
            "mesh asset change failed");
        firstView.synchronizeComponents(first);
        assertTrue(firstView.renderMesh.primitive
            == HeapsMeshFactory.resolve(PrimitiveMeshes.sphere()),
            "runtime instance did not follow its mesh asset reference");
        assertTrue(secondView.renderMesh.primitive
            == HeapsMeshFactory.resolve(PrimitiveMeshes.cube()),
            "changing one entity mutated another entity's renderer");

        // Removing the asset reference detaches only that renderer.
        firstRenderer.setInspectorAsset("mesh", "");
        firstView.synchronizeComponents(first);
        assertTrue(firstView.allRenderMeshes().length == 0,
            "clearing the mesh asset did not detach the runtime instance");
        assertTrue(secondView.allRenderMeshes().length == 1,
            "clearing one mesh asset affected another entity");
    }

    static function property(
            properties:Array<boltspark.engine.inspector.ComponentPropertyData>,
            id:String):Null<ComponentPropertyData> {
        for (candidate in properties) {
            if (candidate.id == id) return candidate;
        }
        return null;
    }

    static function hasOption(data:ComponentPropertyData, id:String):Bool {
        for (option in data.options) {
            if (option.id == id) return true;
        }
        return false;
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
