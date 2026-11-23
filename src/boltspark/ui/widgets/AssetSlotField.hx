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
 * Typed asset slot for the Inspector, laid out like the Unreal property editor:
 * a large square thumbnail with a browse/clear action pair sits *outside* the
 * asset-name combo box instead of being squeezed into its left edge.
 *
 * The whole block is one typed drop target, so a compatible asset dragged from
 * the browser highlights and assigns it no matter where on the block it lands.
 * The widget stays asset-agnostic through `assetType`, so future asset families
 * get the same picker and drop behaviour for free.
 */
class AssetSlotField extends h2d.Object {
    /** Widget height: the thumbnail sets the height so the highlight lines up
     *  with the visible artwork instead of wrapping empty space. */
    public static inline var SLOT_HEIGHT:Float = 56;

    static inline var THUMB_SIZE:Float = 56;
    static inline var COMBO_HEIGHT:Float = 26;
    static inline var ACTION_WIDTH:Float = 22;
    static inline var ACTION_HEIGHT:Float = 20;
    static inline var ACTION_GAP:Float = 4;
    static inline var ARROW_WIDTH:Float = 14;

    public var onPick:Null<Void->Void>;
    /** Invoked by the magnifier: reveal the current asset in the browser. */
    public var onBrowse:Null<Void->Void>;
    public var onAssetDrop:Null<String->Void>;
    /** Invoked by the arrow action; the owner clears the assignment. */
    public var onClear:Null<Void->Void>;
    /** Optional live preview for texture-family slots (project-relative path
     *  in, cached tile out). Engine assets keep using PrimitiveThumbnails. */
    public var onQueryThumbnail(get, set):Null<String->Null<h2d.Tile>>;

    public var assetType(get, set):Null<AssetType>;
    /** Currently assigned asset id; drives the large thumbnail. */
    public var assetId(get, set):String;

    final ctx:UiContext;
    final dropFrame:h2d.Graphics;
    final thumbFrame:h2d.Graphics;
    final thumbIcon:h2d.Graphics;
    final combo:FieldSurface;
    final valueText:h2d.Text;
    final chevron:h2d.Graphics;
    final actionBg:h2d.Graphics;
    final pickIcon:h2d.Graphics;
    final clearIcon:h2d.Graphics;
    final thumbHit:h2d.Interactive;
    final comboHit:h2d.Interactive;
    final pickHit:h2d.Interactive;
    final clearHit:h2d.Interactive;

    var typeValue:Null<AssetType> = null;
    var queryThumbnail:Null<String->Null<h2d.Tile>> = null;
    var assetIdValue:String = "";
    var dropTarget:Null<AssetDropTarget> = null;
    var labelValue:String = "None";
    var widthValue:Float = 0;
    var hovered:Bool = false;
    var dropHighlighted:Bool = false;

    public function new(ctx:UiContext, width:Float, value:String, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        labelValue = value;

        thumbFrame = new h2d.Graphics(this);
        thumbIcon = new h2d.Graphics(this);
        combo = new FieldSurface(this);
        valueText = new UiText(ctx.font, this);
        valueText.lineBreak = false;
        valueText.textColor = Theme.TEXT;
        chevron = new h2d.Graphics(this);
        UiIcons.draw(chevron, ChevronDown, 0, 0, 10, Theme.MUTED);
        actionBg = new h2d.Graphics(this);
        // Separate targets: UiIcons.draw() clears its Graphics' children, so
        // two icons in one object would leave only the last one visible.
        pickIcon = new h2d.Graphics(this);
        clearIcon = new h2d.Graphics(this);
        // Drawn last: one clean highlight frame over the artwork, so it never
        // peeks out from under the thumbnail/combo/action borders.
        dropFrame = new h2d.Graphics(this);

        thumbHit = makeHit(0, 0, THUMB_SIZE, SLOT_HEIGHT, pick);
        comboHit = makeHit(0, 0, 1, 1, pick);
        pickHit = makeHit(0, 0, ACTION_WIDTH, ACTION_HEIGHT, browse);
        clearHit = makeHit(0, 0, ACTION_WIDTH, ACTION_HEIGHT, function() {
            if (onClear != null) onClear();
        });
        thumbHit.onOver = function(_) setHovered(true);
        thumbHit.onOut = function(_) setHovered(false);
        comboHit.onOver = function(_) setHovered(true);
        comboHit.onOut = function(_) setHovered(false);

        setValue(value);
        setWidth(width);
    }

