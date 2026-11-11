package boltspark.ui;

/** Editable proportional editor text using the same runtime FreeType cache. */
class UiTextInput extends h2d.TextInput {
    public function new(font:h2d.Font, ?parent:h2d.Object) {
        super(font, parent);
        smooth = true;
    }
}
