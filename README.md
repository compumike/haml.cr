# haml.cr

A Haml templating engine for [Crystal](https://crystal-lang.org/), inspired by the [Ruby Haml gem](https://haml.info/) ([source](https://github.com/haml/haml), [rubygems](https://rubygems.org/gems/haml)).

Templates contain Haml markup and Crystal expressions, compiled ahead of time into code that writes to an IO.

---

## Demo

Create a template file `haml_demo.html.haml`:

```haml
- # I'm a comment and won't be rendered into the output HTML!
%section.container
  %h1= post.title
  %h2= post.subtitle
  .content
    = post.content
```

Call it from your Crystal code `haml_demo.cr`:

```crystal
require "haml"

record Post, title : String, subtitle : String, content : String
post = Post.new(title: "Welcome to Haml", subtitle: "A nice way to write templates", content: "Ruby & Crystal love Haml!")

puts Haml.render("haml_demo.html.haml")
```

Run it with `crystal run haml_demo.cr`. Output:

```html
<section class="container">
<h1>Welcome to Haml</h1>
<h2>A nice way to write templates</h2>
<div class="content">
Ruby &amp; Crystal love Haml!
</div>
</section>
```

Notice that the `&` is escaped to `&amp;`.

---

## Syntax

See [SYNTAX.md](docs/SYNTAX.md).

---

## Security: HTML escaping

- `=` escapes every dynamic value using `HTML.escape`.
- `!=` inserts explicitly trusted raw markup.
- There is no `html_safe` bypass like in Ruby on Rails.
- Attribute values always escape.

Templates themselves are considered to be trusted source code, not sandboxed user input.

---

## Usage

Use `Haml.render "views/page.html.haml"` to return a String, or
`Haml.embed "views/page.html.haml", io` to write to an existing IO. Inside a view
class, `Haml.def_to_s "views/page.html.haml"` supplies `to_s(io : IO)`. File paths are
relative to the build working directory; use `__DIR__` for absolute paths.
Templates and inline strings must be available at compile time.

`=` escapes every dynamic value using `HTML.escape`. `!=` inserts explicitly
trusted raw markup. There is no `html_safe` bypass. Attribute values always
escape. Templates themselves are trusted source code, not sandboxed user input.

See [supported syntax](docs/SYNTAX.md),
and the programs in `examples/`. This is a starting implementation with a
documented syntax subset, not full Ruby Haml compatibility.

---

## Key differences from Ruby Haml

See [supported syntax](docs/SYNTAX.md) for details and the [Ruby Haml reference](https://haml.info/docs/yardoc/file.REFERENCE.html) for comparison.

Some important differences:

| Feature | Difference |
| --- | --- |
| HTML escaping | `=` always HTML-escapes. `!=` always emits raw HTML. (There is no Rails-style `html_safe` bypass.) |
| Compilation | Templates compile ahead of time. Runtime template evaluation is not supported. |
| Attributes | False `data-*` and `aria-*` values render as `"false"`. |
| Object references | Object references such as `%div[object]` (which pull class and id from `object`) are unsupported. |
| HTML output | HTML5 only. Whitespace handling is simpler and may differ slightly from Ruby Haml. |
| Filters | Only `:plain`, `:escaped`, `:preserve`, `:css`, and `:javascript` are supported. CSS and JavaScript filters do not interpolate. |

---

## Issues and pull requests

- This is a hobby side project.
- Issues and PRs are unlikely to be accepted.
- If you find a reproducible bug, you may file a brief issue.

---

## Development note

This project was developed extensively using AI coding tool assistance. Use at your own risk.