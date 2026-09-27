module Haml
  # The delayed {{ run(...) }} expansion follows Crystal stdlib ECR. It lets a
  # fresh macro IO variable be named before its name is sent to the generator.
  # The generator program is resolved relative to THIS file, so both a local
  # checkout and installation as lib/haml work without symlinks or CRYSTAL_PATH
  # tricks. Template filenames, like ECR's, are relative to the build's cwd.
  # Use an absolute path (typically interpolating __DIR__) for relocatability.
  macro embed(filename, io_name, indent_width = 2)
    \{{ run({{__DIR__ + "/process.cr"}}, "file", {{filename}}, {{io_name.id.stringify}}, {{indent_width.stringify}}) }}
  end

  macro render(filename, indent_width = 2)
    ::String.build do |%io|
      ::Haml.embed({{filename}}, %io, {{indent_width}})
    end
  end

  macro def_to_s(filename, indent_width = 2)
    def to_s(__haml_io : IO) : Nil
      ::Haml.embed({{filename}}, "__haml_io", {{indent_width}})
    end
  end

  # Compile-time inline strings are useful for small fragments and specs. This
  # is not eval: source must be known at compile time. Large inputs should use
  # files because operating systems limit argument length for macro-run tools.
  macro embed_string(source, io_name, filename = "inline.haml", indent_width = 2)
    \{{ run({{__DIR__ + "/process.cr"}}, "string", {{source}}, {{io_name.id.stringify}}, {{indent_width.stringify}}, {{filename}}) }}
  end

  macro render_string(source, filename = "inline.haml", indent_width = 2)
    ::String.build do |%io|
      ::Haml.embed_string({{source}}, %io, {{filename}}, {{indent_width}})
    end
  end
end
