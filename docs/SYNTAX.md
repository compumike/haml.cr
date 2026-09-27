# Supported syntax and intentional differences

This is an initial Haml-to-Crystal implementation, not a claim of full Ruby Haml compatibility. Expressions are Crystal.

## Elements, nesting, and literal text

```haml
!!!
%html(lang="en")
  %body
    %main#content
      .card.featured
        %h1 Hello
        %p Authored <em>markup</em> and &copy; entities are literal.
```

Tags begin with `%`. A leading `.class` or `#id` implies `div`. Shorthand classes and IDs can be combined.

Structural indentation uses exactly two spaces per level unless configured otherwise. Structural tabs are rejected. Ordinary blank lines are ignored.

Tag names start with an ASCII letter and can contain ASCII letters, numbers, underscores, hyphens, and colons. Shorthand class/ID tokens allow alphanumerics, underscore, hyphen, and colon. Use an attribute string for CSS class names containing other punctuation, for example `class: "w-1/2 w-[32px]"`.

A tag can have inline text/output or nested children, not both. The one special inline-plus-children form is a tag whose inline output is an explicit capture helper `do` block.

`!!!` and `!!! 5` emit the HTML5 doctype. Other doctype modes are rejected.

Known HTML void elements, such as `%br`, `%img`, and `%input`, do not get closing tags and cannot have content. A trailing slash marks an explicitly childless tag. For a **non-void** HTML element, `%div/` becomes `<div></div>`, not `<div/>`. XML serialization is not implemented. In an SVG subtree, paired empty elements are still valid; the renderer does not implement a separate XML mode.

## Output and interpolation

| Spelling | Meaning |
|---|---|
| `%p= expression` or `= expression` | Output a Crystal value; escape all body values. |
| `%p!= expression` or `!= expression` | Explicitly raw body output. |
| `%p&= expression` or `&= expression` | Explicit HTML escaping (same as `=` for values). |
| `~ expression` | Escape body value, then encode its newlines as `&#10;`. |
| `Text #{expression}` | Literal authored text plus escaped dynamic substitutions. |
| `== Text #{expression}` | Explicit interpolated text; **not raw expression output**. |
| `& Text #{expression}` / `&== ...` | Escape both authored text and substitutions. |
| `! Text #{expression}` / `!== ...` | Literal text with raw substitutions. |
| `\%not_a_tag` | Escape a leading Haml marker into literal text. |
| `Text \#{expression}` | Literal interpolation syntax. |

The operators also work as tag content where shown in the specs. A value's normal Crystal `to_s` behavior applies; nil becomes empty text and numbers stringify normally.

Ordinary text is trusted markup. For example, with `name = "<Mike>"`:

```haml
%p Hello <em>#{name}</em> &copy;
```

produces:

```html
<p>Hello <em>&lt;Mike&gt;</em> &copy;</p>
```

The implementation escapes the substitution, not the concatenation of substitution and authored markup. An explicit escaped-text form changes that policy.

There is no `html_safe` / `SafeHTML` bypass. `=` and `&=` always escape dynamic values. Use `!=` explicitly for trusted markup. Attributes always escape their values.

## Attributes

### Hash-style syntax

```haml
%a.button{href: user.url, title: user.name} Profile
%input{disabled: disabled?, value: value}
%p{:title => name, "data-key" => key}
%button{"@click": "go()", ":class": "active"} Go
```

The outer list is parsed by Haml. Each value is an opaque Crystal expression. Supported static key spellings include a bare key followed by `:`, a legacy `:key =>`, and a quoted key with `:` or `=>`.

**String semantics differ between forms.** In a hash-style expression, `'x'` is a Crystal character literal. `'several characters'` is not a Crystal string. Use `"several characters"` or an appropriate Crystal percent literal. The library does not translate Ruby strings.

Multiline groups and trailing commas are supported:

```haml
%a{
  href: user.url,
  title: # A leading comment on the value is permitted.
    user.name,
  class: ["button", active && "active"],
} Profile
```

A value may contain nested groups, strings, regexes, and comments within the scanner's supported envelope. A comma inside them is not an attribute separator.

### HTML-style syntax

```haml
%a(href=url title="Hello") Go
%a(title='Hi #{name}') Go
%input(disabled)
%p(title=("Hello " + name))
```

