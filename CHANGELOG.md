# Changelog

---

## Unreleased

- perf: `Haml::Runtime.void_tag?`: no allocations and faster bytesize-based lookup (6.18x speedup; 0 memory allocations) (thanks @willhbr)
- perf: same for `Haml::Runtime.boolean_attribute?`
- perf: `Haml::Runtime.valid_attribute_name?`: explicit character comparisons instead of `String.includes?` (3.17x speedup) (thanks @willhbr)
- perf: `Haml::Runtime.write_preserved`: stream without intermediate allocations (4-10x speedup; 0 memory allocations) (thanks @willhbr)
- perf: compile simple fixed literal attributes at compile time when possible, avoiding `Haml::Runtime::Attributes` entirely in many cases (thanks @willhbr)
- perf: `Haml::Runtime::Attributes#collect_tokens`: use block form of String#split to avoid temporary array allocation (1.2x speedup, -20% memory)
- perf: `Haml::Runtime::Attributes#save_tokens`: reuse single-token String instance in the common n=1 case (one id or one class) (1.25x speedup, -32 bytes alloc)
- (none)

---

## 1.0.3

- more examples: partials
- improve README.md

---

## 1.0.2

- `scripts/hamlc_integration_tests` script to test `hamlc` binary

---

## 1.0.1

- `bin/prerelease_checks` script

---

## 1.0.0

- Initial release
- Add quick demo script in README.md
