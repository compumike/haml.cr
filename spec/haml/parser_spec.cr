require "../spec_helper"

describe Haml::Parser do
  it "parses a document and nested tag tree" do
    document = parse_haml("%ul\n  %li One\n  %li Two\n")
    document.children.size.should eq(1)
    list = document.children.first.as(Haml::AST::Tag)
    list.name.should eq("ul")
    list.children.size.should eq(2)
    list.children.first.location.line.should eq(2)
    list.children.first.location.column.should eq(3)
  end

  it "parses implicit divs and shorthand in authored order" do
    tag = parse_haml(".one#two.three").children.first.as(Haml::AST::Tag)
    tag.name.should eq("div")
    tag.attributes.map(&.name).should eq(["class", "id", "class"])
  end

  it "recognizes interpolation beginning a plain-text line" do
    parse_haml(%q|#{name} hello|).children.first.should be_a(Haml::AST::Text)
  end

  it "normalizes CRLF and accepts a UTF-8 BOM" do
    parse_haml("\uFEFF%ul\r\n  %li One\r\n").children.first.as(Haml::AST::Tag).children.size.should eq(1)
  end

  it "ignores ordinary blank lines" do
    parse_haml("\n%p A\n\n%p B\n\n").children.size.should eq(2)
  end

  it "supports a configured indentation width" do
    parse_haml("%ul\n    %li x", 4).children.first.as(Haml::AST::Tag).children.size.should eq(1)
  end

  it "discards commented-out malformed Haml and Crystal" do
    source = "-# do not parse\n   :unknown\n           %p{broken\n%p Kept"
    parse_haml(source).children.size.should eq(1)
  end

  it "ignores spaced code comments without parsing their contents" do
    {"- # I am a comment", "-   #", "-\t# malformed ( \" |"}.each do |comment|
      parse_haml(comment).children.should be_empty
      document = parse_haml("#{comment}\n%p Kept")
      document.children.size.should eq(1)
      document.children.first.location.line.should eq(2)
    end
  end

  it "does not discard indented content beneath a spaced code comment" do
    expect_raises(Haml::SyntaxError, /unexpected indentation/) do
      parse_haml("- # comment\n  %p nested")
    end
  end

  it "keeps raw filter indentation and blank lines" do
    filter = parse_haml(":plain\n  one\n     two\n\n%p next").children.first.as(Haml::AST::Filter)
    filter.text.should eq("one\n   two\n\n")
  end

  it "parses multiline attribute groups" do
    tag = parse_haml("%p{\n  title: name,\n  class: [\"one\", \"two\"],\n} Hello").children.first.as(Haml::AST::Tag)
    tag.attributes.size.should eq(2)
    tag.attributes.first.expression.location.line.should eq(2)
    tag.attributes.first.expression.source.should eq("name")
  end

  it "parses multiline output expressions" do
    output = parse_haml("= (\n  1 + 2\n)").children.first.as(Haml::AST::Output)
    output.expression.source.should eq("(\n  1 + 2\n)")
  end

  it "attaches sibling branches to the immediately preceding block" do
    root = parse_haml("- if active\n  %p yes\n- elsif pending\n  %p maybe\n- else\n  %p no")
    condition = root.children.first.as(Haml::AST::Code)
    condition.kind.if?.should be_true
    condition.branches.map(&.keyword).should eq(["elsif", "else"])
    root.children.size.should eq(1)
  end

  it "does not confuse nested branches with outer branches" do
    root = parse_haml("- if a\n  - if b\n    %p inner\n  - else\n    %p other\n- else\n  %p outer")
    outer = root.children.first.as(Haml::AST::Code)
    outer.branches.size.should eq(1)
    outer.children.first.as(Haml::AST::Code).branches.size.should eq(1)
  end

  it "supports indented case branches" do
    owner = parse_haml("- case value\n  - when 1\n    %p one\n  - else\n    %p other").children.first.as(Haml::AST::Code)
    owner.children.should be_empty
    owner.branches.map(&.keyword).should eq(["when", "else"])
  end

  it "supports sibling case branches" do
    owner = parse_haml("- case value\n- when 1\n  %p one\n- else\n  %p other").children.first.as(Haml::AST::Code)
    owner.branches.size.should eq(2)
  end

  it "supports rescue, else, and ensure ownership" do
    owner = parse_haml("- begin\n  %p yes\n- rescue error\n  %p failed\n- else\n  %p fine\n- ensure\n  %p done").children.first.as(Haml::AST::Code)
    owner.branches.map(&.keyword).should eq(["rescue", "else", "ensure"])
  end

  it "recognizes output-capture blocks with trailing comments" do
    output = parse_haml("= wrap do |x| # a comment\n  %p= x").children.first.as(Haml::AST::Output)
    output.block?.should be_true
    output.children.size.should eq(1)
  end

  it "recognizes Haml's double equals as text rather than raw Crystal" do
    parse_haml("== hello").children.first.should be_a(Haml::AST::Text)
  end

  it "keeps both whitespace modifiers on the tag" do
    tag = parse_haml("%p<>").children.first.as(Haml::AST::Tag)
    tag.strip_inner?.should be_true
    tag.strip_outer?.should be_true
  end

  it "permits a childless explicit non-void tag" do
    parse_haml("%section/").children.first.as(Haml::AST::Tag).explicit_empty?.should be_true
  end

  it "rejects invalid UTF-8" do
    expect_raises(Haml::SyntaxError, /UTF-8/) { parse_haml(String.new(Bytes[255])) }
  end

  # Failure cases belong to the supported-subset contract, not just snapshots
  # of an incidental parser exception. Every one must fail before codegen.
  {
    "initial indentation"              => "  %p x",
    "jumped indentation"               => "%div\n    %p x",
    "inconsistent dedent"              => "%div\n  %p x\n %p y",
    "tab indentation"                  => "%div\n\t%p x",
    "empty tag name"                   => "%",
    "empty shorthand"                  => "%p.",
    "void inline content"              => "%br text",
    "void nested content"              => "%input\n  %p x",
    "empty tag nested content"         => "%div/\n  %p x",
    "inline and nested content"        => "%p text\n  %b more",
    "nested ordinary output"           => "= name\n  %p nope",
    "nested statement"                 => "- name = 1\n  %p nope",
    "orphan else"                      => "- else\n  %p no",
    "nonadjacent branch"               => "- if x\n  %p yes\n%hr\n- else\n  %p no",
    "unless elsif"                     => "- unless x\n  %p no\n- elsif y\n  %p yes",
    "duplicate else"                   => "- if x\n- else\n- else",
    "branch after ensure"              => "- begin\n- ensure\n- rescue e",
    "else without rescue"              => "- begin\n- else",
    "mixed case branch families"       => "- case x\n- when 1\n- in 2",
    "case body before when"            => "- case x\n  %p no",
    "manual end"                       => "- end",
    "type definition"                  => "- class User",
    "assignment block"                 => "- name = if x\n  %p no",
    "object reference"                 => "%p[user]",
    "legacy doctype"                   => "!!! XML",
    "unsupported filter"               => ":markdown\n  Hello",
    "conditional comment"              => "/[if IE]\n  %p old",
    "invalid comment"                  => "/ -->",
    "incomplete group"                 => "%p{title: name",
    "missing output"                   => "= ",
    "comment-only output"              => "= # nothing",
    "missing attribute value"          => "%p{title: }",
    "missing hash comma"               => "%p{title: 1,, class: 2}",
    "missing hash key"                 => "%p{: 1}",
    "unqualified attribute splat"      => "%p{attrs}",
    "adjacent HTML quoted attributes"  => "%p(a=\"x\"b=\"y\")",
    "unwrapped spaced HTML expression" => "%p(title=a + b)",
    "duplicate whitespace flag"        => "%p>>",
    "NUL"                              => "%p a\u0000b",
    "bare CR"                          => "%p a\rb",
  }.each do |description, source|
    it "rejects #{description}" do
      expect_raises(Haml::SyntaxError) { parse_haml(source) }
    end
  end

  it "bounds nested templates" do
    source = "%div\n  %div\n    %div\n      %p x"
    parser = Haml::Parser.new(source, "deep.haml", Haml::Options.new(max_depth: 2))
    expect_raises(Haml::SyntaxError, /nesting/) { parser.parse }
  end

  it "can be reused without retaining the preceding parse's index" do
    parser = Haml::Parser.new("%p x")
    parser.parse.children.size.should eq(1)
    parser.parse.children.size.should eq(1)
  end
end
