"""Per-target entry-script generators for jac-client.

Each generator in this package contributes a `_entry.js` body for one client
target (web, native, ...). Importing a generator module triggers its
self-registration via `jaclang.runtimelib.entry_generators`.
"""
