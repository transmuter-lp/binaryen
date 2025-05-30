;; NOTE: Assertions have been generated by update_lit_checks.py and should not be edited.
;; RUN: foreach %s %t wasm-opt -all --dae -S -o - | filecheck %s

(module
 ;; CHECK:      (type $"{}" (struct))
 (type $"{}" (struct))

 ;; CHECK:      (func $foo (type $0)
 ;; CHECK-NEXT:  (call $bar)
 ;; CHECK-NEXT: )
 (func $foo
  (call $bar
   (ref.i31
    (i32.const 1)
   )
  )
 )
 ;; CHECK:      (func $bar (type $0)
 ;; CHECK-NEXT:  (local $0 i31ref)
 ;; CHECK-NEXT:  (drop
 ;; CHECK-NEXT:   (local.tee $0
 ;; CHECK-NEXT:    (ref.i31
 ;; CHECK-NEXT:     (i32.const 2)
 ;; CHECK-NEXT:    )
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (local.tee $0
 ;; CHECK-NEXT:   (unreachable)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $bar (param $0 i31ref)
  (drop
   ;; after the parameter is removed, we create a nullable local to replace it,
   ;; and must update the tee's type accordingly to avoid a validation error,
   ;; and also add a ref.as_non_null so that the outside still receives the
   ;; same type as before
   (local.tee $0
    (ref.i31
     (i32.const 2)
    )
   )
  )
  ;; test for an unreachable tee, whose type must be unreachable even after
  ;; the change (the tee would need to be dropped if it were not unreachable,
  ;; so the correctness in this case is visible in the output)
  (local.tee $0
   (unreachable)
  )
 )
 ;; A function that gets a non-nullable reference that is never used. We can
 ;; still create a non-nullable local for that parameter.
 ;; CHECK:      (func $get-nonnull (type $0)
 ;; CHECK-NEXT:  (local $0 (ref $"{}"))
 ;; CHECK-NEXT:  (nop)
 ;; CHECK-NEXT: )
 (func $get-nonnull (param $0 (ref $"{}"))
  (nop)
 )
 ;; CHECK:      (func $send-nonnull (type $0)
 ;; CHECK-NEXT:  (call $get-nonnull)
 ;; CHECK-NEXT: )
 (func $send-nonnull
  (call $get-nonnull
   (struct.new $"{}")
  )
 )
)

;; Test ref.func and ref.null optimization of constant parameter values.
(module
 ;; CHECK:      (func $foo (type $1) (param $0 (ref (exact $0)))
 ;; CHECK-NEXT:  (local $1 (ref (exact $0)))
 ;; CHECK-NEXT:  (local.set $1
 ;; CHECK-NEXT:   (ref.func $a)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (block
 ;; CHECK-NEXT:   (drop
 ;; CHECK-NEXT:    (local.get $1)
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:   (drop
 ;; CHECK-NEXT:    (local.get $0)
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $foo (param $x (ref func)) (param $y (ref func))
  ;; "Use" the params to avoid other optimizations kicking in.
  (drop (local.get $x))
  (drop (local.get $y))
 )

 ;; CHECK:      (func $call-foo (type $0)
 ;; CHECK-NEXT:  (call $foo
 ;; CHECK-NEXT:   (ref.func $b)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (call $foo
 ;; CHECK-NEXT:   (ref.func $c)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $call-foo
  ;; Call $foo with a constant function in the first param, which we
  ;; can optimize, but different ones in the second.
  (call $foo
   (ref.func $a)
   (ref.func $b)
  )
  (call $foo
   (ref.func $a)
   (ref.func $c)
  )
 )

 ;; CHECK:      (func $bar (type $2) (param $0 i31ref)
 ;; CHECK-NEXT:  (local $1 nullref)
 ;; CHECK-NEXT:  (local.set $1
 ;; CHECK-NEXT:   (ref.null none)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (block
 ;; CHECK-NEXT:   (drop
 ;; CHECK-NEXT:    (local.get $1)
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:   (drop
 ;; CHECK-NEXT:    (local.get $0)
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $bar (param $x (ref null any)) (param $y (ref null any))
  ;; "Use" the params to avoid other optimizations kicking in.
  (drop (local.get $x))
  (drop (local.get $y))
 )

 ;; CHECK:      (func $call-bar (type $0)
 ;; CHECK-NEXT:  (call $bar
 ;; CHECK-NEXT:   (ref.null none)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (call $bar
 ;; CHECK-NEXT:   (ref.i31
 ;; CHECK-NEXT:    (i32.const 0)
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $call-bar
  ;; Call with nulls. Mixing nulls is fine as they all have the same type and
  ;; value. However, mixing a null with a reference stops us in the second
  ;; param.
  (call $bar
   (ref.null none)
   (ref.null none)
  )
  (call $bar
   (ref.null none)
   (ref.i31 (i32.const 0))
  )
 )

 ;; Helper functions so we have something to take the reference of.
 ;; CHECK:      (func $a (type $0)
 ;; CHECK-NEXT: )
 (func $a)
 ;; CHECK:      (func $b (type $0)
 ;; CHECK-NEXT: )
 (func $b)
 ;; CHECK:      (func $c (type $0)
 ;; CHECK-NEXT: )
 (func $c)
)

;; Test that string constants can be applied.
(module
 ;; CHECK:      (func $0 (type $0)
 ;; CHECK-NEXT:  (call $1)
 ;; CHECK-NEXT: )
 (func $0
  (call $1
   (string.const "310")
   (string.const "929")
  )
 )
 ;; CHECK:      (func $1 (type $0)
 ;; CHECK-NEXT:  (local $0 (ref string))
 ;; CHECK-NEXT:  (local $1 (ref string))
 ;; CHECK-NEXT:  (local.set $0
 ;; CHECK-NEXT:   (string.const "929")
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT:  (block
 ;; CHECK-NEXT:   (local.set $1
 ;; CHECK-NEXT:    (string.const "310")
 ;; CHECK-NEXT:   )
 ;; CHECK-NEXT:   (nop)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 (func $1 (param $0 (ref string)) (param $1 (ref string))
  ;; The parameters here will be removed, and the constant values placed in the
  ;; function.
  (nop)
 )
)
