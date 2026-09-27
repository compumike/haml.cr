require "../spec_helper"

# Separate from codegen tests: each of these expands the real public macros.
class HamlSpecGreeting
  def initialize(@name : String) : Nil
  end

  Haml.def_to_s "spec/fixtures/object.haml"
end

describe "Haml public macros" do
  it "renders an inline compile-time string using lexical locals" do
    name = "<Reader>"
    Haml.render_string("%p= name").should eq("<p>&lt;Reader&gt;</p>\n")
  end

  it "does not make a runtime eval API out of inline strings" do
    # %q prevents this .cr source from interpolating the Haml prematurely.
    name = "<Reader>"
    Haml.render_string(%q|%p Hello #{name}|).should eq("<p>Hello &lt;Reader&gt;</p>\n")
  end

  it "writes to an existing IO, accepting the ECR-style string name" do
    io = HamlSpecWriteOnlyIO.new
    name = "Reader"
    Haml.embed_string("%p= name", "io")
    io.buffer.to_s.should eq("<p>Reader</p>\n")
  end

  it "also accepts a bare IO variable" do
    io = IO::Memory.new
    Haml.embed_string("%p Hello", io)
    io.to_s.should eq("<p>Hello</p>\n")
  end

  it "embeds a file without requiring a String-returning wrapper" do
    io = IO::Memory.new
    Haml.embed("spec/fixtures/render/004.haml", io)
    io.to_s.should eq("<p>Hello</p>\n")
  end

  it "defines a to_s(io) implementation using instance variables" do
    HamlSpecGreeting.new("<Reader>").to_s.should eq("<p>&lt;Reader&gt;</p>\n")
  end

  it "does not overwrite common application local-variable names" do
    io = "application io"
    __haml_io = "application long name"
    result = Haml.render_string("%p hello")
    result.should eq("<p>hello</p>\n")
    io.should eq("application io")
    __haml_io.should eq("application long name")
  end

  it "supports repeated expansions in the same scope" do
    name = "A"
    a = Haml.render_string("%p= name")
    name = "B"
    b = Haml.render_string("%p= name")
    a.should eq("<p>A</p>\n")
    b.should eq("<p>B</p>\n")
  end

  it "supports configured indentation in inline templates" do
    Haml.render_string("%ul\n    %li x", indent_width: 4).should eq("<ul>\n<li>x</li>\n</ul>\n")
  end
end
