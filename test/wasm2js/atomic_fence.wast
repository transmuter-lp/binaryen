(module
  (memory $0 23 256 shared)
  (func (export "atomic-fence")
    (atomic.fence)
  )
)
