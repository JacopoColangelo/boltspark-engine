package boltspark.editor;

import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;

/**
 * Builds the Inspector projection for a multi-object selection.
 *
 * Only components and properties present on *every* selected object are
 * shown. Values shared by all objects are displayed normally; a value that
 * differs is flagged as mixed (`ComponentPropertyData.mixed`) so the widget
 * shows "Multiple Values" while keeping a valid primary value as an edit base.
 *
 * The primary object's component indices are retained so existing
 * `(componentIndex, propertyId, axis)` edit callbacks keep working.
 */
class MultiInspectorData {
    static inline var EPSILON:Float = 0.0001;

    public static function build(
            primary:Array<ComponentInspectorData>,
            all:Array<Array<ComponentInspectorData>>):Array<ComponentInspectorData> {
        var result:Array<ComponentInspectorData> = [];
        if (primary == null || all == null || all.length == 0) return result;
        for (section in primary) {
            var peers:Array<ComponentInspectorData> = [];
            var shared = true;
            for (data in all) {
                var match:Null<ComponentInspectorData> = null;
                if (data != null) {
                    for (candidate in data) {
                        if (candidate.typeId == section.typeId) {
                            match = candidate;
                            break;
                        }
                    }
                }
                if (match == null) {
                    shared = false;
                    break;
                }
                peers.push(match);
            }
            if (!shared) continue;

            var properties:Array<ComponentPropertyData> = [];
            for (property in section.properties) {
                var propertyPeers:Array<ComponentPropertyData> = [];
                var propertyShared = true;
                for (peer in peers) {
                    var match:Null<ComponentPropertyData> = null;
                    for (candidate in peer.properties) {
                        if (candidate.id == property.id) {
                            match = candidate;
                            break;
                        }
                    }
                    if (match == null || match.kind != property.kind) {
                        propertyShared = false;
                        break;
                    }
                    propertyPeers.push(match);
                }
                if (propertyShared) properties.push(mergeProperty(property, propertyPeers));
            }
            result.push(new ComponentInspectorData(section.componentIndex,
                section.typeId, section.title, properties, section.removable));
        }
        return result;
    }

    static function mergeProperty(base:ComponentPropertyData,
            peers:Array<ComponentPropertyData>):ComponentPropertyData {
        return switch (base.kind) {
            case Vector3:
                var values = base.numberValues.copy();
                var mixed = [false, false, false];
                for (peer in peers) {
                    for (axis in 0...3) {
                        if (!close(valueAt(values, axis), valueAt(peer.numberValues, axis))) {
                            mixed[axis] = true;
                        }
                    }
                }
                new ComponentPropertyData(base.id, base.label, Vector3, values, "",
                    base.editable, base.resettable, base.linkable, base.linked, mixed);
            case Text:
                var mixed = false;
                for (peer in peers) {
                    if (peer.textValue != base.textValue) mixed = true;
                }
                new ComponentPropertyData(base.id, base.label, Text, [],
                    base.textValue, base.editable, base.resettable,
                    base.linkable, base.linked, [mixed]);
            case Asset:
                var mixed = false;
                for (peer in peers) {
                    if (peer.assetId != base.assetId) mixed = true;
                }
                new ComponentPropertyData(base.id, base.label, Asset, [],
                    base.textValue, base.editable, false, false, false,
                    [mixed], base.assetType, base.assetId, base.options);
            case Number, Integer:
                var mixed = false;
                for (peer in peers) {
                    if (!close(valueAt(base.numberValues, 0),
                            valueAt(peer.numberValues, 0))) mixed = true;
                }
                new ComponentPropertyData(base.id, base.label, base.kind,
                    base.numberValues, "", base.editable, base.resettable,
                    false, false,
                    [mixed], null, "", null, false, base.numberMin,
                    base.numberMax, base.numberStep, base.integerValue);
            case Boolean:
                var mixed = false;
                for (peer in peers) {
                    if (peer.boolValue != base.boolValue) mixed = true;
                }
                new ComponentPropertyData(base.id, base.label, Boolean, [], "",
                    base.editable, base.resettable, false, false, [mixed],
                    null, "", null, base.boolValue);
        };
    }

    static inline function valueAt(values:Array<Float>, axis:Int):Float {
        return axis >= 0 && axis < values.length ? values[axis] : 0;
    }

    static inline function close(a:Float, b:Float):Bool {
        return Math.isFinite(a) && Math.isFinite(b) && Math.abs(a - b) <= EPSILON;
    }
}
