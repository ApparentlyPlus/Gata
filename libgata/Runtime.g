/*
 * Runtime.g - The ARC (automatic reference counting) runtime, expressed in Gata
 *
 * The compiler holds no literal runtime C names; it emits whatever symbol carries
 * each @intrinsic(role). This file fills the memory-management roles:
 *   obj_header - the per-object ARC header, embedded first in every managed object
 *   obj_init   - stamp a fresh object's header (refcount = 1, destructor pointer)
 *   retain     - +1 a reference
 *   release    - -1 a reference; at zero, run the destructor then free it
 * Allocation is the pure-Gata `alloc` (see Mem.g); deallocation calls _env_free
 * directly. Any managed pointer aliases its embedded header (offset 0), so
 * retain/release treat every object uniformly as a gata_obj.
 *
 * Author: u/ApparentlyPlus
 */


/*
 * obj - the ARC header. __dtor shares one C signature, void (*)(void*); obj_init's
 * parameter is declared with real `func(void*) -> void` syntax so the compiler emits
 * that typedef under its deterministic mangled name, which the field spells here so
 * the two agree without either hardcoding the other's C name. (A native type body is
 * raw C the type system doesn't see, so it can't spell the func-ptr syntax directly.)
 */
@intrinsic(obj_header)
native type obj {
    gata_Fn_void__void_p __dtor;   // every class's destructor; NULL if it has none
    size_t                __rc;    // strong reference count (GATA_RC_STATIC marks a static object)
}

/*
 * A static, never-freed object (e.g. a string literal): its refcount is a sentinel,
 * so retain/release leave it untouched and its destructor never runs. GATA_OBJ_STATIC
 * is the header initializer libgata hands the compiler for static String literals.
 */
native {
    #define GATA_RC_STATIC ((size_t)-1)
    #define GATA_OBJ_STATIC { 0, GATA_RC_STATIC }
}

/*
 * The two count operations, atomic or not.
 */
native {
    #if !defined(GATA_RC_ATOMIC) || GATA_RC_ATOMIC
    #define GATA_RC_INC(o)      __atomic_add_fetch(&(o)->__rc, 1, __ATOMIC_RELAXED)
    #define GATA_RC_DEC(o)      __atomic_sub_fetch(&(o)->__rc, 1, __ATOMIC_ACQ_REL)
    #else
    #define GATA_RC_INC(o)      (++(o)->__rc)
    #define GATA_RC_DEC(o)      (--(o)->__rc)
    #endif
}

/*
 * retain - +1 a reference (static objects are left untouched)
 */
@intrinsic(retain)
void* func retain(void* p) native {
    if (p && ((gata_obj*)p)->__rc != GATA_RC_STATIC)
        GATA_RC_INC((gata_obj*)p);
    return p;
}

/*
 * release - -1 a reference; at zero, run the destructor then free it
 */
@intrinsic(release)
void func release(void* p) native {
    if (!p) return;
    gata_obj* o = (gata_obj*)p;
    if (o->__rc == GATA_RC_STATIC) return;
    if (o->__rc == 0) return;
    if (GATA_RC_DEC(o) == 0) {
        if (o->__dtor) o->__dtor(p);
        _env_free(p);
    }
}

/*
 * obj_init - Stamp a fresh object's header: refcount = 1, destructor = dtor
 */
@intrinsic(obj_init)
void func obj_init(void* o, func(void*) -> void dtor) native {
    gata_obj* x = (gata_obj*)o;
    x->__rc = 1;
    x->__dtor = dtor;
}
