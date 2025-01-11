;; RUN: not wasm-opt %s -all 2>&1 | filecheck %s

(module
  (type $struct (struct (field (mut i32))))

  ;; CHECK: 8:5: error: struct.atomic.rmw memory orders must be identical
  (func $cmpxchg (param (ref null $struct))
    (struct.atomic.rmw.cmpxchg seqcst acqrel 0
      (local.get 0)
      (i32.const 1)
      (i32.const 2)
    )
  )
)