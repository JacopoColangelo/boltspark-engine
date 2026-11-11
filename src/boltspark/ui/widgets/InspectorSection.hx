package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiIcons;

/**
 * Collapsible inspector section header in the Unreal/CryEngine property-panel
 * style: a full-width interactive header with a chevron and title, a divider
 * rule, and a content area owned by the shell.
 */
class InspectorSection extends h2d.Object {
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
        chevron = new h2d.Graphics(this);
        title = new h2d.Text(ctx.semiboldFont, this);
        title.text = titleText;
        title.textColor = Theme.TEXT;
        title.lineBreak = false;
        title.x = 20;
        title.y = Math.round((Theme.SECTION_HEADER_HEIGHT - title.textHeight) * 0.5);
        divider = new h2d.Graphics(this);
        content = new h2d.Object(this);
        hit = new h2d.Interactive(1, Theme.SECTION_HEADER_HEIGHT, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Button;
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
            ? Theme.SECTION_HEADER_HEIGHT + contentHeight + 6
            : Theme.SECTION_HEADER_HEIGHT + 2;
    }

    function drawChevron():Void {
        chevron.clear();
        UiIcons.draw(chevron, expanded ? ChevronDown : ChevronRight, 0, 0, 12, Theme.MUTED);
        chevron.x = 3;
        chevron.y = Math.round((Theme.SECTION_HEADER_HEIGHT - 12) * 0.5);
    }

    function redraw():Void {
        divider.clear();
        if (hovered) {
            divider.beginFill(Theme.SURFACE_1, 0.6);
            divider.drawRect(0, 0, Math.max(0, hit.width), Theme.SECTION_HEADER_HEIGHT - 1);
            divider.endFill();
        }
        divider.lineStyle(1, hovered ? Theme.BORDER_STRONG : Theme.BORDER, 1);
        divider.moveTo(0, Theme.SECTION_HEADER_HEIGHT - 1);
        divider.lineTo(Math.max(0, hit.width), Theme.SECTION_HEADER_HEIGHT - 1);
        divider.lineStyle();
    }
}
