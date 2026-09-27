require "./interpolation"
require "./runtime"

module Haml
  # This parser understands ONLY the outer attribute list. In `{...}` each
  # value is an opaque Crystal expression. No heterogeneous Hash is generated
  # merely because the template has heterogeneous attributes.
  class AttributeParser
    def initialize(@max_depth : Int32 = 128) : Nil
    end

    def hash_style(group : AST::Expression) : Array(AST::Attribute)
      scanner = Scanner.new(group.source, group.location, @max_depth)
      attributes = [] of AST::Attribute
      loop do
        scanner.skip_space_and_comments
        break if scanner.eof?
        if scanner.starts_with?("**")
          2.times { scanner.take }
          expression = required(scanner.read_until(","))
          attributes << AST::Attribute.new("", AST::AttributeKind::Splat, expression)
        else
          name_location = scanner.location
          legacy = scanner.current == ':'
          scanner.take if legacy
          name = read_name(scanner)
          validate_name(name, name_location)
          scanner.skip_space
          if scanner.starts_with?("=>")
            2.times { scanner.take }
          elsif scanner.current == ':' && !legacy
            scanner.take
          else
            raise SyntaxError.new("expected ':' or '=>' after attribute name; use **attrs for a map", scanner.location)
          end
          expression = required(scanner.read_until(","))
          attributes << AST::Attribute.new(name, AST::AttributeKind::Expression, expression)
        end
        scanner.skip_space_and_comments
        break if scanner.eof?
        unless scanner.current == ','
          raise SyntaxError.new("expected ',' between attributes", scanner.location)
        end
        scanner.take
      end
      attributes
    end

    def html_style(group : AST::Expression) : Array(AST::Attribute)
      scanner = Scanner.new(group.source, group.location, @max_depth)
      attributes = [] of AST::Attribute
      loop do
        scanner.skip_space_and_comments
        break if scanner.eof?
        origin = scanner.location
        name = read_html_name(scanner)
        validate_name(name, origin)
        unless name =~ /\A[A-Za-z_:@][A-Za-z0-9_.:@-]*\z/
          raise SyntaxError.new("invalid HTML-style attribute name; wrap expressions containing spaces in parentheses", origin)
        end
        scanner.skip_space
        if scanner.current == '='
          scanner.take
          scanner.skip_space
          if scanner.current == '"' || scanner.current == '\''
            token = scanner.quoted(template_string: true)
            content = token.source[1...-1]
            segments = Interpolation.parse(content, token.location.advance(token.source[0, 1]), true, @max_depth)
            attributes << AST::Attribute.new(name, AST::AttributeKind::Text, token, segments)
          else
            expression = required(scanner.read_until(whitespace: true))
            attributes << AST::Attribute.new(name, AST::AttributeKind::Expression, expression)
          end
          unless scanner.eof? || scanner.current.ascii_whitespace?
            raise SyntaxError.new("HTML-style attributes must be separated by whitespace", scanner.location)
          end
        else
          # No `=` is the Haml spelling of a true value, not an empty string.
          attributes << AST::Attribute.new(name, AST::AttributeKind::Expression,
            AST::Expression.new("true", origin))
        end
      end
      attributes
    end

    def literal(name : String, value : String, location : Location) : AST::Attribute
      validate_name(name, location)
      AST::Attribute.new(name, AST::AttributeKind::Text,
        AST::Expression.new(value, location), [AST::Segment.new(value, location)])
    end

    private def required(expression : AST::Expression) : AST::Expression
      trimmed = Scanner.expression(expression.source, expression.location)
      # Leading comments on a multiline value are allowed; a comment alone
      # is not a value. Advance the source location along with the omitted
      # prefix so the Crystal diagnostic still points at the expression.
      scanner = Scanner.new(trimmed.source, trimmed.location, @max_depth)
      scanner.skip_space_and_comments
      raise SyntaxError.new("missing attribute value", trimmed.location) if scanner.eof?
      Scanner.expression(scanner.remaining, scanner.location)
    end

    private def read_name(scanner : Scanner) : String
      if scanner.current == '"' || scanner.current == '\''
        token = scanner.quoted(template_string: true)
        segments = Interpolation.parse(token.source[1...-1], token.location.advance(token.source[0, 1]), true, @max_depth)
        if segments.any?(&.dynamic?)
          raise UnsupportedSyntax.new("attribute names must be static; use **attrs for dynamic keys", token.location)
        end
        segments.map(&.text).join
      else
        start = scanner.index
        while scanner.current.ascii_alphanumeric? || scanner.current == '_' || scanner.current == '-'
          scanner.take
        end
        scanner.slice(start)
      end
    end

    private def read_html_name(scanner : Scanner) : String
      start = scanner.index
      until scanner.eof? || scanner.current.ascii_whitespace? || scanner.current == '='
        scanner.take
      end
      scanner.slice(start)
    end

    private def validate_name(name : String, location : Location) : Nil
      unless Runtime.valid_attribute_name?(name)
        raise SyntaxError.new("invalid HTML attribute name: #{name.inspect}", location)
      end
    end
  end
end
