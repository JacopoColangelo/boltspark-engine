package hl;

#if (hl_ver >= version("1.13.0"))
/**
	CArray is a compact array where all objects are memory aligned and stored as a single GC block.
	You must hold a reference to the CArray while any of the objects it contains is still referenced somewhere.

	LOCAL PATCH (Boltspark toolchain, 2026-11-11):
	Haxe 4.3.7's stock CArray.hx resolves element access through the native primitives
	`carray_get` / `carray_length`, which are not exported by ANY released HashLink runtime
	(verified against HashLink 1.16.0 official win64 libhl.dll and its C source; only
	`alloc_carray` and `carray_blit` exist). This made every Heaps DX12 build fail at runtime
	with "Primitive or library is missing".
	This file is adapted from the Haxe development-branch std, which compiles element access
	natively in the compiler (`untyped this[index]`) and only requires `alloc_carray`,
	which HashLink 1.16.0 provides.
 **/
abstract CArray<T>(Abstract<"hl_carray">) {

	@:arrayAccess inline function get( index : Int ) : T return untyped this[index];

	public inline function unsafeSet( index : Int, v : T ) : T return untyped this[index] = v;

	public static inline function alloc<T>( cl : Class<T>, size : Int ) : CArray<T> {
		return cast alloc_carray( (cast cl:BaseType).__type__ , size );
	}

	@:hlNative("?std","alloc_carray")
	static function alloc_carray( t : hl.Type, size : Int ) : CArray<Dynamic> {
		return null;
	}

}
#end
