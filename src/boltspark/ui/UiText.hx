package boltspark.ui;

/** Editor text rendered from a smooth exact-size font atlas. */
class UiText extends h2d.Text {
    public function new(font:h2d.Font, ?parent:h2d.Object) {
        super(font, parent);
        smooth = true;
    }
}
