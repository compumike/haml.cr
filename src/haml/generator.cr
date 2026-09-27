require "digest/sha256"
require "./parser"

module Haml
  # Emits a method BODY that writes to an existing IO. Native Crystal compilation
  # is the next stage; Haml.compile does not execute or type-check expressions.
  #
  # Formatting contract: no pretty-print indentation, one structural LF after
  # each rendered line/tag, unless suppressed by < or >. These modifiers affect
  # structural separators only, never arbitrary whitespace in runtime values.
  # This makes streaming possible without buffering an entire response.
  class Generator
    @code = IO::Memory.new
    @static = IO::Memory.new
    @counter = 0
    @prefix : String

    # Syntactic identifier validation must also reject reserved words. Merely
    # matching [a-z_] would let --io=end produce invalid generated Crystal.
    RESERVED_WORDS = %w(_ __DIR__ __FILE__ __LINE__ __END_LINE__ abstract alias annotation as asm begin break case class def do else elsif end ensure enum extend false for fun if in include instance_sizeof lib macro module next nil of offsetof out pointerof private protected require rescue return select self sizeof struct super then true type typeof uninitialized union unless until verbatim when while with yield)

    def self.valid_io_name?(name : String) : Bool
      !!(name =~ /\A[a-z_][a-zA-Z0-9_]*\z/) && !RESERVED_WORDS.includes?(name)
    end

    def initialize(@io_name : String, @options : Options, fingerprint : String) : Nil
      # Restrict the output target to a local variable. Accepting arbitrary
      # source here risks duplicate evaluation and source-code injection.
      unless Generator.valid_io_name?(@io_name)
        raise ArgumentError.new("io_name must be a Crystal local variable name")
      end
      @prefix = "__haml_#{Digest::SHA256.hexdigest(fingerprint)[0, 12]}_"
    end

    def generate(document : AST::Document) : String
      @code = IO::Memory.new
      @static = IO::Memory.new
      @counter = 0
      sequence(document.children, @io_name)
      flush(@io_name)
      # A consistent Nil return makes def_to_s and generated render methods
      # independent of whichever IO subclass's << overload was called last.
      @code << "nil\n"
      @code.to_s
    end

    private def temporary : String
      @counter += 1
      "#{@prefix}#{@counter}"
    end

    private def literal(text : String) : Nil
      @static << text
    end

    private def flush(io_name : String) : Nil
      return if @static.empty?
      @code << io_name << " << "
      # String#inspect produces a Crystal string literal. Do NOT use JSON
      # quoting or interpolate raw template content into generated source.
      @static.to_s.inspect(@code)
      @code << '\n'
      @static = IO::Memory.new
    end

    private def emits?(node : AST::Node) : Bool
      if code = node.as?(AST::Code)
        !code.kind.statement? && (code.children.any? { |child| emits?(child) } || code.branches.any? { |branch| emits?(branch) })
      else
        true
      end
    end

    private def outer_strip?(node : AST::Node?) : Bool
      node.is_a?(AST::Tag) && node.strip_outer?
    end

    private def sequence(nodes : Array(AST::Node), io_name : String,
                         final_newline : Bool = true) : Nil
      # Code statements are transparent to structural adjacency. Branching
      # constructs remain their own structural boundary; no look-behind across
      # runtime control flow or inspection of the IO's already-written bytes.
      visible = nodes.select { |node| emits?(node) }
      position = 0
      nodes.each do |node|
        newline = final_newline
        if emits?(node)
          following = visible[position + 1]?
          newline = (following ? true : final_newline) && !outer_strip?(node) && !outer_strip?(following)
          position += 1
        end
        emit(node, io_name, newline)
      end
    end

    private def emit(node : AST::Node, io_name : String, newline : Bool) : Nil
      case node
      when AST::Tag
        tag(node, io_name)
        literal("\n") if newline
      when AST::Text
        segments(node.segments, io_name, node.escape, node.escape_literal?)
        literal("\n") if newline
      when AST::Output
        output(node, io_name)
        literal("\n") if newline
      when AST::Code
        control(node, io_name, newline)
      when AST::Doctype
        literal("<!DOCTYPE html>")
        literal("\n") if newline
      when AST::Comment
        comment(node, io_name)
        literal("\n") if newline
      when AST::Filter
        filter(node, io_name, newline)
      else
        raise SyntaxError.new("unexpected AST node #{node.class}", node.location)
      end
    end

    private def tag(node : AST::Tag, io_name : String) : Nil
      literal("<#{node.name}")
      attributes(node.attributes, io_name)
      literal(">")
      return if Runtime.void_tag?(node.name)
      if inline = node.inline
        emit(inline, io_name, false)
      elsif !node.children.empty?
        first = node.children.find { |child| emits?(child) }
        literal("\n") if first && !node.strip_inner? && !outer_strip?(first)
        sequence(node.children, io_name, !node.strip_inner?)
      end
      # A non-void `%div/` is a childless <div></div>, never <div/>. HTML parsers
      # do not treat the latter as a self-closing div. XML mode is out of scope.
      literal("</#{node.name}>")
    end

    private def all_static?(attributes : Array(AST::Attribute)) : Bool
      attributes.all? { |attr| attr.kind.text? && attr.segments.none?(&.dynamic?) }
    end

    private def attributes(attributes : Array(AST::Attribute), io_name : String) : Nil
      return if attributes.empty?
      if all_static?(attributes)
        # Constant HTML-style attributes and shorthand can be normalized during
        # generation. Hash-style strings remain opaque Crystal expressions;
        # we do not eval them to chase a small optimization.
        writer = Runtime::Attributes.new
        attributes.each { |attr| writer.add(attr.name, attr.segments.map(&.text).join) }
        literal(String.build { |io| writer.write_to(io) })
        return
      end
      flush(io_name)
      writer = temporary
      @code << writer << " = ::Haml::Runtime::Attributes.new\n"
      attributes.each do |attr|
        if attr.kind.splat?
          @code << writer << ".add_all("
          expression(attr.expression)
          @code << ")\n"
        elsif attr.kind.text?
          @code << writer << ".add(" << attr.name.inspect << ", "
          attribute_string(attr.segments)
          @code << ")\n"
        else
          @code << writer << ".add(" << attr.name.inspect << ", "
          expression(attr.expression)
          @code << ")\n"
        end
      end
      @code << writer << ".write_to(" << io_name << ")\n"
    end

    private def attribute_string(parts : Array(AST::Segment)) : Nil
      unless parts.any?(&.dynamic?)
        @code << parts.map(&.text).join.inspect
        return
      end
      # Build the raw VALUE, then escape it once when the attribute writer
      # serializes it. Escaping each part here would double-escape ampersands.
      buffer = temporary
      @code << "(::String.build do |" << buffer << "|\n"
      parts.each do |part|
        @code << buffer << " << "
        if part.dynamic?
          expression(AST::Expression.new(part.text, part.location))
        else
          @code << part.text.inspect
        end
        @code << '\n'
      end
      @code << "end)"
    end

    private def segments(parts : Array(AST::Segment), io_name : String,
                         escape : AST::Escape, escape_literal : Bool = false,
                         preserve : Bool = false) : Nil
      parts.each do |part|
        if part.dynamic?
          flush(io_name)
          write_prefix(io_name, escape, preserve)
          expression(AST::Expression.new(part.text, part.location))
          write_suffix(io_name, escape, preserve)
        else
          text = escape_literal ? HTML.escape(part.text) : part.text
          text = text.gsub('\n', "&#10;") if preserve
          literal(text)
        end
      end
    end

    private def write_prefix(io_name : String, escape : AST::Escape, preserve : Bool) : Nil
      # Ordinary values stream directly to the destination IO. Preservation
      # still needs its helper because it replaces newlines after escaping.
      if preserve
        @code << "::Haml::Runtime.write_preserved(" << io_name << ", "
      elsif escape.raw?
        @code << '('
      else
        @code << "::HTML.escape("
      end
    end

    private def write_suffix(io_name : String, escape : AST::Escape, preserve : Bool) : Nil
      if preserve
        @code << ")\n"
      elsif escape.raw?
        @code << ").to_s(" << io_name << ")\n"
      else
        @code << ".to_s, " << io_name << ")\n"
      end
    end

    private def output(node : AST::Output, io_name : String) : Nil
      flush(io_name)
      write_prefix(io_name, node.escape, node.preserve?)
      if node.block?
        @code << "(\n"
        header(node.expression)
        buffer = temporary
        @code << "::String.build do |" << buffer << "|\n"
        sequence(node.children, buffer)
        flush(buffer)
        @code << "end\nend\n)"
      else
        expression(node.expression)
      end
      write_suffix(io_name, node.escape, node.preserve?)
    end

    private def control(node : AST::Code, io_name : String, newline : Bool) : Nil
      if node.kind.case? && node.branches.empty?
        raise SyntaxError.new("case requires at least one when/in branch", node.location)
      end
      flush(io_name)
      header(node.expression)
      unless node.kind.statement?
        sequence(node.children, io_name, newline)
        flush(io_name)
        node.branches.each do |branch|
          header(branch.expression)
          sequence(branch.children, io_name, newline)
          flush(io_name)
        end
        @code << "end\n"
      end
    end

    private def expression(value : AST::Expression) : Nil
      @code << "#<loc:push>\n" if @options.source_locations
      @code << '('
      location(value.location)
      @code << value.source
      # Put the close delimiter on a new physical line: a trailing Crystal
      # comment must not swallow it or the location-pop directive.
      @code << "\n)"
      @code << "#<loc:pop>" if @options.source_locations
    end

    private def header(value : AST::Expression) : Nil
      @code << "#<loc:push>\n" if @options.source_locations
      # Keep the location directive beside the first source token. A newline
      # between them advances Crystal's mapped line and resets its column.
      location(value.location)
      @code << value.source << '\n'
      @code << "#<loc:pop>\n" if @options.source_locations
    end

    private def location(value : Location) : Nil
      return unless @options.source_locations
      # These are Crystal compiler directives used by stdlib ECR, not C #line.
      # Specs check their spelling; native diagnostic mapping must also be
      # verified by scripts/integration. Retest with new Crystal versions.
      @code << "#<loc:" << value.filename.inspect << ',' << value.line << ',' << value.column << '>'
    end

    private def comment(node : AST::Comment, io_name : String) : Nil
      node.children.each { |child| assert_comment_static(child) }
      if node.children.empty?
        literal("<!-- #{node.text} -->")
      else
        literal("<!--#{node.text.empty? ? "" : " " + node.text}\n")
        sequence(node.children, io_name)
        literal("-->")
      end
    end

    private def assert_comment_static(node : AST::Node) : Nil
      case node
      when AST::Text
        if node.segments.any?(&.dynamic?) || node.segments.any? { |segment| segment.text.includes?("--") }
          raise UnsupportedSyntax.new("HTML comment bodies must be static and must not contain --", node.location)
        end
      when AST::Tag
        unless all_static?(node.attributes)
          raise UnsupportedSyntax.new("dynamic attributes are not supported inside HTML comments", node.location)
        end
        if node.name.includes?("--") || node.attributes.any? { |attr| attr.segments.any? { |segment| segment.text.includes?("--") } }
          raise SyntaxError.new("HTML comments must not contain --", node.location)
        end
        if inline = node.inline
          assert_comment_static(inline)
        end
        node.children.each { |child| assert_comment_static(child) }
      else
        raise UnsupportedSyntax.new("only static text and tags are supported inside HTML comments", node.location)
      end
    end

    private def filter(node : AST::Filter, io_name : String, newline : Bool) : Nil
      case node.name
      when "javascript", "css"
        # These filters deliberately do NOT interpolate. HTML escaping is not
        # JavaScript/CSS encoding; automatic interpolation here would suggest
        # a security guarantee this library cannot provide.
        tag_name = node.name == "javascript" ? "script" : "style"
        literal("<#{tag_name}>\n#{node.text}</#{tag_name}>")
      when "preserve"
        parts = Interpolation.parse(node.text, node.body_location, max_depth: @options.max_depth)
        segments(parts, io_name, AST::Escape::Auto, preserve: true)
      else
        # The final LF is the filter's structural separator. Internal blank
        # lines and indentation are preserved, not stripped/minified.
        body = node.text.ends_with?('\n') ? node.text[0...-1] : node.text
        parts = Interpolation.parse(body, node.body_location, max_depth: @options.max_depth)
        escaped = node.name == "escaped"
        segments(parts, io_name, escaped ? AST::Escape::Force : AST::Escape::Auto, escaped)
      end
      literal("\n") if newline
    end
  end
end
