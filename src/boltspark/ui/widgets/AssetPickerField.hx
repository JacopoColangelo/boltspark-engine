package boltspark.ui.widgets;

import boltspark.engine.inspector.AssetType;
import boltspark.ui.AssetDragSession;
import boltspark.ui.AssetDropRect;
import boltspark.ui.AssetDropTarget;
import boltspark.ui.PrimitiveThumbnails;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiText;

/**
 * Compact object-picker field for asset-valued Inspector properties.
 *
 * The widget stays asset-agnostic: it renders the current label, opens a picker
 * via `onPick`, and — when an `assetType` is supplied — registers itself as a
 * typed drop slot. Only drags carrying that asset family can highlight or drop
 * here; the owner applies the resulting id to the component. The same field
 * works for meshes, materials, or any future asset family.
 */
class AssetPickerField extends h2d.Object {
    static inline var ARROW_WIDTH:Float = 16;
    /** Left slot frame that visually marks this as a typed asset slot. */
    static inline var SLOT_SIZE:Float = 22;
    static inline var SLOT_PAD:Float = 2;

    public var onPick:Null<Void->Void>;
    /** Fired with the concrete asset id when a compatible engine asset is dropped. */
    public var onAssetDrop:Null<String->Void>;
    public var assetType(get, set):Null<AssetType>;
    /** Currently assigned asset id; drives the thumbnail drawn in the slot. */
    public var assetId(get, set):String;

    final ctx:UiContext;
    final surface:FieldSurface;
    final slotFrame:h2d.Graphics;
    final slotIcon:h2d.Graphics;
    final dropFrame:h2d.Graphics;
    final valueText:h2d.Text;
    final chevron:h2d.Graphics;
    final hit:h2d.Interactive;
    var typeValue:Null<AssetType> = null;
    var assetIdValue:String = "";
    var dropTarget:Null<AssetDropTarget> = null;
    var labelValue:String = "None";
    var widthValue:Float = 0;
    var heightValue:Float;
    var hovered:Bool = false;
    var dropHighlighted:Bool = false;

