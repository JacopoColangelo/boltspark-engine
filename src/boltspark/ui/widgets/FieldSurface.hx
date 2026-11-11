package boltspark.ui.widgets;

import boltspark.ui.Theme;

/**
 * Flat rectangular field background drawn with vector graphics: a 1px border
 * with a darker inset fill, in the Unreal/CryEngine property-editor style.
 * Avoids bitmap 9-slice rounding for dense inspector controls.
 */
class FieldSurface extends h2d.Object {
    final graphic:h2d.Graphics;
    var widthValue:Float = 0;
    var heightValue:Float = 0;
    var fillColor:Int = Theme.FIELD_BG;
    var borderColor:Int = Theme.BORDER;

    public function new(?parent:h2d.Object) {
        super(parent);
        graphic = new h2d.Graphics(this);
    }

    public function setSize(width:Float, height:Float):Void {
        widthValue = Math.max(0, width);
        heightValue = Math.max(0, height);
        redraw();
    }

    public function setStyle(fillColor:Int, borderColor:Int):Void {
        this.fillColor = fillColor;
        this.borderColor = borderColor;
        redraw();
    }

    function redraw():Void {
        graphic.clear();
        if (widthValue <= 0 || heightValue <= 0) return;
        graphic.beginFill(fillColor, 1);
        graphic.drawRect(0, 0, widthValue, heightValue);
        graphic.endFill();
        graphic.lineStyle(1, borderColor, 1);
        graphic.drawRect(0.5, 0.5, widthValue - 1, heightValue - 1);
        graphic.lineStyle();
    }
}
