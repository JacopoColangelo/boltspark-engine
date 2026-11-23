package boltspark.engine.inspector;

/**
 * Which asset family an Inspector asset property accepts. The widget uses it
 * to stay type-aware without hard-coding any concrete asset type.
 */
enum abstract AssetType(String) from String to String {
    var MeshAsset = "mesh";
    var MaterialAsset = "material";
    /** Imported texture used by a material's albedo slot. */
    var TextureAsset = "texture";
}
