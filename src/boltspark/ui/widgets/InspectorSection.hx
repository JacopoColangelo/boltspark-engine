package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiIcons;
import boltspark.ui.UiText;

/**
 * Collapsible full-width property group. The inspector shell spaces stacked
 * sections apart, and every section pads its header banner from the rows
 * below it, so each group reads as its own block.
 */
class InspectorSection extends h2d.Object {
    /** Breathing room between the header banner and the first content row. */
    static inline var HEADER_GAP:Int = Theme.SPACING;

    /** Invoked after the section expands or collapses so the panel re-lays out. */
    public var onToggle:Null<Void->Void>;

    /** Height contributed by the rows inside `content`; set by the shell. */
    public var contentHeight:Float = 34;

    public var expanded(default, null):Bool = true;

    public final content:h2d.Object;

    final chevron:h2d.Graphics;
    final title:h2d.Text;
    final divider:h2d.Graphics;
    final hit:h2d.Interactive;
    var hovered:Bool = false;

    public function new(ctx:UiContext, titleText:String, ?parent:h2d.Object) {
        super(parent);
        // The header fill must sit behind its glyphs and label.
        divider = new h2d.Graphics(this);
        chevron = new h2d.Graphics(this);
        title = new UiText(ctx.labelFont, this);
        title.text = titleText.toUpperCase();
        title.textColor = Theme.TEXT_SECONDARY;
        title.lineBreak = false;
        title.x = 19;
        title.y = Math.round((Theme.SECTION_HEADER_HEIGHT - title.textHeight) * 0.5);
        content = new h2d.Object(this);
        content.y = Theme.SECTION_HEADER_HEIGHT + HEADER_GAP;
        hit = new h2d.Interactive(1, Theme.SECTION_HEADER_HEIGHT, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onOver = function(_) {
            hovered = true;
            redraw();
        };
        hit.onOut = function(_) {
            hovered = false;
            redraw();
        };
        hit.onClick = function(_) setExpanded(!expanded);
        drawChevron();
        redraw();
    }

    public function setExpanded(value:Bool):Void {
        if (expanded == value) return;
        expanded = value;
        content.visible = value;
        drawChevron();
        if (onToggle != null) onToggle();
    }

    public function setWidth(width:Float):Void {
        hit.width = Math.max(0, width);
        redraw();
    }

    /** Total vertical space taken by the section at current expand state. */
    public function totalHeight():Float {
        return expanded
            ? Theme.SECTION_HEADER_HEIGHT + HEADER_GAP + contentHeight + 1
            : Theme.SECTION_HEADER_HEIGHT + 1;
    }

    function drawChevron():Void {
        chevron.clear();
        UiIcons.draw(chevron, expanded ? ChevronDown : ChevronRight, 0, 0, 12, Theme.MUTED);
        chevron.x = 4;
        chevron.y = Math.round((Theme.SECTION_HEADER_HEIGHT - 12) * 0.5);
    }

    function redraw():Void {
        divider.clear();
        divider.beginFill(hovered ? Theme.SURFACE_3 : Theme.SECTION_HEADER, 1);
        divider.drawRect(0, 0, Math.max(0, hit.width), Theme.SECTION_HEADER_HEIGHT - 1);
        divider.endFill();
        divider.lineStyle(1, Theme.BORDER, 1);
        divider.moveTo(0, Theme.SECTION_HEADER_HEIGHT - 1);
        divider.lineTo(Math.max(0, hit.width), Theme.SECTION_HEADER_HEIGHT - 1);
        divider.lineStyle();
    }
}
