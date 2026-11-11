package boltspark.ui;

/** Crisp rectangular editor surface with optional border and hard shadow. */
class UiSurface extends h2d.Object {
    final graphic:h2d.Graphics;

    var widthValue:Float = 0;
    var heightValue:Float = 0;
    var inset:Float = 1;
    var fillColor:Int = Theme.SURFACE_2;
    var borderColor:Int = Theme.BORDER;
    var shadowAlpha:Float = 0;

    public function new(_ctx:UiContext, ?parent:h2d.Object) {
        super(parent);
        graphic = new h2d.Graphics(this);
        setStyle(Theme.SURFACE_2, Theme.BORDER, 0);
    }

    public function setSize(width:Float, height:Float):Void {
        widthValue = Math.max(0, width);
        heightValue = Math.max(0, height);
        redraw();
    }

    public function setStyle(fillColor:Int, borderColor:Int, shadowAlpha:Float = 0.0,
            borderInset:Float = 1.0):Void {
        inset = Math.max(0, borderInset);
        this.fillColor = fillColor;
        this.borderColor = borderColor;
        this.shadowAlpha = Math.max(0, Math.min(1, shadowAlpha));
        redraw();
    }

    public function setFill(color:Int):Void {
        fillColor = color;
        redraw();
    }

    public function setBorder(color:Int):Void {
        borderColor = color;
        redraw();
    }

    function redraw():Void {
        graphic.clear();
        if (widthValue <= 0 || heightValue <= 0) return;
        if (shadowAlpha > 0) {
            graphic.beginFill(0x000000, shadowAlpha);
            graphic.drawRect(2, 2, widthValue, heightValue);
            graphic.endFill();
        }
        if (inset > 0) {
            graphic.beginFill(borderColor, 1);
            graphic.drawRect(0, 0, widthValue, heightValue);
            graphic.endFill();
            graphic.beginFill(fillColor, 1);
            graphic.drawRect(inset, inset,
                Math.max(0, widthValue - inset * 2),
                Math.max(0, heightValue - inset * 2));
            graphic.endFill();
        } else {
            graphic.beginFill(fillColor, 1);
            graphic.drawRect(0, 0, widthValue, heightValue);
            graphic.endFill();
        }
    }
}
