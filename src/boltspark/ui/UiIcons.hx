package boltspark.ui;

enum abstract UiIconKind(Int) from Int to Int {
    var None = 0;
    var Add = 1;
    var Trash = 2;
    var Cube = 3;
    var Search = 4;
    var Play = 5;
    var Pause = 6;
    var Stop = 7;
    var Move = 8;
    var Rotate = 9;
    var Scale = 10;
    var ChevronDown = 11;
    var ChevronRight = 12;
    var Console = 13;
    var Sliders = 14;
    var Hierarchy = 15;
    var Close = 16;
    var Grid = 17;
    var More = 18;
}

/** Procedural single-color editor icons; no external icon-font dependency. */
class UiIcons {
    public static function draw(target:h2d.Graphics, kind:UiIconKind, x:Float, y:Float,
            size:Float, color:Int, alpha:Float = 1):Void {
        if (kind == None || size <= 0) return;
        var s = size;
        var cx = x + s * 0.5;
        var cy = y + s * 0.5;
        target.lineStyle(Math.max(1, s * 0.105), color, alpha);

        switch (kind) {
            case Add:
                target.moveTo(cx, y + s * 0.2); target.lineTo(cx, y + s * 0.8);
                target.moveTo(x + s * 0.2, cy); target.lineTo(x + s * 0.8, cy);
            case Trash:
                target.moveTo(x + s * 0.30, y + s * 0.30); target.lineTo(x + s * 0.35, y + s * 0.84);
                target.lineTo(x + s * 0.65, y + s * 0.84); target.lineTo(x + s * 0.70, y + s * 0.30);
                target.moveTo(x + s * 0.22, y + s * 0.28); target.lineTo(x + s * 0.78, y + s * 0.28);
                target.moveTo(x + s * 0.40, y + s * 0.18); target.lineTo(x + s * 0.60, y + s * 0.18);
            case Cube:
                target.moveTo(cx, y + s * 0.12); target.lineTo(x + s * 0.84, y + s * 0.32);
                target.lineTo(cx, y + s * 0.52); target.lineTo(x + s * 0.16, y + s * 0.32);
                target.lineTo(cx, y + s * 0.12);
                target.moveTo(x + s * 0.16, y + s * 0.32); target.lineTo(x + s * 0.16, y + s * 0.70);
                target.lineTo(cx, y + s * 0.90); target.lineTo(x + s * 0.84, y + s * 0.70);
                target.lineTo(x + s * 0.84, y + s * 0.32);
                target.moveTo(cx, y + s * 0.52); target.lineTo(cx, y + s * 0.90);
            case Search:
                target.drawCircle(x + s * 0.43, y + s * 0.42, s * 0.24, 12);
                target.moveTo(x + s * 0.61, y + s * 0.60); target.lineTo(x + s * 0.84, y + s * 0.83);
            case Play:
                target.beginFill(color, alpha);
                target.moveTo(x + s * 0.32, y + s * 0.18);
                target.lineTo(x + s * 0.78, cy);
                target.lineTo(x + s * 0.32, y + s * 0.82);
                target.lineTo(x + s * 0.32, y + s * 0.18);
                target.endFill();
            case Pause:
                target.beginFill(color, alpha);
                target.drawRoundedRect(x + s * 0.27, y + s * 0.2, s * 0.16, s * 0.6, s * 0.05);
                target.drawRoundedRect(x + s * 0.57, y + s * 0.2, s * 0.16, s * 0.6, s * 0.05);
                target.endFill();
            case Stop:
                target.beginFill(color, alpha);
                target.drawRoundedRect(x + s * 0.25, y + s * 0.25, s * 0.5, s * 0.5, s * 0.08);
                target.endFill();
            case Move:
                target.moveTo(cx, y + s * 0.12); target.lineTo(cx, y + s * 0.88);
                target.moveTo(x + s * 0.12, cy); target.lineTo(x + s * 0.88, cy);
                target.moveTo(cx, y + s * 0.12); target.lineTo(x + s * 0.40, y + s * 0.24);
                target.moveTo(cx, y + s * 0.12); target.lineTo(x + s * 0.60, y + s * 0.24);
                target.moveTo(x + s * 0.88, cy); target.lineTo(x + s * 0.76, y + s * 0.40);
                target.moveTo(x + s * 0.88, cy); target.lineTo(x + s * 0.76, y + s * 0.60);
            case Rotate:
                target.drawPie(cx, cy, s * 0.32, -2.5, 4.9, 18);
                target.moveTo(x + s * 0.72, y + s * 0.20); target.lineTo(x + s * 0.82, y + s * 0.35);
                target.lineTo(x + s * 0.65, y + s * 0.36);
            case Scale:
                target.drawRect(x + s * 0.22, y + s * 0.48, s * 0.30, s * 0.30);
                target.moveTo(x + s * 0.48, y + s * 0.52); target.lineTo(x + s * 0.82, y + s * 0.18);
                target.moveTo(x + s * 0.59, y + s * 0.18); target.lineTo(x + s * 0.82, y + s * 0.18);
                target.lineTo(x + s * 0.82, y + s * 0.41);
            case ChevronDown:
                target.moveTo(x + s * 0.24, y + s * 0.38); target.lineTo(cx, y + s * 0.64);
                target.lineTo(x + s * 0.76, y + s * 0.38);
            case ChevronRight:
                target.moveTo(x + s * 0.38, y + s * 0.24); target.lineTo(x + s * 0.64, cy);
                target.lineTo(x + s * 0.38, y + s * 0.76);
            case Console:
                target.drawRoundedRect(x + s * 0.12, y + s * 0.17, s * 0.76, s * 0.66, s * 0.08);
                target.moveTo(x + s * 0.27, y + s * 0.38); target.lineTo(x + s * 0.39, cy);
                target.lineTo(x + s * 0.27, y + s * 0.62);
                target.moveTo(x + s * 0.50, y + s * 0.64); target.lineTo(x + s * 0.70, y + s * 0.64);
            case Sliders:
                target.moveTo(x + s * 0.16, y + s * 0.28); target.lineTo(x + s * 0.84, y + s * 0.28);
                target.moveTo(x + s * 0.16, cy); target.lineTo(x + s * 0.84, cy);
                target.moveTo(x + s * 0.16, y + s * 0.72); target.lineTo(x + s * 0.84, y + s * 0.72);
                target.beginFill(color, alpha);
                target.drawCircle(x + s * 0.36, y + s * 0.28, s * 0.09, 10);
                target.drawCircle(x + s * 0.66, cy, s * 0.09, 10);
                target.drawCircle(x + s * 0.45, y + s * 0.72, s * 0.09, 10);
                target.endFill();
            case Hierarchy:
                target.moveTo(x + s * 0.30, y + s * 0.22); target.lineTo(x + s * 0.30, y + s * 0.78);
                target.moveTo(x + s * 0.30, y + s * 0.36); target.lineTo(x + s * 0.56, y + s * 0.36);
                target.moveTo(x + s * 0.30, y + s * 0.68); target.lineTo(x + s * 0.56, y + s * 0.68);
                target.beginFill(color, alpha);
                target.drawRoundedRect(x + s * 0.54, y + s * 0.25, s * 0.28, s * 0.22, s * 0.05);
                target.drawRoundedRect(x + s * 0.54, y + s * 0.57, s * 0.28, s * 0.22, s * 0.05);
                target.endFill();
            case Close:
                target.moveTo(x + s * 0.25, y + s * 0.25); target.lineTo(x + s * 0.75, y + s * 0.75);
                target.moveTo(x + s * 0.75, y + s * 0.25); target.lineTo(x + s * 0.25, y + s * 0.75);
            case Grid:
                for (i in 1...4) {
                    var p = x + s * i / 4;
                    target.moveTo(p, y + s * 0.12); target.lineTo(p, y + s * 0.88);
                    var q = y + s * i / 4;
                    target.moveTo(x + s * 0.12, q); target.lineTo(x + s * 0.88, q);
                }
            case More:
                target.beginFill(color, alpha);
                target.drawCircle(x + s * 0.25, cy, s * 0.07, 8);
                target.drawCircle(cx, cy, s * 0.07, 8);
                target.drawCircle(x + s * 0.75, cy, s * 0.07, 8);
                target.endFill();
            case None:
        }
        target.lineStyle();
    }
}
