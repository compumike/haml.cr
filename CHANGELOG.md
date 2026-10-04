# Changelog

---

## Unreleased

- perf: `Haml::Runtime.void_tag?`: no allocations and faster bytesize-based lookup (6.18x speedup; 0 memory allocations) (thanks @willhbr)
- perf: same for `Haml::Runtime.boolean_attribute?`
- perf: `Haml::Runtime.valid_attribute_name?`: explicit character comparisons instead of `String.includes?` (3.17x speedup) (thanks @willhbr)
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
