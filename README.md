# haml.cr

A compile-time Haml templating engine for [Crystal](https://crystal-lang.org/). Inspired by the [Ruby Haml gem](https://haml.info/) ([source](https://github.com/haml/haml), [rubygems](https://rubygems.org/gems/haml)).

A template contains Haml markup and Crystal expressions, compiled ahead of time into a Crystal macro that writes to an IO (`Haml.embed(filename, io_name)`) or returns a string (`Haml.render(filename)`).

---

## Table of Contents

- [Quick demo](#quick-demo)
- [Interface](#interface)
- [Syntax](#syntax)
  - [Interpolation and HTML escaping](#interpolation-and-html-escaping)
  - [If/else](#ifelse)
  - [Loops](#loops)
  - [HTML attributes](#html-attributes)
  - [CSS Classes and Styles](#css-classes-and-styles)
  - [Multiline Crystal](#multiline-crystal)
  - [Including partial templates](#including-partial-templates)
- [Installation](#installation)
- [Key differences from Ruby Haml](#key-differences-from-ruby-haml)
- [Issues and pull requests](#issues-and-pull-requests)
- [Author](#author)
- [Development note](#development-note)

---

## Quick demo

1. Create a template file `haml_demo.html.haml`:

```haml
- # I'm a comment and won't be rendered into the output HTML!
%section.container
  %h1= post.title
  %h2= post.subtitle
  .content
    = post.content
```

2. Call `Haml.render` from your Crystal code `haml_demo.cr`:

```crystal
require "haml"

record Post, title : String, subtitle : String, content : String
example_post = Post.new(title: "Welcome to Haml", subtitle: "A nice way to write templates", content: "Ruby & Crystal love Haml!")

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

### Macros

Just like Crystal's stdlib [ECR](https://crystal-lang.org/api/latest/ECR.html), there are three supported macros:

- `Haml.embed(filename, io_name)` - writes to io_name
- `Haml.render(filename)` - returns a String (i.e. it wraps `Haml.embed` in `String.build`)
- `Haml.def_to_s(filename)` - defines a `#to_s(io)` method

As shown above, using `Haml.render(filename)` from your view method is probably the most straightforward way to use Haml templates in your Crystal code.

### One-off `Haml.render_string`

A `Haml.render_string(s)` macro can be used for quick testing (but can become confusing because `#{...}` interpolation may happen before the string is passed to the macro):

```shell
crystal eval 'require "haml" ; puts Haml.render_string("%h1 Hello World\n%h2\n  from Crystal\n  = Crystal::VERSION")'
```

```html
<h1>Hello World</h1>
<h2>
from Crystal
1.21.1
</h2>
```

### `hamlc` binary compiler

In this directory, `shards build` will build a `hamlc` binary which compiles a `.haml` file into a Crystal macro:

```shell
hamlc --no-locations examples/haml_demo.html.haml
```

outputs:

```crystal
__haml_io << "<section class=\"container\">\n<h1>"
::HTML.escape((post.title
).to_s, __haml_io)
__haml_io << "</h1>\n<h2>"
::HTML.escape((post.subtitle
).to_s, __haml_io)
__haml_io << "</h2>\n<div class=\"content\">\n"
::HTML.escape((post.content
).to_s, __haml_io)
__haml_io << "\n</div>\n</section>\n"
nil
```

In general you won't need this: just use `Haml.render` in your code as shown above.

---

## Syntax

See [SYNTAX.md](docs/SYNTAX.md). Quick overview:

### Interpolation and HTML escaping

- `=` escapes every dynamic value using `HTML.escape`.
- `!=` inserts explicitly trusted raw markup.
- There is no `html_safe` bypass like in Ruby on Rails.
- Attribute values always escape.

#### Examples

```crystal
str = "A&B"
```

| Haml input | HTML output | Notes |
|---|---|---|
| `%p Hello A&B` | `<p>Hello A&B</p>` | your text passes through unescaped |
| `%p Hello A&amp;B` | `<p>Hello A&amp;B</p>` | |
| `%p Hello #{str}` | `<p>Hello A&amp;B</p>` | `#{...}` is interpolated and escaped |
| `<p>Hello #{str}</p>` | `<p>Hello A&amp;B</p>` | your own HTML tags + escaped interpolated expressions |
| `%p& Hello A&B` | `<p>Hello A&amp;B</p>` | the `&` forces escaping even on your own text |
| `%p= str` | `<p>A&amp;B</p>` | |
| `%p!= str` | `<p>A&B</p>` | `!=` unsafely inserts raw output. (Caution: XSS risk.) |

The `#{str}` and `= str` forms will be the ones you use most frequently. Save `!=` for when you want to insert pre-escaped content (such as raw HTML).

### If/else

```haml
%p
  Coin flip:
  %strong
    - if Random.rand >= 0.5
      Heads
    - else
      Tails
```

### Loops

```haml
%ul
  - entries.each do |entry|
    %li= entry.title
```

### HTML attributes

```haml
%a{href: entry.url, target: "_blank"}
  = entry.title
```

Multi-line attributes are supported:

```haml
%a{
  href: entry.url,
  target: "_blank"
}
  = entry.title
```

### CSS Classes and Styles

```haml
%h2#my_id Subheading with an ID

%h2.mb-0.fw-bold#another_id With classes and ID

%h2{class: ["mb-0", "fw-bold", dynamic_class], id: dynamic_id} With Crystal expressions to set class and ID

%div.container
-# is the same as
.container
```

### Multiline Crystal

Multiline Crystal interpolated strings:

```haml
- value = "Crystal expression"
.example-1
  =%(
    This entire line, including its dynamically interpolated #{value}, will be HTML-escaped.

    And this #{4 - 3} too.
  )

.example-2
  !=%(
    This entire line, including its dynamically interpolated #{value}, will NOT be HTML-escaped. (XSS risk!)

    And this #{4 - 3} too.
  )
```

Multiline inline Crystal code (notice `=` vs. `!=` vs. `-`):

```haml
.example-1
  = (
    now_1 = Time.utc
    # The value will be HTML-escaped and inserted into the div:
    now_1 + 1.hour
  )

.example-2
  != (
    now_2 = Time.utc
    # The value NOT be HTML-escaped, and will be inserted RAW into the div: (XSS risk!)
    now_2 + 1.hour
  )

.example-3
  - (
    now_3 = Time.utc
    # The value will not be inserted.
    now_3 + 1.hour
  )
  = now_3 # but the value can be used later (will not have 1.hour added to it)
```

### Including partial templates

In `fruits.html.haml`:

```
- fruits.each do |fruit|
  != Haml.render("#{__DIR__}/_fruit.html.haml")
```

In `_fruit.html.haml`:

```
.btn.mb-2{id: "fruit_#{fruit}"}
  = fruit
```

Render it:

```crystal
require "haml"
fruits = ["apple", "banana", "peach"]
puts Haml.render("#{__DIR__}/fruits.html.haml")
```

Outputs:

```html
<div class="btn mb-2" id="fruit_apple">
apple
</div>

<div class="btn mb-2" id="fruit_banana">
banana
</div>

<div class="btn mb-2" id="fruit_peach">
peach
</div>
```

Note that `__DIR__` in  `Haml.render("#{__DIR__}/fruits.html.haml")` is used to tell the compiler that `fruits.html.haml` is in the same directory as this file. In your project, you can just specify paths from the build root, such as `Haml.render("src/templates/fruits.html.haml")`.

(Advanced: to reduce String allocations, it is possible to avoid having the partial build its own intermediate String by instead passing it the same IO name as the parent, and using, for example, `!= Haml.embed("_fruit.html.haml", __haml_io)` in place of `!= Haml.render(...)`.)

---

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     haml:
       github: compumike/haml.cr
   ```

2. Run `shards install`

3. Add `require "haml"`

4. Call `Haml.render("src/templates/my_template.html.haml")`

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