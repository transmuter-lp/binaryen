;; NOTE: Assertions have been generated by update_lit_checks.py --all-items and should not be edited.

;; RUN: foreach %s %t wasm-opt --propagate-globals-globally -all -S -o - | filecheck %s
;; RUN: foreach %s %t wasm-opt --simplify-globals           -all -S -o - | filecheck %s --check-prefix SIMGB

;; Check that propagate-globals-globally propagates constants globally but not
;; to code. Also run simplify-globals for comparison, which does do that.

(module
  ;; CHECK:      (type $struct (struct (field stringref) (field stringref)))
  ;; SIMGB:      (type $struct (struct (field stringref) (field stringref)))
  (type $struct (struct stringref stringref))

  ;; CHECK:      (type $1 (func))

  ;; CHECK:      (global $A i32 (i32.const 42))
  ;; SIMGB:      (type $1 (func))

  ;; SIMGB:      (global $A i32 (i32.const 42))
  (global $A i32 (i32.const 42))

  ;; CHECK:      (global $B i32 (i32.const 42))
  ;; SIMGB:      (global $B i32 (i32.const 42))
  (global $B i32 (global.get $A))

  ;; CHECK:      (global $C i32 (i32.add
  ;; CHECK-NEXT:  (i32.const 42)
  ;; CHECK-NEXT:  (i32.const 42)
  ;; CHECK-NEXT: ))
  ;; SIMGB:      (global $C i32 (i32.add
  ;; SIMGB-NEXT:  (i32.const 42)
  ;; SIMGB-NEXT:  (i32.const 42)
  ;; SIMGB-NEXT: ))
  (global $C i32 (i32.add
    ;; Both of these can be optimized, including $B which reads from $A.
    (global.get $B)
    (global.get $A)
  ))

  ;; CHECK:      (global $D (ref string) (string.const "foo"))
  ;; SIMGB:      (global $D (ref string) (string.const "foo"))
  (global $D (ref string) (string.const "foo"))

  ;; CHECK:      (global $E (ref string) (string.const "bar"))
  ;; SIMGB:      (global $E (ref string) (string.const "bar"))
  (global $E (ref string) (string.const "bar"))

  ;; CHECK:      (global $G (ref $struct) (struct.new $struct
  ;; CHECK-NEXT:  (string.const "foo")
  ;; CHECK-NEXT:  (string.const "bar")
  ;; CHECK-NEXT: ))
  ;; SIMGB:      (global $G (ref $struct) (struct.new $struct
  ;; SIMGB-NEXT:  (string.const "foo")
  ;; SIMGB-NEXT:  (string.const "bar")
  ;; SIMGB-NEXT: ))
  (global $G (ref $struct) (struct.new $struct
    (global.get $D)
    (global.get $E)
  ))

  ;; CHECK:      (func $test (type $1)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (global.get $A)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (global.get $B)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (global.get $C)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (global.get $D)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  ;; SIMGB:      (func $test (type $1)
  ;; SIMGB-NEXT:  (drop
  ;; SIMGB-NEXT:   (i32.const 42)
  ;; SIMGB-NEXT:  )
  ;; SIMGB-NEXT:  (drop
  ;; SIMGB-NEXT:   (i32.const 42)
  ;; SIMGB-NEXT:  )
  ;; SIMGB-NEXT:  (drop
  ;; SIMGB-NEXT:   (global.get $C)
  ;; SIMGB-NEXT:  )
  ;; SIMGB-NEXT:  (drop
  ;; SIMGB-NEXT:   (string.const "foo")
  ;; SIMGB-NEXT:  )
  ;; SIMGB-NEXT: )
  (func $test
    ;; We should not change anything here: this pass propagates globals
    ;; *globally*, and not to functions. (but simplify-globals does, except for
    ;; $C which is not constant)
    (drop
      (global.get $A)
    )
    (drop
      (global.get $B)
    )
    (drop
      (global.get $C)
    )
    (drop
      (global.get $D)
    )
  )
)