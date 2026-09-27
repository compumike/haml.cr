require "../spec_helper"

# These are real macro -> generator -> Crystal compiler -> renderer tests,
# not just assertions about generated source. Fixtures are plain .haml files
# so the test's own string interpolation cannot consume their #{...} syntax.
class HamlSpecCounter
  getter calls = 0

  def next_value : String
    @calls += 1
    @calls.to_s
  end
end

def haml_spec_wrap(&block : -> String) : String
  body = yield
  "<section>" + body + "</section>"
end

def haml_spec_greeting(&block : String -> String) : String
  body = yield "Reader"
  "<section>" + body + "</section>"
end

describe "compiled Haml rendering" do
  it "empty template" do
    actual = Haml.render "spec/fixtures/render/001.haml"
    actual.should eq("")
  end

  it "blank lines" do
    actual = Haml.render "spec/fixtures/render/002.haml"
    actual.should eq("")
  end

  it "comment-only template" do
    actual = Haml.render "spec/fixtures/render/003.haml"
    actual.should eq("")
  end

  it "a simple tag" do
    actual = Haml.render "spec/fixtures/render/004.haml"
    actual.should eq("<p>Hello</p>\n")
  end

  it "nested tags" do
    actual = Haml.render "spec/fixtures/render/005.haml"
    actual.should eq("<ul>\n<li>One</li>\n<li>Two</li>\n</ul>\n")
  end

  it "plain text and authored entities" do
    actual = Haml.render "spec/fixtures/render/006.haml"
    actual.should eq("Hello <b>world</b> &copy;\n")
  end

  it "implicit div with classes and id" do
    actual = Haml.render "spec/fixtures/render/007.haml"
    actual.should eq("<div class=\"one two\" id=\"box\"></div>\n")
  end

  it "custom elements" do
    actual = Haml.render "spec/fixtures/render/008.haml"
    actual.should eq("<my-widget class=\"foo\"></my-widget>\n")
  end

  it "SVG names and explicit empty nonvoid tags" do
    actual = Haml.render "spec/fixtures/render/009.haml"
    actual.should eq("<svg>\n<path></path>\n</svg>\n")
  end

  it "HTML5 doctype" do
    actual = Haml.render "spec/fixtures/render/010.haml"
    actual.should eq("<!DOCTYPE html>\n<html></html>\n")
  end

  it "explicit HTML5 doctype" do
    actual = Haml.render "spec/fixtures/render/011.haml"
    actual.should eq("<!DOCTYPE html>\n")
  end

  it "void tags" do
    actual = Haml.render "spec/fixtures/render/012.haml"
    actual.should eq("<br>\n<img src=\"x.png\">\n<input>\n")
  end

  it "explicit empty nonvoid HTML" do
    actual = Haml.render "spec/fixtures/render/013.haml"
    actual.should eq("<div></div>\n")
  end

  it "escaped expression output" do
    name = "<Mike & Co>"
    actual = Haml.render "spec/fixtures/render/014.haml"
    actual.should eq("<p>&lt;Mike &amp; Co&gt;</p>\n")
  end

  it "raw expression output" do
    markup = "<b>x</b>"
    actual = Haml.render "spec/fixtures/render/015.haml"
    actual.should eq("<div><b>x</b></div>\n")
  end

  it "markup is escaped by default" do
    markup = "<b>x</b>"
    actual = Haml.render "spec/fixtures/render/016.haml"
    actual.should eq("<div>&lt;b&gt;x&lt;/b&gt;</div>\n")
  end

  it "explicit escaping of markup" do
    markup = "<b>x</b>"
    actual = Haml.render "spec/fixtures/render/017.haml"
    actual.should eq("<div>&lt;b&gt;x&lt;/b&gt;</div>\n")
  end

  it "nil output" do
    actual = Haml.render "spec/fixtures/render/018.haml"
    actual.should eq("<p></p>\n")
  end

  it "numeric output" do
    actual = Haml.render "spec/fixtures/render/019.haml"
    actual.should eq("123\n")
  end

  it "interpolation without escaping authored markup" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/020.haml"
    actual.should eq("<p>Hello <em>&lt;Mike&gt;</em> &copy;</p>\n")
  end

  it "escaped interpolation" do
    actual = Haml.render "spec/fixtures/render/021.haml"
    actual.should eq("<p>Hello \#{name}</p>\n")
  end

  it "interpolation at the start of a line" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/022.haml"
    actual.should eq("&lt;Mike&gt; says hello\n")
  end

  it "Haml double equals is text interpolation" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/023.haml"
    actual.should eq("hello &lt;Mike&gt;\n")
  end

  it "inline double equals" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/024.haml"
    actual.should eq("<p>hello &lt;Mike&gt;</p>\n")
  end

  it "forced text escaping" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/025.haml"
    actual.should eq("&lt;b&gt;&lt;Mike&gt;&lt;/b&gt;\n")
  end

  it "raw interpolation" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/026.haml"
    actual.should eq("<b><Mike></b>\n")
  end

  it "literal leading special characters" do
    actual = Haml.render "spec/fixtures/render/027.haml"
    actual.should eq("%not_a_tag\n")
  end

  it "hash-style attributes" do
    url = "/a?x=1&y=2"
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/028.haml"
    actual.should eq("<a href=\"/a?x=1&amp;y=2\" title=\"&lt;Mike&gt;\">Go</a>\n")
  end

  it "legacy static attribute keys" do
    name = "x"
    actual = Haml.render "spec/fixtures/render/029.haml"
    actual.should eq("<p title=\"x\" data-x=\"7\"></p>\n")
  end

  it "HTML-style strings and a local variable" do
    url = "/home"
    actual = Haml.render "spec/fixtures/render/030.haml"
    actual.should eq("<a href=\"/home\" title=\"Hello\">Go</a>\n")
  end

  it "single-quoted HTML strings" do
    actual = Haml.render "spec/fixtures/render/031.haml"
    actual.should eq("<p title=\"He said &quot;go&quot;\"></p>\n")
  end

  it "HTML-style interpolated attributes escape once" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/032.haml"
    actual.should eq("<p title=\"Hi &lt;Mike&gt; &amp; more\"></p>\n")
  end

  it "parenthesized expressions in HTML attributes" do
    name = "Mike"
    actual = Haml.render "spec/fixtures/render/033.haml"
    actual.should eq("<p title=\"Hello Mike\"></p>\n")
  end

  it "boolean and nil attributes" do
    actual = Haml.render "spec/fixtures/render/034.haml"
    actual.should eq("<input checked>\n")
  end

  it "bare HTML boolean attribute" do
    actual = Haml.render "spec/fixtures/render/035.haml"
    actual.should eq("<input disabled>\n")
  end

  it "ordinary false attributes" do
    actual = Haml.render "spec/fixtures/render/036.haml"
    actual.should eq("<input title=\"false\" value=\"true\">\n")
  end

  it "class arrays and merging" do
    active = true
    actual = Haml.render "spec/fixtures/render/037.haml"
    actual.should eq("<p class=\"base wide active\"></p>\n")
  end

  it "ID merging" do
    actual = Haml.render "spec/fixtures/render/038.haml"
    actual.should eq("<p id=\"item_7_detail\"></p>\n")
  end

  it "data and ARIA named tuples" do
    actual = Haml.render "spec/fixtures/render/039.haml"
    actual.should eq("<p data-item-id=\"7\" data-nested-ready=\"false\" aria-hidden=\"false\"></p>\n")
  end

  it "attribute splats" do
    attrs = {"class" => "extra", "title" => "old"}
    actual = Haml.render "spec/fixtures/render/040.haml"
    actual.should eq("<p class=\"base extra\" title=\"new\"></p>\n")
  end

  it "attribute delimiters are always escaped" do
    value = %q|" onclick="evil|
    actual = Haml.render "spec/fixtures/render/041.haml"
    actual.should eq("<p title=\"&quot; onclick=&quot;evil\"></p>\n")
  end

  it "multiline attribute groups" do
    name = "Mike"
    actual = Haml.render "spec/fixtures/render/042.haml"
    actual.should eq("<p title=\"Mike\" class=\"wide active\">Hello</p>\n")
  end

  it "multiline output expression" do
    actual = Haml.render "spec/fixtures/render/043.haml"
    actual.should eq("3\n")
  end

  it "commas and braces inside expressions" do
    actual = Haml.render "spec/fixtures/render/044.haml"
    actual.should eq("<p title=\"a,b-}\"></p>\n")
  end

  it "a slash regex inside an attribute" do
    actual = Haml.render "spec/fixtures/render/045.haml"
    actual.should eq("<p title=\"[}]\"></p>\n")
  end

  it "a percent regex inside an attribute" do
    actual = Haml.render "spec/fixtures/render/046.haml"
    actual.should eq("<p title=\"[},]\"></p>\n")
  end

  it "division inside an attribute" do
    actual = Haml.render "spec/fixtures/render/047.haml"
    actual.should eq("<p title=\"3.0\"></p>\n")
  end

  it "integer division inside an attribute" do
    actual = Haml.render "spec/fixtures/render/048.haml"
    actual.should eq("<p title=\"3\"></p>\n")
  end

  it "Crystal interpolation in an output expression" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/049.haml"
    actual.should eq("Hello &lt;Mike&gt;\n")
  end

  it "if elsif else" do
    value = 2
    actual = Haml.render "spec/fixtures/render/050.haml"
    actual.should eq("<p>two</p>\n")
  end

  it "unless else" do
    active = true
    actual = Haml.render "spec/fixtures/render/051.haml"
    actual.should eq("<p>on</p>\n")
  end

  it "a silent local assignment" do
    actual = Haml.render "spec/fixtures/render/052.haml"
    actual.should eq("<p>Mike</p>\n")
  end

  it "nested control flow" do
    actual = Haml.render "spec/fixtures/render/053.haml"
    actual.should eq("<p>inner</p>\n")
  end

  it "iteration" do
    names = ["A", "B"]
    actual = Haml.render "spec/fixtures/render/054.haml"
    actual.should eq("<ul>\n<li>A</li>\n<li>B</li>\n</ul>\n")
  end

  it "while" do
    actual = Haml.render "spec/fixtures/render/055.haml"
    actual.should eq("<p>0</p>\n<p>1</p>\n")
  end

  it "until" do
    actual = Haml.render "spec/fixtures/render/056.haml"
    actual.should eq("<p>0</p>\n<p>1</p>\n")
  end

  it "next in a loop" do
    actual = Haml.render "spec/fixtures/render/057.haml"
    actual.should eq("<p>1</p>\n<p>3</p>\n")
  end

  it "sibling case branches" do
    number = 2
    actual = Haml.render "spec/fixtures/render/058.haml"
    actual.should eq("<p>two</p>\n")
  end

  it "indented case branches" do
    number = 4
    actual = Haml.render "spec/fixtures/render/059.haml"
    actual.should eq("<p>other</p>\n")
  end

  it "rescue and ensure" do
    actual = Haml.render "spec/fixtures/render/060.haml"
    actual.should eq("<p>boom</p>\n<p>done</p>\n")
  end

  it "trailing Crystal comments" do
    name = "Mike"
    actual = Haml.render "spec/fixtures/render/061.haml"
    actual.should eq("<p>Mike</p>\n")
  end

  it "inner whitespace control" do
    actual = Haml.render "spec/fixtures/render/062.haml"
    actual.should eq("<p><b>x</b></p>\n")
  end

  it "outer whitespace control" do
    actual = Haml.render "spec/fixtures/render/063.haml"
    actual.should eq("<span>a</span><span>b</span><span>c</span>\n")
  end

  it "combined whitespace controls" do
    actual = Haml.render "spec/fixtures/render/064.haml"
    actual.should eq("<p><b>x</b></p>")
  end

  it "runtime whitespace is never stripped" do
    value = " x \n"
    actual = Haml.render "spec/fixtures/render/065.haml"
    actual.should eq("<p> x \n</p>\n")
  end

  it "line preservation" do
    value = "a\nb"
    actual = Haml.render "spec/fixtures/render/066.haml"
    actual.should eq("a&#10;b\n")
  end

  it "a static HTML comment" do
    actual = Haml.render "spec/fixtures/render/067.haml"
    actual.should eq("<!-- note -->\n")
  end

  it "nested static HTML comment" do
    actual = Haml.render "spec/fixtures/render/068.haml"
    actual.should eq("<!--\n<p>old</p>\n-->\n")
  end

  it "a plain filter" do
    actual = Haml.render "spec/fixtures/render/069.haml"
    actual.should eq("one\n  two\n")
  end

  it "an escaped filter" do
    name = "<Mike>"
    actual = Haml.render "spec/fixtures/render/070.haml"
    actual.should eq("&lt;b&gt;&lt;Mike&gt;&lt;/b&gt;\n")
  end

  it "a preserve filter" do
    actual = Haml.render "spec/fixtures/render/071.haml"
    actual.should eq("a&#10;b&#10;\n")
  end

  it "a CSS filter" do
    actual = Haml.render "spec/fixtures/render/072.haml"
    actual.should eq("<style>\na { color: red; }\n</style>\n")
  end

  it "a JS filter with deliberately literal interpolation syntax" do
    actual = Haml.render "spec/fixtures/render/073.haml"
    actual.should eq("<script>\nconst s = \"\#{not_a_crystal_variable}\";\n</script>\n")
  end

  it "an output-capture helper" do
    actual = Haml.render "spec/fixtures/render/074.haml"
    actual.should eq("<section><p>Hello</p>\n</section>\n")
  end

  it "a capture helper yielding a value" do
    actual = Haml.render "spec/fixtures/render/075.haml"
    actual.should eq("<section><p>Reader</p>\n</section>\n")
  end

  it "inline tag capture" do
    actual = Haml.render "spec/fixtures/render/076.haml"
    actual.should eq("<div><section><p>Hello</p>\n</section></div>\n")
  end

  it "single evaluation of an attribute" do
    counter = HamlSpecCounter.new
    actual = Haml.render "spec/fixtures/render/077.haml"
    actual.should eq("<p title=\"1\"></p>\n")
    counter.calls.should eq(1)
  end

  it "single evaluation of output" do
    counter = HamlSpecCounter.new
    actual = Haml.render "spec/fixtures/render/078.haml"
    actual.should eq("1\n")
    counter.calls.should eq(1)
  end

  it "single evaluation of interpolation" do
    counter = HamlSpecCounter.new
    actual = Haml.render "spec/fixtures/render/079.haml"
    actual.should eq("1\n")
    counter.calls.should eq(1)
  end

  it "Unicode text and dynamic content" do
    name = "東京"
    actual = Haml.render "spec/fixtures/render/080.haml"
    actual.should eq("<p>Café 東京</p>\n")
  end

  it "leading comments on an attribute value" do
    name = "Mike"
    actual = Haml.render "spec/fixtures/render/081.haml"
    actual.should eq("<p title=\"Mike\"></p>\n")
  end

  it "Crystal percent q terminates even after a backslash" do
    actual = Haml.render "spec/fixtures/render/082.haml"
    actual.should eq("<p title=\"a\\\"></p>\n")
  end

  it "interpolation in Crystal arrays" do
    name = "&"
    actual = Haml.render_string(%q|= ["a", "#{name}", "b"].join(",")|)
    actual.should eq("a,&amp;,b\n")
  end

  # Older Crystal parsers do not support interpolated word-array literals.
  {% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
    it "interpolation in Crystal percent W arrays" do
      name = "&"
      actual = Haml.render "spec/fixtures/render/083.haml"
      actual.should eq("a,&amp;,b\n")
    end
  {% end %}

  it "exhaustive case branches" do
    flag = true
    actual = Haml.render "spec/fixtures/render/084.haml"
    actual.should eq("<p>yes</p>\n")
  end

  it "type narrowing inside Crystal conditionals" do
    name : String? = "Mike"
    actual = Haml.render "spec/fixtures/render/085.haml"
    actual.should eq("<p>4</p>\n")
  end

  it "break from an iteration" do
    actual = Haml.render "spec/fixtures/render/086.haml"
    actual.should eq("<p>1</p>\n")
  end

  it "nested captures use independent output buffers" do
    actual = Haml.render "spec/fixtures/render/087.haml"
    actual.should eq("<section><section><p>inner</p>\n</section>\n</section>\n")
  end

  it "a silent comment does not detach else" do
    actual = Haml.render "spec/fixtures/render/088.haml"
    actual.should eq("<p>yes</p>\n")
  end

  it "attribute side effects follow source order" do
    counter = HamlSpecCounter.new
    actual = Haml.render "spec/fixtures/render/089.haml"
    actual.should eq("<p title=\"1\" class=\"2\" id=\"3\"></p>\n")
  end

  it "inner trim affects separators on every loop iteration" do
    actual = Haml.render "spec/fixtures/render/090.haml"
    actual.should eq("<p><b>A</b><b>B</b></p>\n")
  end
end
