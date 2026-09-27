module Haml
  # Locations use 1-based character columns, not byte offsets. The scanner uses
  # Char arrays so a multibyte character never becomes part of a delimiter.
  struct Location
    getter filename : String
    getter line : Int32
    getter column : Int32

    def initialize(@filename : String, @line : Int32 = 1, @column : Int32 = 1) : Nil
    end

    def advance(text : String) : Location
      line = @line
      column = @column
      text.each_char do |char|
        if char == '\n'
          line += 1
          column = 1
        else
          column += 1
        end
      end
      Location.new(@filename, line, column)
    end

    def to_s(io : IO) : Nil
      io << @filename << ':' << @line << ':' << @column
    end
  end

  class Error < Exception
    getter location : Location
    getter reason : String

    def initialize(@reason : String, @location : Location) : Nil
      super("#{@location}: #{@reason}")
    end
  end

  class SyntaxError < Error
  end

  class UnsupportedSyntax < SyntaxError
  end

  # Internal, recoverable signal used only while assembling multiline groups.
  # Parser turns an unfinished group at EOF into a normal located SyntaxError.
  class IncompleteExpression < SyntaxError
  end
end
