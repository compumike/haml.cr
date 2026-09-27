require "./options"
require "./attribute_parser"

module Haml
  class Parser
    @lines : Array(String)
    @index = 0
    @attribute_parser : AttributeParser

    # This is a guard on the simple re-scan-on-continuation implementation.
    # Ordinary lines are scanned once; deliberately huge attribute blocks
    # should be moved into a helper/map instead of causing quadratic work.
    MAX_CONTINUATION_LINES = 256
    FILTERS                = %w(plain escaped preserve css javascript)

    def initialize(source : String, @filename : String = "inline.haml", @options : Options = Options.new) : Nil
      unless source.valid_encoding?
        raise SyntaxError.new("template must be valid UTF-8", Location.new(@filename))
      end
      if source.includes?('\0')
        raise SyntaxError.new("NUL is not permitted in a template", Location.new(@filename))
      end
      normalized = source.gsub("\r\n", "\n")
      if normalized.includes?('\r')
        raise SyntaxError.new("bare CR is not supported; use LF or CRLF", Location.new(@filename))
      end
      normalized = normalized[1..] if normalized.starts_with?('\uFEFF')
      @lines = normalized.split('\n')
      @lines.pop if normalized.ends_with?('\n')
      @attribute_parser = AttributeParser.new(@options.max_depth)
    end

    def parse : AST::Document
      # Parser instances are single-use; compiler API creates a new one per
      # call. Resetting here makes accidental repeated parse calls deterministic.
      @index = 0
      AST::Document.new(Location.new(@filename), sequence(0, 0))
    end

    private def blank?(line : String) : Bool
      line.strip.empty?
    end

    private def indentation(line : String, line_number : Int32, raw : Bool = false) : Int32
      spaces = 0
      line.each_char do |char|
        if char == ' '
          spaces += 1
        elsif char == '\t' && !raw
          raise SyntaxError.new("tabs are not allowed in structural indentation", Location.new(@filename, line_number, spaces + 1))
        else
          break
        end
      end
      spaces
    end

    private def sequence(indent : Int32, depth : Int32, case_owner : AST::Code? = nil) : Array(AST::Node)
      if depth > @options.max_depth
        raise SyntaxError.new("template nesting exceeds #{@options.max_depth}", Location.new(@filename, @index + 1))
      end
      nodes = [] of AST::Node
      while @index < @lines.size
        line = @lines[@index]
        if blank?(line)
          @index += 1
          next
        end
        actual = indentation(line, @index + 1)
        break if actual < indent
        if actual != indent
          raise SyntaxError.new("unexpected indentation: expected #{indent} spaces, got #{actual}", Location.new(@filename, @index + 1, actual + 1))
        end
        location = Location.new(@filename, @index + 1, indent + 1)
        text = line[indent..]
        @index += 1

        if text.starts_with?("-#")
          skip_silent_comment(indent)
          next
        end
        if text.starts_with?(':')
          name = text[1..].strip
          unless FILTERS.includes?(name)
            raise UnsupportedSyntax.new("unknown/unsupported filter :#{name}", location)
          end
          body, body_location = raw_block(indent)
          node = AST::Filter.new(location, name, body, body_location)
        else
          node = parse_continued(text, location)
          following = next_nonblank_indent
          if following && following > indent
            child_indent = indent + @options.indent_width
            if following != child_indent
              raise SyntaxError.new("indentation must increase by #{@options.indent_width} spaces", Location.new(@filename, @index + 1))
            end
            attach_children(node, child_indent, depth + 1)
          end
          validate_node(node)
        end

        if code = node.as?(AST::Code)
          if code.kind.branch?
            owner = case_owner || nodes.last?.as?(AST::Code)
            unless owner
              raise SyntaxError.new("orphan #{code.keyword}; branches must immediately follow their owning block", code.location)
            end
            attach_branch(owner, code)
            next
          end
        end
        if case_owner
          raise SyntaxError.new("only when/in/else branches may be direct children of case", node.location)
        end
        nodes << node
      end
      nodes
    end

    private def next_nonblank_indent : Int32?
      offset = @index
      while offset < @lines.size
        unless blank?(@lines[offset])
          return indentation(@lines[offset], offset + 1)
        end
        offset += 1
      end
      nil
    end

    private def skip_silent_comment(indent : Int32) : Nil
      # Deliberately do not parse or validate the commented subtree. Even
      # unsupported filters or malformed Crystal are safe to comment out.
      while @index < @lines.size
        line = @lines[@index]
        break unless blank?(line) || indentation(line, @index + 1, raw: true) > indent
        @index += 1
      end
    end

    private def raw_block(indent : Int32) : Tuple(String, Location)
      base = indent + @options.indent_width
      origin = Location.new(@filename, @index + 1, base + 1)
      text = String.build do |io|
        while @index < @lines.size
          line = @lines[@index]
          if blank?(line)
            io << '\n'
            @index += 1
            next
          end
          actual = indentation(line, @index + 1, raw: true)
          break if actual <= indent
          if actual < base
            raise SyntaxError.new("filter content must be indented at least #{base} spaces", Location.new(@filename, @index + 1))
          end
          io << line[base..] << '\n'
          @index += 1
        end
      end
      {text, origin}
    end

    private def parse_continued(text : String, location : Location) : AST::Node
      count = 1
      loop do
        begin
          return line_node(text, location)
        rescue ex : IncompleteExpression
          if @index >= @lines.size
            raise SyntaxError.new(ex.reason, ex.location)
          end
          if count >= MAX_CONTINUATION_LINES
            raise SyntaxError.new("multiline construct exceeds #{MAX_CONTINUATION_LINES} lines", location)
          end
          text += "\n" + @lines[@index]
          @index += 1
          count += 1
        end
      end
    end

    private def line_node(text : String, location : Location) : AST::Node
      if text.starts_with?("!!!")
        unless {"!!!", "!!! 5"}.includes?(text.strip)
          raise UnsupportedSyntax.new("only the HTML5 doctype (!!! or !!! 5) is supported", location)
        end
        return AST::Doctype.new(location)
      end
      if text.starts_with?("%") || text.starts_with?(".") || (text.starts_with?("#") && !text.starts_with?("\#{"))
        return tag_node(text, location)
      end
      if text.starts_with?("/")
        if text.starts_with?("/[") || text.starts_with?("/![")
          raise UnsupportedSyntax.new("conditional comments are not supported", location)
        end
        comment = text[1..].strip
        if comment.includes?("--") || comment.ends_with?('-')
          raise SyntaxError.new("HTML comments must not contain -- or end in -", location)
        end
        return AST::Comment.new(location, comment)
      end
      if text.starts_with?("-")
        expression = read_code(text[1..], location.advance("-"))
        kind, keyword = classify_code(expression)
        return AST::Code.new(location, expression, kind, keyword)
      end
      content_node(text, location)
    end

    private def content_node(text : String, location : Location) : AST::Node
      # Longest prefix first. Haml's == is INTERPOLATED TEXT, unlike Slang's
      # raw-output ==. Keeping that distinction avoids a dangerous migration.
      if text.starts_with?("&==") || text.starts_with?("!==") || text.starts_with?("==")
        length = text.starts_with?("==") ? 2 : 3
        mode = text.starts_with?("&") ? AST::Escape::Force : (text.starts_with?("!") ? AST::Escape::Raw : AST::Escape::Auto)
        body = text[length..].lstrip
        offset = text.size - body.size
        return AST::Text.new(location,
          Interpolation.parse(body, location.advance(text[0, offset]), max_depth: @options.max_depth),
          mode, mode.force?)
      end
      escape = AST::Escape::Auto
      preserve = false
      prefix = 0
      if text.starts_with?("!=")
        escape = AST::Escape::Raw
        prefix = 2
      elsif text.starts_with?("&=")
        escape = AST::Escape::Force
        prefix = 2
      elsif text.starts_with?("=")
        prefix = 1
      elsif text.starts_with?("~")
        preserve = true
        prefix = 1
      end
      if prefix > 0
        expression = read_code(text[prefix..], location.advance(text[0, prefix]))
        output = AST::Output.new(location, expression, escape, preserve)
        output.block = do_header?(visible_code(expression))
        return output
      end
      if text.starts_with?("\\")
        text = text[1..]
        location = location.advance("\\")
      elsif text.starts_with?("! ")
        text = text[2..]
        location = location.advance("! ")
        escape = AST::Escape::Raw
      elsif text.starts_with?("& ")
        text = text[2..]
        location = location.advance("& ")
        escape = AST::Escape::Force
        return AST::Text.new(location, Interpolation.parse(text, location, max_depth: @options.max_depth), escape, true)
      end
      AST::Text.new(location, Interpolation.parse(text, location, max_depth: @options.max_depth), escape)
    end

    private def tag_node(text : String, location : Location) : AST::Tag
      scanner = Scanner.new(text, location, @options.max_depth)
      name = "div"
      if scanner.current == '%'
        scanner.take
        start = scanner.index
        unless scanner.current.ascii_letter?
          raise SyntaxError.new("tag names must start with an ASCII letter", scanner.location)
        end
        while scanner.current.ascii_alphanumeric? || "_:-".includes?(scanner.current)
          scanner.take
        end
        name = scanner.slice(start)
      end
      tag = AST::Tag.new(location, name)
      loop do
        case scanner.current
        when '.', '#'
          attr_name = scanner.take == '.' ? "class" : "id"
          origin = scanner.location
          start = scanner.index
          while scanner.current.ascii_alphanumeric? || "_-:".includes?(scanner.current)
            scanner.take
          end
          value = scanner.slice(start)
          raise SyntaxError.new("empty #{attr_name} shorthand", origin) if value.empty?
          tag.attributes << @attribute_parser.literal(attr_name, value, origin)
        when '{'
          tag.attributes.concat(@attribute_parser.hash_style(scanner.group))
        when '('
          tag.attributes.concat(@attribute_parser.html_style(scanner.group(template_strings: true)))
        when '['
          raise UnsupportedSyntax.new("object references are not supported; use id:/class: helpers", scanner.location)
        when '<'
          raise SyntaxError.new("duplicate < modifier", scanner.location) if tag.strip_inner?
          scanner.take
          tag.strip_inner = true
        when '>'
          raise SyntaxError.new("duplicate > modifier", scanner.location) if tag.strip_outer?
          scanner.take
          tag.strip_outer = true
        when '/'
          scanner.take
          tag.explicit_empty = true
          unless scanner.remaining.strip.empty?
            raise SyntaxError.new("an explicit empty tag cannot have content", scanner.location)
          end
          break
        else
          break
        end
      end
      unless scanner.eof?
        # A space separates ordinary inline text, while =/!=/&=/~ may directly
        # follow the tag header, just as in Ruby Haml.
        char = scanner.current
        unless char.ascii_whitespace? || "=!&~".includes?(char)
          raise SyntaxError.new("unexpected character after tag header #{char.inspect}", scanner.location)
        end
        scanner.skip_space
        unless scanner.eof?
          tag.inline = content_node(scanner.remaining, scanner.location)
        end
      end
      tag
    end

    private def read_code(text : String, location : Location) : AST::Expression
      expression = Scanner.expression(text, location)
      scanner = Scanner.new(expression.source, expression.location, @options.max_depth)
      scanner.read_until
      if visible_code(expression).empty?
        raise SyntaxError.new("missing Crystal expression", expression.location)
      end
      expression
    end

    private def visible_code(expression : AST::Expression) : String
      Scanner.new(expression.source, expression.location, @options.max_depth).read_until(stop_at_comment: true).source.strip
    end

    private def do_header?(code : String) : Bool
      !!(code =~ /\bdo(?:\s*\|[^|]*\|)?\s*\z/)
    end

    private def classify_code(expression : AST::Expression) : Tuple(AST::CodeKind, String)
      code = visible_code(expression)
      keyword = code.split(/\s+/, 2).first
      case keyword
      when "if"     then {AST::CodeKind::If, keyword}
      when "unless" then {AST::CodeKind::Unless, keyword}
      when "while"  then {AST::CodeKind::While, keyword}
      when "until"  then {AST::CodeKind::Until, keyword}
      when "case"   then {AST::CodeKind::Case, keyword}
      when "begin"  then {AST::CodeKind::Begin, keyword}
      when "else", "elsif", "when", "in", "rescue", "ensure"
        {AST::CodeKind::Branch, keyword}
      when "end"
        raise SyntaxError.new("do not write - end; indentation closes blocks", expression.location)
      when "def", "class", "struct", "module", "lib", "macro", "fun", "require"
        raise UnsupportedSyntax.new("define types, methods and imports in .cr files, not templates", expression.location)
      else
        if code =~ /\A\w+\s*=\s*(if|unless|case|begin)\b/
          raise UnsupportedSyntax.new("assignment to an indentation block is not supported; use a helper", expression.location)
        end
        {do_header?(code) ? AST::CodeKind::Do : AST::CodeKind::Statement, ""}
      end
    end

    private def attach_children(node : AST::Node, indent : Int32, depth : Int32) : Nil
      case node
      when AST::Tag
        if output = node.inline.as?(AST::Output)
          unless output.block?
            raise SyntaxError.new("inline output cannot also have nested content", node.location)
          end
          output.children.concat(sequence(indent, depth))
        elsif node.inline
          raise SyntaxError.new("a tag cannot have both inline text and nested content", node.location)
        else
          node.children.concat(sequence(indent, depth))
        end
      when AST::Code
        if node.kind.statement?
          raise SyntaxError.new("nested content requires a Crystal block header ending in do, or a control keyword", node.location)
        end
        if node.kind.case?
          sequence(indent, depth, node)
        else
          node.children.concat(sequence(indent, depth))
        end
      when AST::Output
        unless node.block?
          raise UnsupportedSyntax.new("output with nested content requires a do block; see the capture convention", node.location)
        end
        node.children.concat(sequence(indent, depth))
      when AST::Comment
        node.children.concat(sequence(indent, depth))
      else
        raise SyntaxError.new("this line cannot have nested content", node.location)
      end
    end

    private def validate_node(node : AST::Node) : Nil
      if tag = node.as?(AST::Tag)
        if (Runtime.void_tag?(tag.name) || tag.explicit_empty?) && (tag.inline || !tag.children.empty?)
          raise SyntaxError.new("empty/void tag #{tag.name} cannot have content", tag.location)
        end
      end
    end

    private def attach_branch(owner : AST::Code, branch : AST::Code) : Nil
      previous = owner.branches.map(&.keyword)
      valid = case owner.kind
              when .if?     then {"elsif", "else"}.includes?(branch.keyword) && !previous.includes?("else")
              when .unless? then branch.keyword == "else" && previous.empty?
              when .case?
                {"when", "in", "else"}.includes?(branch.keyword) && !previous.includes?("else") &&
                  !(branch.keyword == "in" && previous.includes?("when")) &&
                  !(branch.keyword == "when" && previous.includes?("in"))
              when .begin?
                case branch.keyword
                when "rescue" then !previous.includes?("else") && !previous.includes?("ensure")
                when "else"   then previous.includes?("rescue") && !previous.includes?("else") && !previous.includes?("ensure")
                when "ensure" then !previous.includes?("ensure")
                else               false
                end
              else false
              end
      unless valid
        raise SyntaxError.new("#{branch.keyword} is not a valid next branch of #{owner.kind}", branch.location)
      end
      owner.branches << branch
    end
  end
end
