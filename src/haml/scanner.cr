require "./ast"

module Haml
  # A boundary scanner, NOT a second Crystal parser. Its sole job is to keep
  # commas/braces inside strings, regexes and nested groups from becoming Haml
  # delimiters. Syntax, overloads and types remain Crystal's responsibility.
  #
  # Deliberate boundary: heredocs and Crystal macro bodies are rejected. Bare
  # slash regexes work in operand positions. The ambiguous `method /regexp/`
  # form is rejected; write `method(/regexp/)` or `%r(regexp)` instead. Ordinary
  # `a / b` and `a/b` division work. See docs/SYNTAX.md for the exact contract.
  class Scanner
    getter index : Int32
    getter location : Location
    @chars : Array(Char)
    @depth = 0

    OPERAND_KEYWORDS = %w(if unless when in return yield then else elsif rescue ensure case while until and or not do)
    OPEN_TO_CLOSE    = {'(' => ')', '[' => ']', '{' => '}'}

    def initialize(source : String, @location : Location, @max_depth : Int32 = 128) : Nil
      @chars = source.chars
      @index = 0
    end

    def eof? : Bool
      @index >= @chars.size
    end

    def current : Char
      peek
    end

    def peek(offset : Int32 = 0) : Char
      @chars[@index + offset]? || '\0'
    end

    def starts_with?(text : String) : Bool
      chars = text.chars
      chars.each_with_index do |char, offset|
        return false unless peek(offset) == char
      end
      true
    end

    def take : Char
      raise IncompleteExpression.new("unexpected end of input", @location) if eof?
      char = @chars[@index]
      @index += 1
      @location = if char == '\n'
                    Location.new(@location.filename, @location.line + 1, 1)
                  else
                    Location.new(@location.filename, @location.line, @location.column + 1)
                  end
      char
    end

    def slice(start : Int32, finish : Int32 = @index) : String
      @chars[start, finish - start].join
    end

    def remaining : String
      slice(@index, @chars.size)
    end

    def skip_space : Nil
      while !eof? && current.ascii_whitespace?
        take
      end
    end

    def skip_space_and_comments : Nil
      loop do
        skip_space
        break unless current == '#'
        while !eof? && current != '\n'
          take
        end
      end
    end

    def self.expression(text : String, location : Location) : AST::Expression
      # Trimming is paired with a corresponding source-location adjustment. The
      # end is trimmed as well, but embedded physical newlines are retained.
      left = text.size - text.lstrip.size
      AST::Expression.new(text.strip, location.advance(text[0, left]))
    end

    def group(template_strings : Bool = false) : AST::Expression
      # Read one complete group, returning only its interior. Cursor lands AFTER
      # the matching delimiter. This primitive is shared by attributes and #{...}.
      start_location = @location
      open = take
      close = OPEN_TO_CLOSE[open]?
      raise SyntaxError.new("expected an opening delimiter", start_location) unless close
      enter_depth(start_location)
      begin
        content_location = @location
        content_start = @index
        read_until(close.to_s, template_strings: template_strings)
        unless current == close
          raise IncompleteExpression.new("unclosed #{open.inspect}; expected #{close.inspect}", start_location)
        end
        result = AST::Expression.new(slice(content_start), content_location)
        take
        result
      ensure
        @depth -= 1
      end
    end

    def read_until(stops : String = "", whitespace : Bool = false,
                   # Returns a source slice without consuming a top-level stop character.
                   # Reading a nested group/quoted token consumes it atomically. This is why
                   # `{title: "a,b", data: {x: 1}}` does not need regular-expression splitting.
                   stop_at_comment : Bool = false, template_strings : Bool = false) : AST::Expression
      start = @index
      origin = @location
      operand = true
      spaced = false
      while !eof?
        char = current
        break if stops.includes?(char)
        break if whitespace && char.ascii_whitespace?
        if char.ascii_whitespace?
          take
          spaced = true
          next
        end
        if char == '#'
          break if stop_at_comment
          while !eof? && current != '\n'
            take
          end
          spaced = true
          next
        end
        if starts_with?("<<-") || starts_with?("<<~")
          raise UnsupportedSyntax.new("heredocs are not supported; use a helper or a quoted multiline string", @location)
        end
        if starts_with?("{{") || starts_with?("{%")
          raise UnsupportedSyntax.new("Crystal macro bodies are not supported inside Haml", @location)
        end
        case char
        when '(', '[', '{'
          group
          operand = false
        when ')', ']', '}'
          raise SyntaxError.new("unexpected closing delimiter #{char.inspect}", @location)
        when '"', '\'', '`'
          quoted(template_strings)
          operand = false
        when '%'
          if percent_literal?
            percent_literal
            operand = false
          else
            take
            operand = true
          end
        when '/'
          if operand
            regex_literal
            operand = false
          elsif starts_with?("//")
            2.times { take }
            take if current == '='
            operand = true
          elsif spaced && !peek(1).ascii_whitespace? && peek(1) != '='
            raise UnsupportedSyntax.new("ambiguous slash; use spaces for division or parentheses around a regex argument", @location)
          else
            take
            take if current == '='
            operand = true
          end
        else
          if char.ascii_alphanumeric? || char == '_' || char == '@'
            word_start = @index
            take
            while current.ascii_alphanumeric? || current == '_' || current == '?' || current == '!'
              # Do not consume != as the end of an identifier.
              break if current == '!' && peek(1) == '='
              take
            end
            operand = OPERAND_KEYWORDS.includes?(slice(word_start))
          elsif char == '.'
            take
            # Receiver/member syntax is not an operand start for /regex/.
            operand = false
          else
            take
            operand = true
          end
        end
        spaced = false
      end
      AST::Expression.new(slice(start), origin)
    end

    def quoted(template_string : Bool = false) : AST::Expression
      # A quoted Crystal token, including nested interpolation. The returned
      # string includes its quotes. Single quotes denote Crystal Char literals;
      # the HTML-attribute parser has a separate Haml string convention.
      origin = @location
      start = @index
      quote = take
      enter_depth(origin)
      begin
        loop do
          raise IncompleteExpression.new("unclosed quoted string", origin) if eof?
          if current == '\\'
            take
            raise IncompleteExpression.new("unfinished escape", origin) if eof?
            take
          elsif current == quote
            take
            break
          elsif (quote != '\'' || template_string) && starts_with?("\#{")
            take
            group
          else
            take
          end
        end
      ensure
        @depth -= 1
      end
      AST::Expression.new(slice(start), origin)
    end

    private def enter_depth(location : Location) : Nil
      @depth += 1
      if @depth > @max_depth
        raise SyntaxError.new("expression nesting exceeds #{@max_depth}", location)
      end
    end

    private def percent_literal? : Bool
      return false unless current == '%'
      offset = "qQwWirx".includes?(peek(1)) ? 2 : 1
      "([{<|".includes?(peek(offset))
    end

    private def percent_literal : Nil
      origin = @location
      take # %
      kind = '\0'
      if "qQwWirx".includes?(current)
        kind = take
      end
      open = take
      close = case open
              when '(' then ')'
              when '[' then ']'
              when '{' then '}'
              when '<' then '>'
              else          open
              end
      interpolated = kind != 'q' && kind != 'w' && kind != 'i'
      enter_depth(origin)
      begin
        nesting = 0
        loop do
          raise IncompleteExpression.new("unclosed percent literal", origin) if eof?
          if current == '\\'
            take
            # Crystal's %q does not interpret even delimiter escapes. A
            # following ')' can close %q(...), unlike a normal quoted string.
            # %w/%i still consume escaped delimiters and whitespace. Keep
            # this distinction aligned with next_string_token in Crystal.
            unless kind == 'q'
              raise IncompleteExpression.new("unfinished escape", origin) if eof?
              take
            end
          elsif interpolated && starts_with?("\#{")
            take
            group
          elsif current == close
            take
            break if nesting == 0
            nesting -= 1
          elsif open != close && current == open
            nesting += 1
            if nesting > @max_depth
              raise SyntaxError.new("percent literal nesting exceeds #{@max_depth}", origin)
            end
            take
          else
            take
          end
        end
        while kind == 'r' && current.ascii_letter?
          take
        end
      ensure
        @depth -= 1
      end
    end

    private def regex_literal : Nil
      origin = @location
      take # /
      # Crystal's lexer treats an unescaped slash as the literal terminator,
      # including inside a regex character class. PCRE syntax is interpreted
      # later; an embedded slash must be written as \/ here. Do not apply the
      # more permissive delimiter rules used by some other language lexers.
      enter_depth(origin)
      begin
        loop do
          raise IncompleteExpression.new("unclosed slash regex", origin) if eof?
          if current == '\\'
            take
            raise IncompleteExpression.new("unfinished regex escape", origin) if eof?
            take
          elsif starts_with?("\#{")
            take
            group
          elsif current == '/'
            take
            while current.ascii_letter?
              take
            end
            break
          else
            take
          end
        end
      ensure
        @depth -= 1
      end
    end
  end
end
