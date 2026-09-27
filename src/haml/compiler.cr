require "./generator"

module Haml
  def self.compile(source : String, filename : String = "inline.haml",
                   io_name : String = "__haml_io", options : Options = Options.new) : String
    # Translation API for tools. This returns Crystal source, NOT rendered HTML.
    # Application rendering normally uses require "haml" and the embed/render
    # macros instead, keeping compiler dependencies out of the application graph.
    document = Parser.new(source, filename, options).parse
    fingerprint = filename + "\0" + io_name + "\0" + source
    Generator.new(io_name, options, fingerprint).generate(document)
  end

  def self.compile_file(filename : String, io_name : String = "__haml_io",
                        options : Options = Options.new) : String
    compile(File.read(filename), filename, io_name, options)
  end
end
