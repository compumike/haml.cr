require "../spec_helper"

describe Haml::Runtime do
  it "escapes all five HTML metacharacters" do
    output = String.build { |io| Haml::Runtime.write_escaped(io, %q|<&>"'|) }
    output.should eq("&lt;&amp;&gt;&quot;&#39;")
  end

  it "stringifies numeric and nil output" do
    String.build { |io| Haml::Runtime.write_escaped(io, 123) }.should eq("123")
    String.build { |io| Haml::Runtime.write_escaped(io, nil) }.should eq("")
  end

  it "escapes markup in ordinary body values" do
    String.build { |io| Haml::Runtime.write_escaped(io, "<b>x</b>") }.should eq("&lt;b&gt;x&lt;/b&gt;")
  end

  it "explicitly escapes markup" do
    String.build { |io| Haml::Runtime.write_forced(io, "<b>x</b>") }.should eq("&lt;b&gt;x&lt;/b&gt;")
  end

  it "keeps raw output explicitly raw" do
    String.build { |io| Haml::Runtime.write_raw(io, "<b>x</b>") }.should eq("<b>x</b>")
  end

  it "preserves newlines after, not before, escaping" do
    String.build { |io| Haml::Runtime.write_preserved(io, "<x>\r\ny\n") }.should eq("&lt;x&gt;&#10;y&#10;")
  end

  it "escapes markup before preserving newlines" do
    String.build { |io| Haml::Runtime.write_preserved(io, "<b>\nx</b>") }.should eq("&lt;b&gt;&#10;x&lt;/b&gt;")
  end

  it "writes escaped output to an arbitrary write-only IO" do
    io = HamlSpecWriteOnlyIO.new
    Haml::Runtime.write_escaped(io, "a<b")
    io.buffer.to_s.should eq("a&lt;b")
    io.writes.should be > 0
  end
end

describe Haml::Runtime::Attributes do
  it "escapes attribute values, including ampersands and both quote types" do
    attributes_html { |a| a.add("title", %q|<&>"'|) }.should eq(" title=\"&lt;&amp;&gt;&quot;&#39;\"")
  end

  it "escapes injected attribute delimiters" do
    attributes_html { |a| a.add("title", %q|" onmouseover="evil|) }.should eq(" title=\"&quot; onmouseover=&quot;evil\"")
  end

  it "omits nil ordinary attributes" do
    attributes_html { |a| a.add("title", nil) }.should eq("")
  end

  it "writes true boolean attributes without a value" do
    attributes_html { |a| a.add("disabled", true) }.should eq(" disabled")
  end

  it "omits false and nil boolean attributes" do
    attributes_html { |a| a.add("disabled", false); a.add("checked", nil) }.should eq("")
  end

  it "preserves textual boolean-attribute values" do
    attributes_html { |a| a.add("hidden", "until-found") }.should eq(" hidden=\"until-found\"")
  end

  it "does not conflate false with the string false" do
    attributes_html { |a| a.add("disabled", "false") }.should eq(" disabled=\"false\"")
  end

  it "serializes booleans for non-boolean attributes" do
    attributes_html { |a| a.add("title", false); a.add("value", true) }.should eq(" title=\"false\" value=\"true\"")
  end

  it "retains false ARIA and data values" do
    attributes_html { |a| a.add("aria-hidden", false); a.add("data-ready", true) }.should eq(" aria-hidden=\"false\" data-ready=\"true\"")
  end

  it "deduplicates and flattens class tokens while omitting falsey values" do
    attributes_html do |a|
      a.add("class", "base")
      a.add("class", ["base active", nil, false, ["active", "wide"]])
    end.should eq(" class=\"base active wide\"")
  end

  it "joins IDs using underscores without deduplicating" do
    attributes_html { |a| a.add("id", ["item", 0, false, nil, ["item"]]) }.should eq(" id=\"item_0_item\"")
  end

  it "supports tuple-valued classes" do
    attributes_html { |a| a.add("class", {"one", false, {"two", "one"}}) }.should eq(" class=\"one two\"")
  end

  it "omits empty class and ID collections" do
    attributes_html { |a| a.add("class", [nil, false]); a.add("id", "") }.should eq("")
  end

  it "merges a later false class without erasing shorthand" do
    attributes_html { |a| a.add("class", "base"); a.add("class", false) }.should eq(" class=\"base\"")
  end

  it "preserves stable attribute insertion order and uses last ordinary value" do
    attributes_html do |a|
      a.add("title", "old")
      a.add("id", "x")
      a.add("title", "new")
    end.should eq(" title=\"new\" id=\"x\"")
  end

  it "allows a later nil to remove an ordinary attribute" do
    attributes_html { |a| a.add("title", "x"); a.add("title", nil) }.should eq("")
  end

  it "expands nested named tuples and hyphenates underscores" do
    attributes_html do |a|
      a.add("data", {item_id: 7, nested: {ready: false}})
      a.add("aria", {expanded: true})
    end.should eq(" data-item-id=\"7\" data-nested-ready=\"false\" aria-expanded=\"true\"")
  end

  it "expands nested hashes with string keys" do
    attributes_html { |a| a.add("data", {"book" => {"item_id" => 3}}) }.should eq(" data-book-item-id=\"3\"")
  end

  it "supports named tuple splats" do
    attributes_html { |a| a.add_all({title: "x", disabled: true}) }.should eq(" title=\"x\" disabled")
  end

  it "supports hash splats and class merging" do
    attributes_html do |a|
      a.add("class", "base")
      a.add_all({"class" => "other", "title" => "x"})
    end.should eq(" class=\"base other\" title=\"x\"")
  end

  it "allows attribute names used by small JS frameworks" do
    attributes_html { |a| a.add("@click", "go()"); a.add(":class", "active") }.should eq(" @click=\"go()\" :class=\"active\"")
  end

  ["", "x y", "x\ty", "x\ny", "x=y", "x\"y", "x'y", "x/y", "x>y", "x<y", "x\u0000y", "x\u007fy"].each do |name|
    it "rejects invalid attribute name #{name.inspect}" do
      expect_raises(ArgumentError) { attributes_html { |a| a.add(name, "value") } }
    end
  end

  it "validates names supplied through splats" do
    expect_raises(ArgumentError) { attributes_html { |a| a.add_all({"onclick bad" => "x"}) } }
  end

  it "validates expanded data names" do
    expect_raises(ArgumentError) { attributes_html { |a| a.add("data", {"bad key" => 1}) } }
  end

  it "rejects empty prefixed keys" do
    expect_raises(ArgumentError) { attributes_html { |a| a.add("data", {"" => 1}) } }
  end

  it "bounds data-map recursion" do
    writer = Haml::Runtime::Attributes.new(1)
    expect_raises(ArgumentError, /nesting/) { writer.add("data", {outer: {inner: 1}}) }
  end

  it "bounds class-list recursion" do
    writer = Haml::Runtime::Attributes.new(1)
    expect_raises(ArgumentError, /nesting/) { writer.add("class", [["x"]]) }
  end
end
