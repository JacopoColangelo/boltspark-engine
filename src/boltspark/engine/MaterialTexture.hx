package boltspark.engine;

/** An imported texture offered as a material albedo map. */
typedef MaterialTexture = {
    /** Project-relative texture source, used as the stable asset id. */
    id:String,
    /** Display label for Inspector pickers. */
    label:String,
    /** Project-relative source path. */
    source:String
};
