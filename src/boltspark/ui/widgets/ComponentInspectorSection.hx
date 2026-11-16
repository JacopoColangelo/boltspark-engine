package boltspark.ui.widgets;

import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.engine.inspector.ComponentPropertyKind;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiText;

/** Generic retained-H2D section generated from Component property metadata. */
class ComponentInspectorSection extends InspectorSection {
    static inline var ROW_HEIGHT:Int = 28;
    static inline var ACTION_WIDTH:Int = 22;

    public final componentIndex:Int;
    public final typeId:String;
    public var onNumberCommit:Null<String->Int->Float->Void>;
    public var onNumberEditBegin:Null<String->Int->Void>;
    public var onNumberEditEnd:Null<String->Int->Void>;
    public var onTextCommit:Null<String->String->Void>;
    public var onReset:Null<String->Void>;
    public var onLinkChanged:Null<String->Bool->Void>;
    public var onEditRejected:Null<String->Void>;

    final ctx:UiContext;
    final vectors:Array<VectorPropertyControls> = [];
    final texts:Array<TextPropertyControls> = [];
    var hasLinkAction:Bool = false;
    var widthValue:Float = 0;

    public function new(ctx:UiContext, data:ComponentInspectorData,
            linkedScale:Bool, ?parent:h2d.Object) {
        super(ctx, data.title, parent);
        this.ctx = ctx;
        componentIndex = data.componentIndex;
        typeId = data.typeId;

        var row = 0;
        for (property in data.properties) {
            switch (property.kind) {
                case Vector3:
                    createVector(property, row++, linkedScale);
                case Text:
                    createText(property, row++);
            }
        }
        if (row == 0) {
            createText(ComponentPropertyData.text("empty", "Properties",
                "No exposed properties"), row++);
        }
        contentHeight = row * ROW_HEIGHT;
    }

