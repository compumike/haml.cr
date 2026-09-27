require "../spec_helper"

describe Haml::Scanner do
  it "tracks Unicode character columns and physical lines" do
    scanner = scan_haml("é\nx")
    scanner.take.should eq('é')
    scanner.location.column.should eq(2)
    scanner.take
    scanner.location.line.should eq(2)
    scanner.location.column.should eq(1)
  end

  it "lands after a balanced group" do
    scanner = scan_haml(%q|{key: [1, (2 + 3)]}tail|)
    scanner.group.source.should eq("key: [1, (2 + 3)]")
    scanner.remaining.should eq("tail")
  end

  it "does not split on commas or braces in quoted strings" do
    scanner = scan_haml(%q|"a,}b", next_value|)
    scanner.read_until(",").source.should eq(%q|"a,}b"|)
    scanner.current.should eq(',')
  end

  it "handles nested interpolation inside a quoted Crystal string" do
    scanner = scan_haml(%q|{x: "#{ {a: "}"}[:a] }"}end|)
    scanner.group.source.should eq(%q|x: "#{ {a: "}"}[:a] }"|)
    scanner.remaining.should eq("end")
  end

  it "handles Crystal character literals containing delimiters" do
    scan_haml(%q|{x: '}', y: ','}|).group.source.should eq(%q|x: '}', y: ','|)
  end

  it "ignores closing braces in comments" do
    scanner = scan_haml("{x: 1, # } ignored\ny: 2}rest")
    scanner.group.source.should contain("y: 2")
    scanner.remaining.should eq("rest")
  end

  it "handles noninterpolated percent strings with nested delimiters" do
    scanner = scan_haml(%q|{x: %q(a(b)c)}tail|)
    scanner.group.source.should eq(%q|x: %q(a(b)c)|)
    scanner.remaining.should eq("tail")
  end

  it "handles percent regexes containing braces and commas" do
    scanner = scan_haml(%q|{x: %r([},])}tail|)
    scanner.group.source.should eq(%q|x: %r([},])|)
    scanner.remaining.should eq("tail")
  end

  it "handles regex character classes containing escaped slashes and braces" do
    scanner = scan_haml(%q|{x: /[\/},]/}tail|)
    scanner.group.source.should eq(%q|x: /[\/},]/|)
    scanner.remaining.should eq("tail")
  end

  it "handles regex call arguments" do
    scanner = scan_haml(%q|{x: text.match(/}/)}tail|)
    scanner.group.source.should eq(%q|x: text.match(/}/)|)
    scanner.remaining.should eq("tail")
  end

  it "does not confuse spaced division with a regex" do
    scan_haml("{x: 6 / 2, y: 6/2}").group.source.should eq("x: 6 / 2, y: 6/2")
  end

  it "supports integer division" do
    scan_haml("{x: 7 // 2}").group.source.should eq("x: 7 // 2")
  end

  it "rejects ambiguous slash syntax" do
    expect_raises(Haml::UnsupportedSyntax, /ambiguous slash/) { scan_haml("method /x/").read_until }
  end

  it "rejects heredocs rather than guessing at their boundaries" do
    expect_raises(Haml::UnsupportedSyntax, /heredocs/) { scan_haml("call(<<-TEXT)").read_until }
  end

  it "rejects embedded Crystal macros" do
    expect_raises(Haml::UnsupportedSyntax, /macro/) { scan_haml("{{ 1 }}").read_until }
  end

  it "reports an incomplete group" do
    expect_raises(Haml::IncompleteExpression, /unclosed/) { scan_haml("{a: 1").group }
  end

  it "reports an incomplete string" do
    expect_raises(Haml::IncompleteExpression, /unclosed/) { scan_haml(%q|"hello|).read_until }
  end

  it "reports mismatched closing delimiters" do
    expect_raises(Haml::SyntaxError, /closing delimiter/) { scan_haml("[1, 2)").group }
  end

  it "bounds expression nesting" do
    scanner = Haml::Scanner.new("[[[1]]]", Haml::Location.new("deep.haml"), 2)
    expect_raises(Haml::SyntaxError, /nesting/) { scanner.group }
  end

  it "adjusts a trimmed expression's source location" do
    expression = Haml::Scanner.expression(" \n  name  ", Haml::Location.new("x", 7, 2))
    expression.source.should eq("name")
    expression.location.line.should eq(8)
    expression.location.column.should eq(3)
  end

  it "supports Haml single-quoted attribute strings with nested interpolation" do
    scanner = scan_haml(%q|(title='#{ "'" }')tail|)
    scanner.group(template_strings: true).source.should eq(%q|title='#{ "'" }'|)
    scanner.remaining.should eq("tail")
  end
end

describe Haml::Interpolation do
  it "keeps literals and dynamic values separate" do
    parts = Haml::Interpolation.parse(%q|Hello <b>#{name}</b> &copy;|, Haml::Location.new("x"))
    parts.map(&.dynamic?).should eq([false, true, false])
    parts.map(&.text).should eq(["Hello <b>", "name", "</b> &copy;"])
  end

  it "allows escaped interpolation" do
    parts = Haml::Interpolation.parse(%q|Hello \#{name}|, Haml::Location.new("x"))
    parts.size.should eq(1)
    parts.first.dynamic?.should be_false
    parts.first.text.should eq(%q|Hello #{name}|)
  end

  it "decodes quoted attribute escapes" do
    parts = Haml::Interpolation.parse(%q|a\nb\t\"c|, Haml::Location.new("x"), true)
    parts.first.text.should eq("a\nb\t\"c")
  end

  it "does not accept undocumented attribute escapes" do
    expect_raises(Haml::UnsupportedSyntax) { Haml::Interpolation.parse(%q|\x41|, Haml::Location.new("x"), true) }
  end

  it "rejects empty interpolation" do
    expect_raises(Haml::SyntaxError, /empty interpolation/) { Haml::Interpolation.parse(%q|#{ }|, Haml::Location.new("x")) }
  end
end

describe "additional Crystal lexical boundaries" do
  it "does not let a backslash escape the terminator of percent q" do
    scanner = scan_haml(%q|{title: %q(a\)}tail|)
    scanner.group.source.should eq(%q|title: %q(a\)|)
    scanner.remaining.should eq("tail")
  end

  it "handles interpolation in an uppercase percent W array" do
    scanner = scan_haml(%q|{title: %W[a #{value} b]}tail|)
    scanner.group.source.should eq(%q|title: %W[a #{value} b]|)
    scanner.remaining.should eq("tail")
  end

  it "rejects comment-only interpolation" do
    expect_raises(Haml::SyntaxError, /empty interpolation/) do
      Haml::Interpolation.parse("\#{ # comment\n }", Haml::Location.new("x"))
    end
  end

  ["(", "[", "{"].each do |open|
    close = {"(" => ")", "[" => "]", "{" => "}"}[open]
    (1..12).each do |depth|
      it "balances #{depth} levels of #{open}" do
        # Separate brace tokens: adjacent {{ opens a Crystal macro, not nested tuples.
        source = (open + " ") * depth + "value" + (" " + close) * depth + ",tail"
        scanner = scan_haml(source)
        scanner.read_until(",").source.should eq(source[0...-5])
        scanner.remaining.should eq(",tail")
      end
    end
  end
end

describe "slash literals use Crystal delimiter rules" do
  it "does not invent an exemption for an unescaped slash in a character class" do
    expect_raises(Haml::SyntaxError) { scan_haml(%q|/[/]/|).read_until }
  end
end