    function makeHit(x:Float, y:Float, width:Float, height:Float,
            onClick:Void->Void):h2d.Interactive {
        var hit = new h2d.Interactive(width, height, this);
        hit.x = x;
        hit.y = y;
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onClick = function(event) {
            event.propagate = false;
            onClick();
        };
        return hit;
    }

    inline function pick():Void {
        if (onPick != null) onPick();
    }

    inline function browse():Void {
        if (onBrowse != null) onBrowse();
    }

    function setHovered(value:Bool):Void {
        if (hovered == value) return;
        hovered = value;
        updateStyle();
    }

    function get_onQueryThumbnail():Null<String->Null<h2d.Tile>> return queryThumbnail;

    function set_onQueryThumbnail(value:Null<String->Null<h2d.Tile>>):Null<String->Null<h2d.Tile>> {
        queryThumbnail = value;
        drawThumb();
        return value;
    }

    function get_assetType():Null<AssetType> return typeValue;

    function set_assetType(value:Null<AssetType>):Null<AssetType> {
        if (typeValue == value) return value;
        typeValue = value;
        if (dropTarget != null) {
            AssetDragSession.remove(dropTarget);
            dropTarget = null;
        }
        drawThumb();
        if (typeValue != null) {
            dropTarget = new AssetDropTarget(typeValue, this, dropRect,
                setDropHighlight, function(payload) {
                    if (onAssetDrop != null) onAssetDrop(payload.assetId);
                });
            AssetDragSession.add(dropTarget);
            if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
                Sys.println('[probe] asset slot registered type=${typeValue}');
            }
        }
        return value;
    }

    function get_assetId():String return assetIdValue;

    function set_assetId(value:String):String {
        assetIdValue = value == null ? "" : value;
        drawThumb();
        return assetIdValue;
    }

    function dropRect():AssetDropRect {
        // Window-space rect: the h2d UI scene is 1:1 with the native window,
        // and getAbsPos includes all dock/mask offsets.
        var pos = getAbsPos();
        return {
            x: pos.x, y: pos.y, width: widthValue, height: SLOT_HEIGHT
        };
    }

    function setDropHighlight(active:Bool):Void {
        if (dropHighlighted == active) return;
        if (active && Sys.getEnv("BOLTSPARK_PROBE") != null) {
            var rect = dropRect();
            Sys.println('[probe] asset slot type=${typeValue}'
                + ' rect=${Std.int(rect.x)},${Std.int(rect.y)}'
                + ' ${Std.int(rect.width)}x${Std.int(rect.height)}');
        }
        dropHighlighted = active;
        redrawDropFrame();
        drawThumb();
        drawActions();
        updateStyle();
    }

    public function setValue(value:String):Void {
        labelValue = value == null ? "" : value;
        fitLabel();
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        var comboX = THUMB_SIZE + ACTION_GAP;
        var comboWidth = Math.max(0, widthValue - comboX);
        combo.x = comboX;
        combo.y = 0;
        combo.setSize(comboWidth, COMBO_HEIGHT);
        valueText.x = comboX + 8;
        chevron.x = comboX + Math.max(0, comboWidth - ARROW_WIDTH - 2);
        chevron.y = Math.round((COMBO_HEIGHT - 10) * 0.5);
        comboHit.x = comboX;
        comboHit.y = 0;
        comboHit.width = comboWidth;
        comboHit.height = COMBO_HEIGHT;
        pickHit.x = comboX;
        pickHit.y = COMBO_HEIGHT + ACTION_GAP;
        clearHit.x = comboX + ACTION_WIDTH + ACTION_GAP;
        clearHit.y = COMBO_HEIGHT + ACTION_GAP;
        drawActions();
        drawThumb();
        redrawDropFrame();
        fitLabel();
    }

    function drawThumb():Void {
        thumbFrame.clear();
        thumbIcon.clear();
        // UiIcons.draw attaches Bitmap children; clear() only drops vector
        // commands, so remove them before drawing a fallback glyph again.
        thumbIcon.removeChildren();
        // While highlighted the outer drop frame is the only outline; inner
        // borders would show through as a second, offset rectangle.
        if (!dropHighlighted) {
            thumbFrame.lineStyle(1, Theme.BORDER_STRONG, 1);
            thumbFrame.drawRect(0.5, 0.5, THUMB_SIZE - 1, THUMB_SIZE - 1);
            thumbFrame.lineStyle();
        }
        var tint = dropHighlighted ? Theme.ACCENT_HOVER : Theme.TEXT_SECONDARY;
        var preview = assetIdValue != "" && queryThumbnail != null
            ? queryThumbnail(assetIdValue) : null;
        if (preview != null) {
            var bitmap = new h2d.Bitmap(preview, thumbIcon);
            var box = THUMB_SIZE - 6;
            var scale = Math.min(box / preview.width, box / preview.height);
            bitmap.width = preview.width * scale;
            bitmap.height = preview.height * scale;
            bitmap.x = 3 + (box - bitmap.width) * 0.5;
            bitmap.y = 3 + (box - bitmap.height) * 0.5;
        } else if (assetIdValue != "") {
            PrimitiveThumbnails.draw(thumbIcon, assetIdValue, 3, 3,
                THUMB_SIZE - 6, THUMB_SIZE - 6, tint);
        } else if (typeValue == AssetType.TextureAsset) {
            UiIcons.drawSceneThumb(thumbIcon, 8, 8, THUMB_SIZE - 16, tint);
        } else {
            var kind:UiIconKind = switch (typeValue) {
                case AssetType.MeshAsset: Cube;
                case AssetType.MaterialAsset: Box;
                default: Document;
            };
            UiIcons.draw(thumbIcon, kind, 8, 8, THUMB_SIZE - 16, tint);
        }
    }

    function drawActions():Void {
        actionBg.clear();
        actionBg.beginFill(Theme.FIELD_BG, 1);
        actionBg.drawRect(pickHit.x, pickHit.y, ACTION_WIDTH, ACTION_HEIGHT);
        actionBg.drawRect(clearHit.x, clearHit.y, ACTION_WIDTH, ACTION_HEIGHT);
        actionBg.endFill();
        if (!dropHighlighted) {
            actionBg.lineStyle(1, Theme.BORDER, 1);
            actionBg.drawRect(pickHit.x + 0.5, pickHit.y + 0.5,
                ACTION_WIDTH - 1, ACTION_HEIGHT - 1);
            actionBg.drawRect(clearHit.x + 0.5, clearHit.y + 0.5,
                ACTION_WIDTH - 1, ACTION_HEIGHT - 1);
            actionBg.lineStyle();
        }

        var tint = dropHighlighted ? Theme.ACCENT_HOVER : Theme.TEXT_SECONDARY;
        UiIcons.draw(pickIcon, Search, pickHit.x + 3, pickHit.y + 3,
            ACTION_WIDTH - 6, tint);
        UiIcons.draw(clearIcon, Reset, clearHit.x + 3, clearHit.y + 3,
            ACTION_WIDTH - 6, tint);
    }

    function redrawDropFrame():Void {
        dropFrame.clear();
        if (!dropHighlighted || widthValue <= 0) return;
        // One translucent tint plus a single 2px frame exactly on the slot
        // bounds. Drawing it on top keeps it crisp and perfectly aligned with
        // the thumbnail/combo/actions instead of showing doubled inner edges.
        dropFrame.beginFill(Theme.ACCENT_MUTED, 0.35);
        dropFrame.drawRect(0, 0, widthValue, SLOT_HEIGHT);
        dropFrame.endFill();
        dropFrame.lineStyle(2, Theme.SELECTION_OUTLINE, 1);
        dropFrame.drawRect(1, 1,
            Math.max(0, widthValue - 2), Math.max(0, SLOT_HEIGHT - 2));
        dropFrame.lineStyle();
    }

    function fitLabel():Void {
        var comboX = THUMB_SIZE + ACTION_GAP;
        var maxWidth = Math.max(0,
            widthValue - comboX - 8 - ARROW_WIDTH - 4);
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
        // A highlighted slot uses its single outer frame; give the combo the
        // same colour for its 1px border so it does not draw a second outline.
        var border = dropHighlighted ? fill
            : (hovered ? Theme.ACCENT : Theme.BORDER);
        combo.setStyle(fill, border);
        drawThumb();
        drawActions();
    }
}