    override public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        super.setWidth(widthValue);
        layoutControls();
    }

    public function updateVector(propertyId:String,
            x:Float, y:Float, z:Float):Bool {
        return updateVectorMixed(propertyId, [x, y, z], [false, false, false]);
    }

    /**
     * Live values for a multi-object selection. Mixed axes keep their primary
     * value as an edit base but display the "Multiple Values" placeholder.
     */
    public function updateVectorMixed(propertyId:String,
            values:Array<Float>, mixed:Array<Bool>):Bool {
        for (row in vectors) {
            if (row.propertyId != propertyId) continue;
            for (axis in 0...row.fields.length) {
                row.fields[axis].setValue(
                    axis < values.length ? values[axis] : 0);
                row.fields[axis].setMultiple(
                    axis < mixed.length && mixed[axis]);
            }
            return true;
        }
        return false;
    }

    public function setLinkState(propertyId:String, linked:Bool):Void {
        for (row in vectors) {
            if (row.propertyId != propertyId || row.linkButton == null) continue;
            row.linked = linked;
            row.linkButton.setIcon(linked ? Link : Unlink);
            row.linkButton.setSelected(linked);
        }
    }

    public function isEditing():Bool {
        for (row in vectors) {
            for (field in row.fields) if (field.isEditing()) return true;
        }
        for (row in texts) {
            if (row.input != null && row.input.isFocused()) return true;
        }
        return false;
    }

    function createVector(property:ComponentPropertyData, rowIndex:Int,
            linkedScale:Bool):Void {
        var row = new VectorPropertyControls(property.id, rowIndex);
        row.label = new UiText(ctx.labelFont, content);
        row.label.text = property.label;
        row.label.textColor = Theme.TEXT_SECONDARY;
        row.label.lineBreak = false;
        var axisNames = ["X", "Y", "Z"];
        var axisColors = [Theme.AXIS_X, Theme.AXIS_Y, Theme.AXIS_Z];
        for (axis in 0...3) {
            var field = new AxisValue(ctx, axisNames[axis], axisColors[axis],
                60, Theme.CONTROL_HEIGHT, content);
            field.setValue(property.numberValues.length > axis
                ? property.numberValues[axis] : 0);
            field.setMultiple(property.isMixed(axis));
            var capturedAxis = axis;
            var propertyId = property.id;
            field.onCommit = function(value) {
                if (onNumberCommit != null) {
                    onNumberCommit(propertyId, capturedAxis, value);
                }
            };
            field.onEditBegin = function() {
                if (onNumberEditBegin != null) {
                    onNumberEditBegin(propertyId, capturedAxis);
                }
            };
            field.onEditEnd = function() {
                if (onNumberEditEnd != null) {
                    onNumberEditEnd(propertyId, capturedAxis);
                }
            };
            field.onEditRejected = function(message) {
                if (onEditRejected != null) onEditRejected(message);
            };
            row.fields.push(field);
        }
        if (property.resettable) {
            row.resetButton = new UiButton(ctx, "", ACTION_WIDTH,
                Theme.CONTROL_HEIGHT, content);
            row.resetButton.setIcon(Reset);
            var propertyId = property.id;
            row.resetButton.onClick = function() {
                if (onReset != null) onReset(propertyId);
            };
        }
        if (property.linkable) {
            hasLinkAction = true;
            row.linked = linkedScale || property.linked;
            row.linkButton = new UiButton(ctx, "", ACTION_WIDTH,
                Theme.CONTROL_HEIGHT, content);
            row.linkButton.setIcon(row.linked ? Link : Unlink);
            row.linkButton.setSelected(row.linked);
            var propertyId = property.id;
            row.linkButton.onClick = function() {
                row.linked = !row.linked;
                row.linkButton.setIcon(row.linked ? Link : Unlink);
                row.linkButton.setSelected(row.linked);
                if (onLinkChanged != null) {
                    onLinkChanged(propertyId, row.linked);
                }
            };
        }
        vectors.push(row);
    }

    function createText(property:ComponentPropertyData, rowIndex:Int):Void {
        var row = new TextPropertyControls(property.id, rowIndex);
        if (property.isMixed(0)) {
            // Text components currently published by the engine are read-only;
            // show the mixed placeholder instead of a misleading single value.
            row.label = new UiText(ctx.labelFont, content);
            row.label.text = property.label;
            row.label.textColor = Theme.TEXT_SECONDARY;
            row.label.lineBreak = false;
            row.value = new UiText(ctx.font, content);
            row.value.text = NumericDragField.MULTIPLE_TEXT;
            row.value.textColor = Theme.MUTED;
            row.value.lineBreak = false;
        } else if (property.editable) {
            row.input = new TextInputField(ctx, property.label,
                100, Theme.CONTROL_HEIGHT, property.textValue, content);
            row.input.setLabelWidth(66);
            var propertyId = property.id;
            row.input.onCommit = function(value) {
                if (onTextCommit != null) onTextCommit(propertyId, value);
            };
        } else {
            row.label = new UiText(ctx.labelFont, content);
            row.label.text = property.label;
            row.label.textColor = Theme.TEXT_SECONDARY;
            row.label.lineBreak = false;
            row.value = new UiText(ctx.font, content);
            row.value.text = property.textValue;
            row.value.textColor = Theme.TEXT;
            row.value.lineBreak = false;
        }
        texts.push(row);
    }

    function layoutControls():Void {
        var fieldStart = 72.0;
        var axisGap = 4.0;
        var actionGap = 3.0;
        var resetX = Math.max(fieldStart, widthValue - 8 - ACTION_WIDTH);
        var linkX = resetX - actionGap - ACTION_WIDTH;
        var fieldEnd = (hasLinkAction ? linkX : resetX) - axisGap;
        var axisWidth = Math.max(0,
            (fieldEnd - fieldStart - axisGap * 2) / 3);

        for (row in vectors) {
            var rowY = 2 + row.rowIndex * ROW_HEIGHT;
            row.label.x = 8;
            row.label.y = rowY + Math.round(
                (Theme.CONTROL_HEIGHT - row.label.textHeight) * 0.5 - 1);
            for (axis in 0...row.fields.length) {
                row.fields[axis].x = fieldStart + axis * (axisWidth + axisGap);
                row.fields[axis].y = rowY;
                row.fields[axis].setWidth(axisWidth);
            }
            if (row.resetButton != null) {
                row.resetButton.x = resetX;
                row.resetButton.y = rowY;
            }
            if (row.linkButton != null) {
                row.linkButton.x = linkX;
                row.linkButton.y = rowY;
            }
        }

        for (row in texts) {
            var rowY = 2 + row.rowIndex * ROW_HEIGHT;
            if (row.input != null) {
                row.input.x = 8;
                row.input.y = rowY;
                row.input.setWidth(Math.max(0, widthValue - 16));
            } else {
                row.label.x = 8;
                row.label.y = rowY + Math.round(
                    (Theme.CONTROL_HEIGHT - row.label.textHeight) * 0.5 - 1);
                row.value.x = fieldStart;
                row.value.y = rowY + Math.round(
                    (Theme.CONTROL_HEIGHT - row.value.textHeight) * 0.5 - 1);
                fitText(row.value, row.value.text,
                    Math.max(0, widthValue - fieldStart - 8));
            }
        }
    }

    static function fitText(target:h2d.Text, fullValue:String,
            maxWidth:Float):Void {
        if (maxWidth <= 0) {
            target.text = "";
            return;
        }
        if (target.calcTextWidth(fullValue) <= maxWidth) {
            target.text = fullValue;
            return;
        }
        target.text = "";
        for (index in 0...fullValue.length) {
            var candidate = fullValue.substr(0, index + 1) + "…";
            if (target.calcTextWidth(candidate) > maxWidth) break;
            target.text = candidate;
        }
    }
}

private class VectorPropertyControls {
    public final propertyId:String;
    public final rowIndex:Int;
    public var label:h2d.Text;
    public final fields:Array<AxisValue> = [];
    public var resetButton:Null<UiButton>;
    public var linkButton:Null<UiButton>;
    public var linked:Bool = false;

    public function new(propertyId:String, rowIndex:Int) {
        this.propertyId = propertyId;
        this.rowIndex = rowIndex;
    }
}

private class TextPropertyControls {
    public final propertyId:String;
    public final rowIndex:Int;
    public var label:Null<h2d.Text>;
    public var value:Null<h2d.Text>;
    public var input:Null<TextInputField>;

    public function new(propertyId:String, rowIndex:Int) {
        this.propertyId = propertyId;
        this.rowIndex = rowIndex;
    }
}
