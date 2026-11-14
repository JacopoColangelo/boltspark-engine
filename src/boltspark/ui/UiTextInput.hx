package boltspark.ui;

/** Editable editor text using the same smooth exact-size font atlas. */
class UiTextInput extends h2d.TextInput {
    public function new(font:h2d.Font, ?parent:h2d.Object) {
        super(font, parent);
        smooth = true;
    }
}
