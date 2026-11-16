package boltspark.engine.inspector;

/** One selectable asset reference offered by an Inspector asset property. */
class AssetOption {
    public final id:String;
    public final label:String;

    public function new(id:String, label:String) {
        this.id = id;
        this.label = label;
    }

    /** Option representing "no asset" (an empty id). */
    public static function none():AssetOption {
        return new AssetOption("", "None");
    }
}
