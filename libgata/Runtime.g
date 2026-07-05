// Runtime.g — the ARC (automatic reference counting) runtime, expressed in Gata.
//
// The compiler holds NO literal runtime C names. It emits whatever symbol carries
// each @intrinsic(role); this file fills the memory-management roles:
//
//   obj_header — the per-object ARC header, embedded first in every managed object
//   obj_init   — stamp a fresh object's header (refcount = 1, destructor pointer)
//   retain     — +1 a reference
//   release    — -1 a reference; at zero, run the destructor then free it
//
// Allocation is the pure-Gata `alloc` (the @intrinsic(alloc) role, see Mem.g);
// deallocation here calls the environment's `_env_free` bind directly. Because a
// pointer to any managed object aliases a pointer to its embedded header (offset 0),
// retain/release can treat every object uniformly as a `gata_obj`.

// Every class's generated destructor shares this one C signature: `void (*)(void*)`,
// taking the bare object pointer. obj_init's Gata-level parameter below is declared
// with the real `func(void*) -> void` syntax, so the compiler emits that typedef
// itself (from module.FuncPtrTypes) under its deterministic mangled name; the field
// here spells the same name so the two agree without either hardcoding the other's
// C name. (A `native type` body is raw C the type system doesn't see, so it can't
// be written as `func(void*) -> void` here directly — see Ir.cs's IrFuncPtrType /
// IrArrayType.Mangle for how that name is derived.)
@intrinsic(obj_header)
native type obj {
    gata_Fn_void__void_p __dtor;   // every class's destructor; NULL if it has none
    size_t                __rc;    // strong reference count (GATA_RC_STATIC marks a static object)
}

// A static, never-freed object (e.g. a string literal): its refcount is a sentinel,
// so retain/release leave it untouched and its destructor never runs. GATA_OBJ_STATIC
// is the obj-header initializer libgata hands the compiler for static String literals.
// `0` (not a `void*` cast) is the null-pointer-constant form valid for any pointer
// type, including a function pointer like __dtor.
native {
    #define GATA_RC_STATIC ((size_t)-1)
    #define GATA_OBJ_STATIC { 0, GATA_RC_STATIC }
}

@intrinsic(retain)
void* func retain(void* p) native {
    if (p && ((gata_obj*)p)->__rc != GATA_RC_STATIC) ((gata_obj*)p)->__rc++;
    return p;
}

@intrinsic(release)
void func release(void* p) native {
    if (!p) return;
    gata_obj* o = (gata_obj*)p;
    if (o->__rc == GATA_RC_STATIC) return;   // static object: never reaped
    if (o->__rc != 0 && --o->__rc == 0) {
        if (o->__dtor) o->__dtor(p);
        _env_free(p);
    }
}

@intrinsic(obj_init)
void func obj_init(void* o, func(void*) -> void dtor) native {
    gata_obj* x = (gata_obj*)o;
    x->__rc = 1;
    x->__dtor = dtor;
}
