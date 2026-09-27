require "spec"
require "../src/haml"
require "../src/haml/compiler"

def attributes_html(&block : Haml::Runtime::Attributes ->) : String
  # Keep test helpers outside Haml's namespace so accidental namespace lookup
  # cannot hide an implementation error in generated ::Haml references.
  writer = Haml::Runtime::Attributes.new
  yield writer
  String.build { |io| writer.write_to(io) }
end

def parse_haml(source : String, indent : Int32 = 2) : Haml::AST::Document
  Haml::Parser.new(source, "test.haml", Haml::Options.new(indent)).parse
end

def scan_haml(source : String) : Haml::Scanner
  Haml::Scanner.new(source, Haml::Location.new("scan.haml"))
end

# A non-memory IO verifies the rendering API does not read back, seek, or assume
# IO::Memory. Its backing buffer is only for assertions in these tests.
class HamlSpecWriteOnlyIO < IO
  getter writes = 0
  getter buffer = IO::Memory.new

  def read(slice : Bytes) : Int32
    raise IO::Error.new("write-only test IO")
  end

  def write(slice : Bytes) : Nil
    @writes += 1
    @buffer.write(slice)
  end
end
