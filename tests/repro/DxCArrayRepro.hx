import dx.Dx12;

/**
 * Minimal reproduction for the DX12 startup failure:
 *   "Primitive or library is missing"
 *   thrown from h3d.impl.DX12Driver.reset (DX12Driver.hx line 480)
 *
 * Isolates each native call used by DX12Driver.reset() in sequence.
 */
class DxCArrayRepro {
	static function main() {
		Sys.println("step 1: hl.CArray.alloc");
		var adesc = hl.CArray.alloc(IndirectArgumentDesc, 1);
		Sys.println("  OK");

		Sys.println("step 2: struct field write adesc[0].type = DRAW_INDEXED");
		adesc[0].type = IndirectArgumentType.DRAW_INDEXED;
		Sys.println("  OK");

		Sys.println("step 3: read back");
		Sys.println("  adesc[0].type=" + adesc[0].type);

		Sys.println("step 4: CommandSignatureDesc construction + field writes");
		var desc = new CommandSignatureDesc();
		desc.byteStride = 5 * 4;
		desc.numArgumentDescs = 1;
		desc.argumentDescs = adesc;
		Sys.println("  OK");

		Sys.println("ALL STEPS PASSED");
	}
}
