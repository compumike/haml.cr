require "../spec_helper"

describe Haml::AttributeParser do
  parser = Haml::AttributeParser.new
  origin = Haml::Location.new("attrs.haml")

  it "keeps Crystal value expressions opaque" do
    attrs = parser.hash_style(Haml::AST::Expression.new(%q|title: lookup(a, b), data: {key: value}|, origin))
    attrs.map(&.expression.source).should eq(["lookup(a, b)", "{key: value}"])
  end

  it "accepts leading comments on multiline values" do
    attrs = parser.hash_style(Haml::AST::Expression.new("title: # explanation\n  name,", origin))
    attrs.first.expression.source.should eq("name")
    attrs.first.expression.location.line.should eq(2)
    attrs.first.expression.location.column.should eq(3)
  end

  it "does not confuse comments with values" do
    expect_raises(Haml::SyntaxError, /missing attribute value/) do
      parser.hash_style(Haml::AST::Expression.new("title: # nothing\n", origin))
    end
  end

  it "supports trailing commas and comments" do
    attrs = parser.hash_style(Haml::AST::Expression.new("title: name, # comment\n", origin))
    attrs.size.should eq(1)
  end

  it "supports quoted names used by JavaScript frameworks" do
    attrs = parser.hash_style(Haml::AST::Expression.new(%q|"@click": handler, ":class" => state|, origin))
    attrs.map(&.name).should eq(["@click", ":class"])
  end

  it "rejects interpolated attribute names" do
    expect_raises(Haml::UnsupportedSyntax, /static/) do
      parser.hash_style(Haml::AST::Expression.new(%q|"#{name}": value|, origin))
    end
  end

  it "supports an explicit attribute-map splat" do
    attrs = parser.hash_style(Haml::AST::Expression.new("**attributes, title: name", origin))
    attrs.first.kind.splat?.should be_true
    attrs.first.expression.source.should eq("attributes")
  end

  it "does not interpret Ruby string literals in hash-style values" do
    attrs = parser.hash_style(Haml::AST::Expression.new(%q|title: 'x'|, origin))
    attrs.first.expression.source.should eq("'x'") # A Crystal Char, not Ruby String.
  end

  it "keeps quote style independent in HTML-style attributes" do
    attrs = parser.html_style(Haml::AST::Expression.new(%q|title='hi' alt="there"|, origin))
    attrs.map { |attr| attr.segments.map(&.text).join }.should eq(["hi", "there"])
  end

  it "retains spaces inside a parenthesized HTML attribute expression" do
    attrs = parser.html_style(Haml::AST::Expression.new(%q|title=(name + " suffix")|, origin))
    attrs.first.expression.source.should eq(%q|(name + " suffix")|)
  end

  it "splits HTML interpolation without prematurely escaping its literals" do
    attrs = parser.html_style(Haml::AST::Expression.new(%q|title="A & #{name}"|, origin))
    attrs.first.segments.map(&.text).should eq(["A & ", "name"])
  end
end
