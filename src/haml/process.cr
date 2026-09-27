# Internal macro-run executable. Only generated source goes to stdout. Located
# diagnostics go to stderr and a nonzero exit aborts Crystal compilation.
require "./compiler"

begin
  unless ARGV.size >= 4
    STDERR.puts "haml macro processor: expected MODE INPUT IO_NAME INDENT [FILENAME]"
    exit 1
  end
  mode, input, io_name, indent = ARGV[0], ARGV[1], ARGV[2], ARGV[3]
  options = Haml::Options.new(indent.to_i)
  case mode
  when "file"
    STDOUT.print Haml.compile_file(input, io_name, options)
  when "string"
    filename = ARGV[4]? || "inline.haml"
    STDOUT.print Haml.compile(input, filename, io_name, options)
  else
    STDERR.puts "haml macro processor: invalid mode #{mode.inspect}"
    exit 1
  end
rescue ex : Haml::Error | File::Error | ArgumentError
  STDERR.puts ex.message
  exit 1
end
