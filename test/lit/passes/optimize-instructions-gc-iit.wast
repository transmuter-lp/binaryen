;; NOTE: Assertions have been generated by update_lit_checks.py and should not be edited.

;; RUN: foreach %s %t wasm-opt --optimize-instructions --ignore-implicit-traps --enable-reference-types --enable-gc -S -o - \
;; RUN:   | filecheck %s

;; Also test trapsNeverHappen
;; RUN: foreach %s %t wasm-opt --optimize-instructions --traps-never-happen --enable-reference-types --enable-gc -S -o - \
;; RUN:   | filecheck %s --check-prefix TNH

(module
  ;; CHECK:      (type $parent (sub (struct (field i32))))
  ;; TNH:      (type $parent (sub (struct (field i32))))
  (type $parent (sub (struct (field i32))))
  ;; CHECK:      (type $child (sub $parent (struct (field i32) (field f64))))
  ;; TNH:      (type $child (sub $parent (struct (field i32) (field f64))))
  (type $child (sub $parent (struct (field i32) (field f64))))
  ;; CHECK:      (type $other (struct (field i64) (field f32)))
  ;; TNH:      (type $other (struct (field i64) (field f32)))
  (type $other  (struct (field i64) (field f32)))

  ;; CHECK:      (func $foo (type $3)
  ;; CHECK-NEXT: )
  ;; TNH:      (func $foo (type $3)
  ;; TNH-NEXT: )
  (func $foo)

  ;; CHECK:      (func $ref-cast-iit (type $4) (param $parent (ref $parent)) (param $child (ref $child)) (param $other (ref $other))
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $parent)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (local.get $child)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (ref.cast (ref $child)
  ;; CHECK-NEXT:    (local.get $parent)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (unreachable)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; TNH:      (func $ref-cast-iit (type $4) (param $parent (ref $parent)) (param $child (ref $child)) (param $other (ref $other))
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (local.get $parent)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (local.get $child)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (ref.cast (ref $child)
  ;; TNH-NEXT:    (local.get $parent)
  ;; TNH-NEXT:   )
  ;; TNH-NEXT:  )
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (unreachable)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT: )
  (func $ref-cast-iit
    (param $parent (ref $parent))
    (param $child (ref $child))
    (param $other (ref $other))

    ;; a cast of parent to parent. We can optimize this as the new type will be
    ;; valid.
    (drop
      (ref.cast (ref $parent)
        (local.get $parent)
      )
    )
    ;; a cast of child to a supertype: again, we replace with a valid type.
    (drop
      (ref.cast (ref $parent)
        (local.get $child)
      )
    )
    ;; a cast of parent to a subtype: we cannot replace the original heap type
    ;; $child with one that is not equal or more specific, like $parent, so we
    ;; cannot optimize here.
    (drop
      (ref.cast (ref $child)
        (local.get $parent)
      )
    )
    ;; a cast of child to an unrelated type: it will trap anyhow
    (drop
      (ref.cast (ref $other)
        (local.get $child)
      )
    )
  )

  ;; CHECK:      (func $ref-cast-iit-bad (type $5) (param $parent (ref $parent))
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (block (result (ref $parent))
  ;; CHECK-NEXT:    (call $foo)
  ;; CHECK-NEXT:    (local.get $parent)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (block ;; (replaces unreachable RefCast we can't emit)
  ;; CHECK-NEXT:    (drop
  ;; CHECK-NEXT:     (unreachable)
  ;; CHECK-NEXT:    )
  ;; CHECK-NEXT:    (unreachable)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; TNH:      (func $ref-cast-iit-bad (type $5) (param $parent (ref $parent))
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (block (result (ref $parent))
  ;; TNH-NEXT:    (call $foo)
  ;; TNH-NEXT:    (local.get $parent)
  ;; TNH-NEXT:   )
  ;; TNH-NEXT:  )
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (block ;; (replaces unreachable RefCast we can't emit)
  ;; TNH-NEXT:    (drop
  ;; TNH-NEXT:     (unreachable)
  ;; TNH-NEXT:    )
  ;; TNH-NEXT:    (unreachable)
  ;; TNH-NEXT:   )
  ;; TNH-NEXT:  )
  ;; TNH-NEXT: )
  (func $ref-cast-iit-bad
    (param $parent (ref $parent))

    ;; optimizing this cast away requires reordering.
    (drop
      (ref.cast (ref $parent)
        (block (result (ref $parent))
          (call $foo)
          (local.get $parent)
        )
      )
    )

    ;; ignore unreachability
    (drop
      (ref.cast (ref null $parent)
        (unreachable)
      )
    )
  )

  ;; CHECK:      (func $ref-eq-ref-cast (type $6) (param $x eqref)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (i32.const 1)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; TNH:      (func $ref-eq-ref-cast (type $6) (param $x eqref)
  ;; TNH-NEXT:  (drop
  ;; TNH-NEXT:   (i32.const 1)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT: )
  (func $ref-eq-ref-cast (param $x eqref)
    ;; we can look through a ref.cast null if we ignore traps
    (drop
      (ref.eq
        (local.get $x)
        (ref.cast (ref null $parent)
          (local.get $x)
        )
      )
    )
  )

  ;; CHECK:      (func $set-of-as-non-null (type $7) (param $x anyref)
  ;; CHECK-NEXT:  (local.set $x
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; TNH:      (func $set-of-as-non-null (type $7) (param $x anyref)
  ;; TNH-NEXT:  (local.set $x
  ;; TNH-NEXT:   (local.get $x)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT: )
  (func $set-of-as-non-null (param $x anyref)
    ;; As we ignore such traps, we can remove the ref.as here.
    (local.set $x
      (ref.as_non_null
        (local.get $x)
      )
    )
  )
)

(module
  (rec
    ;; CHECK:      (rec
    ;; CHECK-NEXT:  (type $A (sub (struct)))
    ;; TNH:      (rec
    ;; TNH-NEXT:  (type $A (sub (struct)))
    (type $A (sub (struct )))
    ;; CHECK:       (type $B (sub $A (struct (field (ref null $A)))))
    ;; TNH:       (type $B (sub $A (struct (field (ref null $A)))))
    (type $B (sub $A (struct (field (ref null $A)))))
    ;; CHECK:       (type $C (sub $B (struct (field (ref null $D)))))
    ;; TNH:       (type $C (sub $B (struct (field (ref null $D)))))
    (type $C (sub $B (struct (field (ref null $D)))))
    ;; CHECK:       (type $D (sub $A (struct)))
    ;; TNH:       (type $D (sub $A (struct)))
    (type $D (sub $A (struct )))
  )

  ;; CHECK:      (func $test (type $4) (param $C (ref $C)) (result anyref)
  ;; CHECK-NEXT:  (struct.get $C 0
  ;; CHECK-NEXT:   (local.get $C)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; TNH:      (func $test (type $4) (param $C (ref $C)) (result anyref)
  ;; TNH-NEXT:  (struct.get $C 0
  ;; TNH-NEXT:   (local.get $C)
  ;; TNH-NEXT:  )
  ;; TNH-NEXT: )
  (func $test (param $C (ref $C)) (result anyref)
    (struct.get $B 0
      (ref.cast (ref $B) ;; Try to cast a $C to its parent, $B. That always
                         ;; works, so the cast can be removed.
                         ;; Then once the cast is removed, the outer struct.get
                         ;; will have a reference with a different type,
                         ;; making it a (struct.get $C ..) instead of $B.
                         ;; But $B and $C have different types on field 0, and
                         ;; so the struct.get must be refinalized so the node
                         ;; has the expected type.
        (local.get $C)
      )
    )
  )
)
