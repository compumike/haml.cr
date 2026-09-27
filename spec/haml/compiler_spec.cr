require "../spec_helper"

describe "Haml source generation" do
  it "coalesces adjacent static HTML into one write" do
    code = Haml.compile("%p One\n%p Two\n", "x.haml", "io")
    code.should eq("io << \"<p>One</p>\\n<p>Two</p>\\n\"\nnil\n")
  end

  it "precomputes exclusively static shorthand and HTML attributes" do
    code = Haml.compile(%q|%p.one(title="x&y") Hi|, "x", "io")
    code.should_not contain("Attributes.new")
    code.should contain("&amp;")
  end

  it "does not eval even apparently constant Crystal expressions" do
    code = Haml.compile(%q|%p{title: raise("must not execute during generation")}|)
    code.should contain("must not execute during generation")
    code.should contain("Attributes.new")
  end

  it "uses body escaping for ordinary output" do
    code = Haml.compile("%p= user.name")
    code.should contain("::HTML.escape(")
    code.should contain(".to_s, __haml_io)")
  end

  it "writes raw output directly and force-escapes output" do
    Haml.compile("!= markup").should contain(").to_s(__haml_io)")
    Haml.compile("&= markup").should contain("::HTML.escape(")
  end

  it "puts the header location stack marker on its own line" do
    code = Haml.compile("- 2.times do |number|\n  = number", "view.haml")
    code.should contain("#<loc:push>\n#<loc:\"view.haml\",1,3>2.times do |number|")
  end

  it "writes attribute expressions exactly once" do
    code = Haml.compile("%p{title: unique_side_effect()}")
    code.scan(/unique_side_effect/).size.should eq(1)
  end

  it "writes interpolations exactly once" do
    code = Haml.compile(%q|Hello #{unique_side_effect()}|)
    code.scan(/unique_side_effect/).size.should eq(1)
  end

  it "does not generate a heterogeneous hash for a fixed attribute list" do
    code = Haml.compile("%p{title: name, hidden: flag, count: number}")
    code.scan(/\.add\(/).size.should eq(3)
    code.should_not contain("{title:")
  end

  it "terminates expressions before trailing comments can swallow delimiters" do
    code = Haml.compile("= name # closing comment", "comment.haml", "io")
    code.should contain("name # closing comment\n)#<loc:pop>")
  end

  it "maps an inline expression to its Haml column" do
    code = Haml.compile("%p= user.name", "view.haml", "io")
    code.should contain(%q|#<loc:"view.haml",1,5>|)
  end

  it "maps multiline attribute expressions to their physical line" do
    code = Haml.compile("%p{\n  title: name,\n}\n", "view.haml", "io")
    code.should contain(%q|#<loc:"view.haml",2,10>|)
  end

  it "can omit source-location directives for inspection" do
    options = Haml::Options.new(source_locations: false)
    Haml.compile("%p= name", "x", "io", options).should_not contain("#<loc:")
  end

  it "is deterministic, including generated temporary names" do
    source = %q|%p.base{class: classes}(title="#{name}")= title|
    Haml.compile(source).should eq(Haml.compile(source))
  end

  it "can regenerate from the same AST without consuming attributes" do
    ast = parse_haml("%p.one{title: name}")
    generator = Haml::Generator.new("io", Haml::Options.new, "same")
    first = generator.generate(ast)
    generator.generate(ast).should eq(first)
    ast.children.first.as(Haml::AST::Tag).attributes.size.should eq(2)
  end

  it "uses different temporary namespaces for different output variables" do
    left = Haml.compile("%p{title: name}", "x", "left")
    right = Haml.compile("%p{title: name}", "x", "right")
    left.match(/__haml_[0-9a-f]+_1/).not_nil![0].should_not eq(right.match(/__haml_[0-9a-f]+_1/).not_nil![0])
  end

  ["bad.name", "io; evil", "io\n", "123", "", "end", "self", "nil", "_", "__DIR__"].each do |name|
    it "rejects invalid IO identifier #{name.inspect}" do
      expect_raises(ArgumentError) { Haml.compile("%p hi", "x", name) }
    end
  end

  it "rejects case with no branches during generation" do
    expect_raises(Haml::SyntaxError, /case requires/) { Haml.compile("- case value") }
  end

  it "does not run code hidden in HTML comments" do
    expect_raises(Haml::UnsupportedSyntax, /static/) { Haml.compile("/\n  = side_effect()") }
  end

  it "rejects interpolated HTML-comment bodies" do
    expect_raises(Haml::UnsupportedSyntax, /static/) { Haml.compile(%q|/
  text #{value}|) }
  end

  it "rejects nested HTML comments" do
    expect_raises(Haml::UnsupportedSyntax) { Haml.compile("/\n  / nested") }
  end

  it "rejects dynamic attributes inside an HTML comment" do
    expect_raises(Haml::UnsupportedSyntax, /dynamic attributes/) { Haml.compile("/\n  %p{title: name}") }
  end

  it "rejects the HTML-comment terminator in nested text" do
    expect_raises(Haml::SyntaxError) { Haml.compile("/\n  text -->") }
  end

  it "reports Haml syntax errors using filename, line, and column" do
    ex = expect_raises(Haml::SyntaxError) { Haml.compile("%div\n    %p x", "example.haml") }
    ex.message.to_s.should contain("example.haml:2:")
  end

  it "preserves a literal compiler-directive-looking string as data" do
    code = Haml.compile(%q|%p #<loc:"fake.haml",100,1> #{1}|, "real.haml")
    code.should contain(%q|#<loc:\"fake.haml\",100,1>|)
    code.should contain(%q|#<loc:"real.haml",1,|)
  end
end

describe Haml::Options do
  it "has explicit HTML5-oriented defaults" do
    options = Haml::Options.new
    options.indent_width.should eq(2)
    options.source_locations.should be_true
    options.max_depth.should eq(128)
  end

  it "rejects unusable indentation and depth bounds" do
    expect_raises(ArgumentError) { Haml::Options.new(indent_width: 0) }
    expect_raises(ArgumentError) { Haml::Options.new(indent_width: 9) }
    expect_raises(ArgumentError) { Haml::Options.new(max_depth: 0) }
    expect_raises(ArgumentError) { Haml::Options.new(max_depth: 257) }
  end
end
