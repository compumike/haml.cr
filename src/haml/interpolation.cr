require "./scanner"

module Haml
  module Interpolation
    def self.parse(text : String, location : Location, quoted : Bool = false, max_depth : Int32 = 128) : Array(AST::Segment)
      # In ordinary text, literal markup stays literal; ONLY the interpolated
      # values are auto-escaped. Escaping the entire concatenated string would
      # break authored <em> markup and &copy; entities.
      #
      # For HTML-style quoted attributes, decode a small explicit set of escapes.
      # `{...}` attribute expressions instead retain native Crystal string rules.
      scanner = Scanner.new(text, location, max_depth)
      segments = [] of AST::Segment
      literal = IO::Memory.new
      literal_location = location
      until scanner.eof?
        if scanner.starts_with?("\\\#{")
          scanner.take
          literal << scanner.take << scanner.take
        elsif scanner.starts_with?("\#{")
          unless literal.empty?
            segments << AST::Segment.new(literal.to_s, literal_location)
            literal = IO::Memory.new
          end
          scanner.take # #
          expression = scanner.group
          expression = Scanner.expression(expression.source, expression.location)
          value_scanner = Scanner.new(expression.source, expression.location, max_depth)
          value_scanner.skip_space_and_comments
          if value_scanner.eof?
            raise SyntaxError.new("empty interpolation", expression.location)
          end
          segments << AST::Segment.new(expression.source, expression.location, true)
          literal_location = scanner.location
        elsif quoted && scanner.current == '\\'
          origin = scanner.location
          scanner.take
          raise SyntaxError.new("unfinished attribute escape", origin) if scanner.eof?
          case char = scanner.take
          when 'n'             then literal << '\n'
          when 'r'             then literal << '\r'
          when 't'             then literal << '\t'
          when '\\', '\'', '"' then literal << char
          else
            raise UnsupportedSyntax.new("unsupported attribute escape \\#{char}; use a Crystal expression in {...}", origin)
          end
        else
          # A doubled backslash before #{...} represents a literal backslash
          # followed by a LIVE interpolation. Consume the pair atomically.
          if scanner.starts_with?("\\\\")
            scanner.take
            scanner.take
            literal << '\\'
            literal << '\\' unless quoted
          else
            literal << scanner.take
          end
        end
      end
      segments << AST::Segment.new(literal.to_s, literal_location) unless literal.empty?
      segments
    end
  end
end
