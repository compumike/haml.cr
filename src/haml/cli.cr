require "option_parser"
require "./compiler"

# The CLI and macros use the same compiler; there is no second implementation.
# A default invocation prints a Crystal method body. --method wraps it in a
# named method, with optional caller-supplied Crystal parameter declarations.
# The surrounding application remains responsible for `require "haml"`.
begin
  output : String? = nil
  method_name : String? = nil
  params = ""
  io_name = "__haml_io"
  indent = 2
  locations = true
  check = false
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: hamlc [options] FILE.haml"
    opts.on("-o FILE", "--output=FILE", "Write generated Crystal (default: stdout)") { |value| output = value }
    opts.on("--io=NAME", "Name of the existing output IO variable") { |value| io_name = value }
    opts.on("--method=NAME", "Wrap the body in a named render method") { |value| method_name = value }
    opts.on("--params=DECLARATIONS", "Extra Crystal parameters for --method") { |value| params = value }
    opts.on("--indent=WIDTH", "Spaces per indentation level (default: 2)") { |value| indent = value.to_i }
    opts.on("--no-locations", "Omit Crystal source-location directives") { locations = false }
    opts.on("--check", "Validate Haml and generate internally; do not write (not Crystal type-checking)") { check = true }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end
  parser.parse
  if ARGV.size != 1
    STDERR.puts parser
    exit 2
  end
  unless params.empty? || method_name
    raise ArgumentError.new("--params requires --method")
  end
  generated = Haml.compile_file(ARGV[0], io_name, Haml::Options.new(indent, locations))
  if name = method_name
    unless (name =~ /\A[a-z_][a-zA-Z0-9_]*[!?]?\z/) && !Haml::Generator::RESERVED_WORDS.includes?(name)
      raise ArgumentError.new("invalid method name")
    end
    declarations = params.empty? ? "" : ", #{params}"
    generated = "def #{name}(#{io_name} : IO#{declarations}) : Nil\n#{generated}end\n"
  end
  unless check
    if filename = output
      # Do not touch mtime when output has not changed. External build systems
      # can safely key subsequent compilation on generated-file timestamps.
      unless File.exists?(filename) && File.read(filename) == generated
        File.write(filename, generated)
      end
    else
      STDOUT.print generated
    end
  end
rescue ex : Haml::Error | File::Error | ArgumentError | OptionParser::Exception
  STDERR.puts ex.message
  exit 1
end