Both single- and double-quoted **HTML-style** values are Haml strings; both can interpolate. They are not Crystal character/string literal expressions. Supported escapes are `\n`, `\r`, `\t`, `\\`, `\'`, `\"`, and escaped interpolation. Use a hash-style Crystal expression for richer native escapes such as Unicode escape sequences.

An unquoted value ends at top-level whitespace. Use parentheses around an expression containing spaces, or use the hash style. Whitespace separates attributes; `title="x"alt="y"` is rejected. Bare attributes have a true value.

Both attribute styles can appear on one tag. Entries are processed in authored order. This ordering is intentional and may differ from Ruby Haml's merging/order rules in some versions.

### Classes and IDs

```haml
.item{class: ["wide", active && "active", nil, false]}
#item{id: [item.id, "detail"]}
```

Class lists recursively flatten Arrays/Tuples, omit nil/false, split String tokens, and deduplicate in first-seen order. IDs flatten, omit nil/false, and join with `_` without deduplication. Zero and the String `"false"` are retained. A later false class does not erase a shorthand class.

There is no `%div[object]` ActiveModel-style object reference. Use explicit `class:` and `id:` helpers instead.

### Booleans, nil, data, and ARIA

Presence/absence HTML attributes such as `disabled` are bare when true and omitted when false/nil. Textual values are retained. Consequently, `disabled: "false"` still emits a present boolean attribute; use `disabled: false` to omit it.

For ordinary attributes, actual Boolean values become `"true"` and `"false"`. Nil omits the attribute. A later ordinary value replaces an earlier value; a later nil removes it.

```haml
%p{data: {item_id: 7, nested: {ready: false}}, aria: {hidden: false}}
```

becomes:

```html
<p data-item-id="7" data-nested-ready="false" aria-hidden="false"></p>
```

Nested Hash/NamedTuple data/ARIA values flatten recursively. Underscores in nested subkeys become hyphens. Empty or structurally invalid keys raise errors. Recursion is bounded.

**Deliberate Ruby Haml difference:** data/ARIA false values remain explicit strings. They are not silently omitted. There is no compatibility switch in this draft.

### Dynamic attribute maps

```haml
%p.base{**attributes, title: title}
```

`attributes` must be a Crystal Hash or NamedTuple. Splats participate in the same merging, name validation, escaping, and evaluation-order rules. Unqualified `%p{attributes}` and arbitrary hash-object argument syntax are not supported; use `**attributes`.

Every expression is evaluated once as an argument. A helper's internal computation and conversion methods may, of course, do their own work.

Attribute names are validated, not merely escaped. Values are quoted and escaped exactly once. There is no type-based bypass.

## Crystal code and control flow

```haml
- name = user.name
- if user.active?
  %p= name
- elsif user.pending?
  %p Pending
- else
  %p Inactive
```

```haml
%ul
  - users.each do |user|
    - next unless user.visible?
    %li= user.name
```

Supported indentation-managed block openers are `if`, `unless`, `while`, `until`, `case`, `begin`, and calls ending in `do` with optional block parameters. Branches must be adjacent to and valid for their actual owner. Crystal statements such as assignments, `next`, and `break` are otherwise passed through.

Use whitespace after a control keyword. Write the opener on its own logical line and its template children beneath it. Full Crystal one-line control grammar is not promised. Do not supply `- end`; indentation closes the construct.

`case` accepts either sibling or indented `when`/`in`/`else` branches. Mixing `when` and `in` is rejected. For `in`, follow Crystal's own exhaustiveness and pattern rules; Haml does not replace those checks.

```haml
- begin
  - perform_operation
  %p Success
- rescue error
  %p= error.message
- ensure
  %p Finished
```

Assignment to an indentation-managed block, imports, and type/method definitions are excluded. Keep those in `.cr` files. Arbitrary Ruby expressions, Rails helpers, and dynamic `eval` are not provided.

## Supported lexical envelope

Embedded Crystal is not parsed semantically, but the frontend recognizes its boundaries. Supported forms include nested `()`, `[]`, `{}`; quoted strings/characters and command literals; nested `#{...}`; percent strings/string arrays/symbol arrays/regexes/commands with supported Crystal delimiters; and line comments.