    public function new(ctx:UiContext, width:Float, height:Float,
            value:String, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        heightValue = height;
        labelValue = value;

        surface = new FieldSurface(this);
        // Drop highlight sits behind the slot art and label so it tints the
        // whole field without hiding the current asset thumbnail.
        dropFrame = new h2d.Graphics(this);
        slotFrame = new h2d.Graphics(this);
        slotIcon = new h2d.Graphics(this);
        valueText = new UiText(ctx.font, this);
        valueText.lineBreak = false;
        valueText.textColor = Theme.TEXT;
        chevron = new h2d.Graphics(this);
        UiIcons.draw(chevron, ChevronDown, 0, 0, 10, Theme.MUTED);

        hit = new h2d.Interactive(1, 1, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onOver = function(_) {
            hovered = true;
            updateStyle();
        };
        hit.onOut = function(_) {
            hovered = false;
            updateStyle();
        };
        hit.onClick = function(event) {
            event.propagate = false;
            if (onPick != null) onPick();
        };

        setValue(value);
        setWidth(width);
    }

    function get_assetType():Null<AssetType> return typeValue;

    function get_assetId():String return assetIdValue;

    function set_assetId(value:String):String {
        assetIdValue = value == null ? "" : value;
        drawSlot();
        return assetIdValue;
    }

    function set_assetType(value:Null<AssetType>):Null<AssetType> {
        if (typeValue == value) return value;
        typeValue = value;
        if (dropTarget != null) {
            AssetDragSession.remove(dropTarget);
            dropTarget = null;
        }
        drawSlot();
        if (typeValue != null) {
            dropTarget = new AssetDropTarget(typeValue, this, dropRect,
                setDropHighlight, function(payload) {
                    if (onAssetDrop != null) onAssetDrop(payload.assetId);
                });
            AssetDragSession.add(dropTarget);
        }
        return value;
    }

    function dropRect():AssetDropRect {
        // Window-space rect: the h2d UI scene is 1:1 with the native window,
        // and getAbsPos includes all dock/mask offsets.
        var pos = getAbsPos();
        return {
            x: pos.x, y: pos.y, width: widthValue, height: heightValue
        };
    }

    function setDropHighlight(active:Bool):Void {
        if (dropHighlighted == active) return;
        dropHighlighted = active;
        chevron.visible = !active;
        redrawDropFrame();
        updateStyle();
    }

    public function setValue(value:String):Void {
        labelValue = value == null ? "" : value;
        fitLabel();
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        surface.setSize(widthValue, heightValue);
        valueText.x = SLOT_PAD * 2 + SLOT_SIZE;
        valueText.y = Math.max(0,
            Math.round((heightValue - valueText.textHeight) * 0.5 - 1));
        chevron.x = Math.max(0, widthValue - ARROW_WIDTH);
        chevron.y = Math.max(0, Math.round((heightValue - 10) * 0.5));
        hit.width = widthValue;
        hit.height = heightValue;
        drawSlot();
        redrawDropFrame();
        fitLabel();
    }

    function drawSlot():Void {
        slotFrame.clear();
        slotIcon.clear();
        // UiIcons.draw attaches Bitmap children; clear() only drops vector
        // commands, so remove them when switching back to the fallback glyph.
        slotIcon.removeChildren();
        var size = Math.min(SLOT_SIZE, Math.max(8, heightValue - 2));
        var x = SLOT_PAD;
        var y = Math.round((heightValue - size) * 0.5);
        slotFrame.lineStyle(1, Theme.BORDER_STRONG, 1);
        slotFrame.drawRect(x + 0.5, y + 0.5, size - 1, size - 1);
        slotFrame.lineStyle();
        var tint = dropHighlighted ? Theme.ACCENT_HOVER : Theme.TEXT_SECONDARY;
        if (assetIdValue != "") {
            PrimitiveThumbnails.draw(slotIcon, assetIdValue,
                x + 2, y + 2, Math.max(6, size - 4),
                Math.max(6, size - 4), tint);
        } else {
            var kind:UiIconKind = switch (typeValue) {
                case AssetType.MeshAsset: Cube;
                case AssetType.MaterialAsset: Box;
                default: Document;
            };
            UiIcons.draw(slotIcon, kind, x + 3, y + 3, Math.max(6, size - 6), tint);
        }
    }

    function redrawDropFrame():Void {
        dropFrame.clear();
        if (!dropHighlighted || widthValue <= 0) return;
        dropFrame.beginFill(Theme.ACCENT_MUTED, 0.9);
        dropFrame.drawRect(0, 0, widthValue, heightValue);
        dropFrame.endFill();
        dropFrame.lineStyle(3, Theme.SELECTION_OUTLINE, 1);
        dropFrame.drawRect(1.5, 1.5, widthValue - 3, heightValue - 3);
        dropFrame.lineStyle();
    }

    function fitLabel():Void {
        var maxWidth = Math.max(0,
            widthValue - ARROW_WIDTH - SLOT_PAD * 2 - SLOT_SIZE - 6);
        if (valueText.calcTextWidth(labelValue) <= maxWidth) {
            valueText.text = labelValue;
            return;
        }
        var text = "";
        for (index in 0...labelValue.length) {
            var candidate = labelValue.substr(0, index + 1) + "…";
            if (valueText.calcTextWidth(candidate) > maxWidth) break;
            text = candidate;
        }
        valueText.text = text;
    }

    function updateStyle():Void {
        var fill = hovered || dropHighlighted ? Theme.FIELD_FOCUS : Theme.FIELD_BG;
        var border = hovered || dropHighlighted ? Theme.ACCENT : Theme.BORDER;
        surface.setStyle(fill, border);
        drawSlot();
    }
}
