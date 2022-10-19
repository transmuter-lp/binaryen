;; NOTE: Assertions have been generated by update_lit_checks.py --all-items and should not be edited.

;; Check that array types and operations are emitted properly in the binary format.

;; RUN: wasm-opt %s -all -S -o - | filecheck %s
;; RUN: wasm-opt %s -all --roundtrip -S -o - | filecheck %s --check-prefix=ROUNDTRIP

;; Check that we can roundtrip through the text format as well.

;; RUN: wasm-opt %s -all -S -o - | wasm-opt -all -S -o - | filecheck %s

(module
 (type $byte-array (array (mut i8)))
 ;; CHECK:      (type $arrayref_=>_i32 (func (param arrayref) (result i32)))

 ;; CHECK:      (type $ref|array|_=>_i32 (func (param (ref array)) (result i32)))

 ;; CHECK:      (type $nullref_=>_i32 (func (param nullref) (result i32)))

 ;; CHECK:      (func $len (param $a (ref array)) (result i32)
 ;; CHECK-NEXT:  (array.len
 ;; CHECK-NEXT:   (local.get $a)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 ;; ROUNDTRIP:      (type $arrayref_=>_i32 (func (param arrayref) (result i32)))

 ;; ROUNDTRIP:      (type $ref|array|_=>_i32 (func (param (ref array)) (result i32)))

 ;; ROUNDTRIP:      (type $nullref_=>_i32 (func (param nullref) (result i32)))

 ;; ROUNDTRIP:      (func $len (param $a (ref array)) (result i32)
 ;; ROUNDTRIP-NEXT:  (array.len
 ;; ROUNDTRIP-NEXT:   (local.get $a)
 ;; ROUNDTRIP-NEXT:  )
 ;; ROUNDTRIP-NEXT: )
 (func $len (param $a (ref array)) (result i32)
  ;; TODO: remove the unused type annotation
  (array.len $byte-array
   (local.get $a)
  )
 )

 ;; CHECK:      (func $impossible-len (param $none nullref) (result i32)
 ;; CHECK-NEXT:  (array.len
 ;; CHECK-NEXT:   (local.get $none)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 ;; ROUNDTRIP:      (func $impossible-len (param $none nullref) (result i32)
 ;; ROUNDTRIP-NEXT:  (array.len
 ;; ROUNDTRIP-NEXT:   (local.get $none)
 ;; ROUNDTRIP-NEXT:  )
 ;; ROUNDTRIP-NEXT: )
 (func $impossible-len (param $none nullref) (result i32)
  (array.len $byte-array
   (local.get $none)
  )
 )

 ;; CHECK:      (func $unreachable-len (param $a arrayref) (result i32)
 ;; CHECK-NEXT:  (array.len
 ;; CHECK-NEXT:   (unreachable)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 ;; ROUNDTRIP:      (func $unreachable-len (param $a arrayref) (result i32)
 ;; ROUNDTRIP-NEXT:  (unreachable)
 ;; ROUNDTRIP-NEXT: )
 (func $unreachable-len (param $a arrayref) (result i32)
  (array.len $byte-array
   (unreachable)
  )
 )

 ;; CHECK:      (func $unannotated-len (param $a arrayref) (result i32)
 ;; CHECK-NEXT:  (array.len
 ;; CHECK-NEXT:   (local.get $a)
 ;; CHECK-NEXT:  )
 ;; CHECK-NEXT: )
 ;; ROUNDTRIP:      (func $unannotated-len (param $a arrayref) (result i32)
 ;; ROUNDTRIP-NEXT:  (array.len
 ;; ROUNDTRIP-NEXT:   (local.get $a)
 ;; ROUNDTRIP-NEXT:  )
 ;; ROUNDTRIP-NEXT: )
 (func $unannotated-len (param $a arrayref) (result i32)
  (array.len
   (local.get $a)
  )
 )
)