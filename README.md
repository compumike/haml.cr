# haml.cr

A Haml templating engine for [Crystal](https://crystal-lang.org/). Inspired by the [Ruby Haml gem](https://haml.info/) ([source](https://github.com/haml/haml), [rubygems](https://rubygems.org/gems/haml)).

Templates contain Haml markup and Crystal expressions, compiled ahead of time into code that writes to an IO.

---

## Quick Demo

1. Create a template file `haml_demo.html.haml`:

```haml
- # I'm a comment and won't be rendered into the output HTML!
%section.container
  %h1= post.title
  %h2= post.subtitle
  .content
    = post.content
```

2. Call it from your Crystal code `haml_demo.cr`:

```crystal
require "haml"

record Post, title : String, subtitle : String, content : String
my_post = Post.new(title: "Welcome to Haml", subtitle: "A nice way to write templates", content: "Ruby & Crystal love Haml!")

def my_view(post : Post) : String
  Haml.render("#{__DIR__}/haml_demo.html.haml")
end

puts my_view(example_post)
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

Please observe:

- The `&` is automatically HTML-escaped to `&amp;`.
  - (If you are viewing this README.md with a Markdown renderer, it may or may not show that, so look at the raw Markdown, or run the example yourself.)
- Just like Crystal's stdlib [ECR](https://crystal-lang.org/api/latest/ECR.html):
  - The template file is fully compiled into the binary at Crystal compile time: the template file is not read and not needed at runtime.
  - The `Haml.render` compiles the template file into a Crystal macro, so it can access in-scope variables like `post`, and run other arbitrary Crystal code.

---

## Interface

Just like Crystal's stdlib [ECR](https://crystal-lang.org/api/latest/ECR.html), there are three supported macros:

- `Haml.embed(filename, io_name)` - writes to io_name
- `Haml.render(filename)` - returns a String (i.e. it wraps `Haml.embed` in `String.build`)
- `Haml.def_to_s(filename)` - defines a `#to_s(io)` method

As shown above, using `Haml.render(filename)` from your view method is probably the most straightforward way to use Haml templates in your Crystal code.

### One-off `Haml.render_string`

A `Haml.render_string(s)` macro can be used for quick testing (but can become confusing because `#{...}` interpolation may happen before the string is passed to the macro):

```
crystal eval 'require "haml" ; puts Haml.render_string("%h1 Hello World\n%h2\n  from Crystal\n  = Crystal::VERSION")'

<h1>Hello World</h1>
<h2>
from Crystal
1.21.1
</h2>
```

### `hamlc` binary compiler

In this directory, `shards build` will build a `hamlc` binary which compiles a `.haml` file into a Crystal macro.

In general you won't need this: just use `Haml.render` in your code as shown above.

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

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     haml:
       github: compumike/haml.cr
   ```

2. Run `shards install`

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

## Author

- [compumike](https://github.com/compumike) - creator and maintainer

---

## Development note

This project was written almost entirely by AI coding agents, including an extensive test suite. Use at your own risk.