# haml.cr

A Haml templating engine for [Crystal](https://crystal-lang.org/), inspired by the [Ruby Haml gem](https://haml.info/) ([source](https://github.com/haml/haml), [rubygems](https://rubygems.org/gems/haml)).

Templates contain Haml markup and Crystal expressions, compiled ahead of time into code that writes to an IO.

---

## Examples

```crystal
require "haml"

name = "<Reader>"
html = Haml.render_string "%p= name"
```

For interpolation inside a compile-time template string, use a non-interpolating Crystal literal:

```crystal
html = Haml.render_string %q|%p Hello #{name}|
# => "<p>Hello &lt;Reader&gt;</p>\n"
```

Use `Haml.render "views/page.html.haml"` to return a String, or
`Haml.embed "views/page.html.haml", io` to write to an existing IO. Inside a view
class, `Haml.def_to_s "views/page.html.haml"` supplies `to_s(io : IO)`. File paths are
relative to the build working directory; use `__DIR__` for absolute paths.
Templates and inline strings must be available at compile time.

`=` escapes every dynamic value using `HTML.escape`; `!=` inserts explicitly
trusted raw markup. There is no `html_safe` bypass. Attribute values always
escape. Templates themselves are trusted source code, not sandboxed user input.

See [supported syntax](docs/SYNTAX.md), [validation results](docs/VALIDATION.md),
and the programs in `examples/`. This is a starting implementation with a
documented syntax subset, not full Ruby Haml compatibility.

---

## Issues and pull requests

- This is a hobby side project.
- Issues and PRs are unlikely to be accepted.
- If you find a reproducible bug, you may file a brief issue.

---

## Development note

This project was developed extensively using AI coding tool assistance. Use at your own risk.