package boltspark.assets;

/**
 * Renderer-independent triangle mesh data produced by an importer. Plain arrays
 * keep the parsers headless-testable; `HeapsMeshFactory` turns this into an
 * `h3d.prim.Polygon` when a scene view needs geometry.
 */
typedef MeshGeometry = {
    /** Display/family name parsed from the source. */
    name:String,
    /** XYZ triples, 3 floats per vertex. */
    positions:Array<Float>,
    /** XYZ triples, one per vertex (zero-filled when absent). */
    normals:Array<Float>,
    /** UV pairs, one per vertex (zero-filled when absent). */
    uvs:Array<Float>,
    /** Triangle corner indices into the parallel vertex arrays. */
    indices:Array<Int>
};
