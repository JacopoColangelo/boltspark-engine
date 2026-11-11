package boltspark.ui;

/** Proportional editor text rasterized and cached by FreeType at its exact size. */
class UiText extends h2d.Text {
    public function new(font:h2d.Font, ?parent:h2d.Object) {
        super(font, parent);
        smooth = true;
    }
}