`%q` follows Crystal's non-escaping behavior, including its delimiter treatment. `%W` supports interpolation when the host Crystal compiler supports it (tested on 1.21; unavailable on 1.14). Hash-style strings use Crystal rules, while HTML-style quoted strings use the smaller Haml convention above.

In a slash regex, escape literal slashes even inside a character class, for example `/[\/]/`. Crystal's lexer terminates an unescaped slash before regex character-class semantics apply.

Slash regexes work in operand positions, for example `text.match(/pattern/)`. Spaced `a / b`, unspaced `a/b`, and integer `a // b` division are supported. Ambiguous `method /pattern/` is rejected; use `method(/pattern/)` or `method(%r(pattern))`.

Heredocs, explicit `{{...}}` / `{%...%}` macro bodies, and the full host-language continuation grammar are not supported. Where punctuation is ambiguous, use a clearer equivalent or move the expression into a helper. The scanner is not a substitute for Crystal syntax/type checking.

### Multiline expressions

Use an open group or quoted literal to continue onto following physical lines:

```haml
= (
  subtotal +
  tax
)
```

Hash and HTML attribute groups can also span lines. Continuation is bounded at 256 lines and nesting is bounded by options. A trailing pipe, trailing backslash outside a recognized literal, or comma without an open grouping construct is not a supported Haml continuation mechanism.

## Comments

`-#` drops its line and nested subtree without evaluating it. `/` emits a static HTML comment. Nested static tags/text in an HTML comment are permitted, but code, dynamic values/attributes, nested HTML comments, and invalid `--` content are rejected. HTML comments are not an execution-suppression mechanism for arbitrary Crystal code; use `-#` for that.

Internet Explorer conditional-comment syntax is not implemented.

## Filters

| Filter | Behavior |
|---|---|
| `:plain` | Raw authored text with escaped dynamic interpolations. |
| `:escaped` | Escape authored text and dynamic interpolations. |
| `:preserve` | Preserve body markup policy and encode newlines as `&#10;`. |
| `:css` | Wrap literal authored content in `<style>`; no interpolation. |
| `:javascript` | Wrap literal authored content in `<script>`; no interpolation. |

Filter content is indented beneath its header. The baseline indentation is removed; further indentation and internal blank lines are preserved. The raw filter parser is not the ordinary Haml tag parser.

`:markdown`, `:sass`, `:scss`, `:ruby`, `:crystal`, `:erb`, and other filters are not implemented. They can be proposed later with explicit trust, dependency, and escaping rules. A `:crystal` code filter is not silently substituted for Ruby Haml's `:ruby`.

## Capture and composition

An output helper with a `do` block gets a block whose return value is a rendered String:

```haml
!= card(title) do
  %p= message
```

A helper returning markup returns a String, after escaping its own dynamic fields. Insert that markup with `!=`. See `examples/capture.cr`. There is no Rails/global output buffer. Returning an ordinary String under `=` escapes it. Helpers may yield values into the block parameters.

Typed view objects, helpers, and compile-time macro calls can serve as partials. Arbitrary runtime filenames containing newly loaded Crystal are not supported.

## Whitespace

This draft emits no pretty indentation. It normally places an LF after rendered nodes and at structural boundaries around nested content. Blank ordinary input lines do not add extra output.

`<` removes immediate **structural** inner separators; `>` removes structural outer adjacency separators. Their combinations are supported. They do not trim spaces/newlines already contained in a runtime value and do not inspect previously written IO bytes.

This is narrower than Ruby Haml's full whitespace-removal behavior. Control flow also limits structural adjacency analysis. In a loop whose final structural separator is suppressed, that choice applies on every iteration. These rules are covered by exact-output fixtures.

There is no automatic compatibility mode for all `pre`, `textarea`, or historical Haml whitespace behaviors. Use explicit forms and test the text nodes your application depends on.

## Diagnostics and limits

Frontend errors contain filename, line, and column. Generated expressions include ECR-style Crystal source-location directives. Native filename/line mapping is checked by `scripts/integration`. Later raw-filter columns may refer to dedented content; this is a recorded limitation, not an exact-source-map claim.

`--check` validates only the Haml translation path. Undefined application methods, invalid Crystal strings, type mismatches, and some unsupported host-language grammar are detected only by a real Crystal compilation.

Templates are trusted source. Nesting and continuation limits protect the implementation from accidental pathological input; they do not make it safe to execute hostile templates.
