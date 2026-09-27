# haml.cr

## Overview

This project is a Crystal language port of the Ruby HAML gem. The goal is to make a templating engine for HTML documents. Per the Ruby gem, "It's designed to make it both easier and more pleasant to write HTML documents, by eliminating redundancy, reflecting the underlying structure that the document represents, and providing an elegant syntax that's both powerful and easy to understand."

## Ruby gem

For reference, the Ruby HAML gem and its documentation is available at:
- https://github.com/haml/haml
- https://haml.info/
- https://haml.info/docs/yardoc/

## Crystal build cache

The development build cache is intended to stay in `.crystal-cache`. This is set in `.envrc` and `.env`. Using the prefix `direnv exec .` will guarantee that this environment variable is loaded. You may check with, for example, `direnv exec . crystal env` which will print the CRYSTAL_CACHE_DIR path.

## Crystal version compatibility

This project is written as a shard (a reusable library package, like a Ruby gem) for the [Crystal programming language](https://crystal-lang.org/). The goal is to remain compatible for Crystal 1.14 and above. This environment uses `asdf` to manage versions of Crystal. The default version is specified in `.tool_versions`. A different version may be specified by setting, for example, `ASDF_CRYSTAL_VERSION=1.14.0`.

You can check this to compare, for example:

```shell
direnv exec . crystal version
ASDF_CRYSTAL_VERSION=1.14.0 direnv exec . crystal version
```

## Crystal code style

Prefer explicit `def self.method_name` definitions for class or module methods instead of `extend self`.

## Comments and Typing

For non-obvious sections of code, comments are helpful. It is especially a one or few sentence comment at the start of a new method if it isn't super clear what it's doing and why. Sometimes, on a section of code, it's useful to add a one-liner to help remind future agents or humans why that code is there.

Explicit typing for Crystal code is also helpful. In this project, this is required at method boundaries: all method arguments must be typed. All methods must have an explicit return type, even if that is just `: Nil` to indicate no return value.

Do not assume that any files in `design_docs` will be long-lived. In general they will be removed quickly. Any long-lasting knowledge to improve readability should be concisely but clearly and concretely encoded into comments in the code itself. Otherwise it will quickly become unreadable and out of date.

Comments at the top of the method must be WITHIN the method, for example:

```crystal
def my_special_method(a : Int32, b : Int32) : Int32
  # This is a short comment that explains my_special_method, what it accepts and returns, what it does, and why.
  a + b
end
```

Prefer over-commenting to under-commenting, but prefer adding multiple short and simple comments through the code, not large multi-sentence blocks, where possible.

Adding blank newlines where appropriate is also helpful. It improves readability.

## Security

### Escaping HTML

It is CRUCIAL for security that you understand the difference between inserting variables with and without HTML escaping. This helps developers using the `haml.cr` shard avoid creating XSS (cross-site scripting) vulnerabilities.

In Ruby on Rails, one may call `String#html_safe` to receive a `ActiveSupport::SafeBuffer`, which indicates that the string may be rendered in the template without HTML escaping. In the Ruby `haml` gem, a template `= "my & string"` will be rendered as "my &amp; string" because HTML escaping is automatically applied, while a template `= "my & string".html_safe` will be rendered as "my & string" because of the `#html_safe` call. The `html_safe` allows the developer to insert (trusted, known-safe) raw HTML into the document.

In the Ruby haml gem, there is also support for two different operators: `= s` and `!= s`. When `s` is a regular String (but not an `ActiveSupport::SafeBuffer`), the `= s` will do HTML escaping by default, and the `!= s` will not do HTML escaping.

The `#html_safe` concept does not exist in Crystal. This leaves us only with the `= s` and `!= s` operators. This is fine. Crystal provides several variants of the `HTML.escape` method to use for escaping HTML, and these should be used on the `= s` operator.

## Performance

### IO writes preferred

Where possible, it is preferable to use methods which write to an IO, rather than building additional intermediate String buffers, to reduce unnecessary memory allocations. In Crystal both options are often available. As a concrete example, prefer to use `HTML.escape(string : String, io: IO) : Nil` rather than `HTML.escape(string: String) : String`, because the latter creates one or more intermediate String allocations.