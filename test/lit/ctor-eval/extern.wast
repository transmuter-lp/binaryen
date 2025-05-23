;; NOTE: Assertions have been generated by update_lit_checks.py --all-items and should not be edited.
;; RUN: wasm-ctor-eval %s --ctors=test1,test1-shared,test2,test2-shared,test3,test3-shared \
;; RUN:     --kept-exports=test1,test1-shared,test2,test2-shared,test3,test3-shared --quiet -all -S -o - | filecheck %s

(module
 ;; CHECK:      (type $array (array (mut i8)))
 (type $array (array (mut i8)))
 ;; CHECK:      (type $shared-array (shared (array (mut i8))))
 (type $shared-array (shared (array (mut i8))))

 ;; CHECK:      (type $struct (struct (field externref)))
 (type $struct (struct (field externref)))
 ;; CHECK:      (type $shared-struct (shared (struct (field (ref null (shared extern))))))
 (type $shared-struct (shared (struct (field (ref null (shared extern))))))

 (func $test1 (export "test1") (result externref)
  ;; This will remain almost the same, even though we eval it, since the
  ;; serialization of an externalized i31 is what is written here. But the add
  ;; will be evalled out.
  (extern.convert_any
   (ref.i31
    (i32.add
     (i32.const 41)
     (i32.const 1)
    )
   )
  )
 )

 (func $test1-shared (export "test1-shared") (result (ref null (shared extern)))
  ;; Same as above, but now the i31 is shared.
  (extern.convert_any
   (ref.i31_shared
    (i32.add
     (i32.const 41)
     (i32.const 1)
    )
   )
  )
 )

 (func $test2 (export "test2") (result externref)
  ;; This will be evalled into an externalization of a global.get.
  (extern.convert_any
   (array.new_fixed $array 3
    (i32.const 1)
    (i32.const 2)
    (i32.const 3)
   )
  )
 )

 (func $test2-shared (export "test2-shared") (result (ref null (shared extern)))
  ;; Same as above, but now the array is shared.
  (extern.convert_any
   (array.new_fixed $shared-array 3
    (i32.const 1)
    (i32.const 2)
    (i32.const 3)
   )
  )
 )

 (func $test3 (export "test3") (result anyref)
  ;; This will add a global that contains an externalization operation.
  (struct.new $struct
   (extern.convert_any
    (ref.i31
     (i32.const 1)
    )
   )
  )
 )

 (func $test3-shared (export "test3-shared") (result (ref null (shared any)))
  ;; Same as above, but now the struct and i31 are shared.
  (struct.new $shared-struct
   (extern.convert_any
    (ref.i31_shared
     (i32.const 1)
    )
   )
  )
 )
)

;; CHECK:      (type $4 (func (result externref)))

;; CHECK:      (type $5 (func (result (ref null (shared extern)))))

;; CHECK:      (type $6 (func (result anyref)))

;; CHECK:      (type $7 (func (result (ref null (shared any)))))

;; CHECK:      (global $ctor-eval$global (ref (exact $array)) (array.new_fixed $array 3
;; CHECK-NEXT:  (i32.const 1)
;; CHECK-NEXT:  (i32.const 2)
;; CHECK-NEXT:  (i32.const 3)
;; CHECK-NEXT: ))

;; CHECK:      (global $ctor-eval$global_1 (ref (exact $shared-array)) (array.new_fixed $shared-array 3
;; CHECK-NEXT:  (i32.const 1)
;; CHECK-NEXT:  (i32.const 2)
;; CHECK-NEXT:  (i32.const 3)
;; CHECK-NEXT: ))

;; CHECK:      (global $ctor-eval$global_2 (ref (exact $struct)) (struct.new $struct
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (ref.i31
;; CHECK-NEXT:    (i32.const 1)
;; CHECK-NEXT:   )
;; CHECK-NEXT:  )
;; CHECK-NEXT: ))

;; CHECK:      (global $ctor-eval$global_3 (ref (exact $shared-struct)) (struct.new $shared-struct
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (ref.i31_shared
;; CHECK-NEXT:    (i32.const 1)
;; CHECK-NEXT:   )
;; CHECK-NEXT:  )
;; CHECK-NEXT: ))

;; CHECK:      (export "test1" (func $test1_6))

;; CHECK:      (export "test1-shared" (func $test1-shared_7))

;; CHECK:      (export "test2" (func $test2_8))

;; CHECK:      (export "test2-shared" (func $test2-shared_9))

;; CHECK:      (export "test3" (func $test3_10))

;; CHECK:      (export "test3-shared" (func $test3-shared_11))

;; CHECK:      (func $test1_6 (type $4) (result externref)
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (ref.i31
;; CHECK-NEXT:    (i32.const 42)
;; CHECK-NEXT:   )
;; CHECK-NEXT:  )
;; CHECK-NEXT: )

;; CHECK:      (func $test1-shared_7 (type $5) (result (ref null (shared extern)))
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (ref.i31_shared
;; CHECK-NEXT:    (i32.const 42)
;; CHECK-NEXT:   )
;; CHECK-NEXT:  )
;; CHECK-NEXT: )

;; CHECK:      (func $test2_8 (type $4) (result externref)
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (global.get $ctor-eval$global)
;; CHECK-NEXT:  )
;; CHECK-NEXT: )

;; CHECK:      (func $test2-shared_9 (type $5) (result (ref null (shared extern)))
;; CHECK-NEXT:  (extern.convert_any
;; CHECK-NEXT:   (global.get $ctor-eval$global_1)
;; CHECK-NEXT:  )
;; CHECK-NEXT: )

;; CHECK:      (func $test3_10 (type $6) (result anyref)
;; CHECK-NEXT:  (global.get $ctor-eval$global_2)
;; CHECK-NEXT: )

;; CHECK:      (func $test3-shared_11 (type $7) (result (ref null (shared any)))
;; CHECK-NEXT:  (global.get $ctor-eval$global_3)
;; CHECK-NEXT: )
