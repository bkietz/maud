Zen
---

- Do not require enumeration of source files; use globs.
- Do not require specification of targets; infer these from exported modules.
- Do not require finding/linking to libraries; infer these from imported modules.
- Do not require install manifests; generate and install what's necessary.
- Do not hinder documentation; keep it *easier* than writing in forgettable places. 
- Do not lock authors into learning maud equivalents for what's already
  available in cmake; reverting to configuration is easy.
- Do not promise dependency management; there is no single best answer to this
  (and there are plenty of okay-ish answers, and a few people stuck with poor ones).

.. FIXME
  We might need to overwrite cpp:namespace in order to support extended namespace spelling
  .. cpp:namespace:: Parameter : c4::yml::ConstNodeRef

