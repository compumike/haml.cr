require "./error"

module Haml
  # These are compiler data types, not a runtime DOM. Expressions deliberately
  # remain source text: Crystal, not this library, resolves names and types.
  module AST
    enum Escape
      Auto  # escape all dynamic values
      Force # explicit escaping (the &= spelling)
      Raw   # explicit != / ! interpolation
    end

    struct Expression
      getter source : String
      getter location : Location

      def initialize(@source : String, @location : Location) : Nil
      end
    end

    struct Segment
      getter text : String
      getter location : Location
      getter? dynamic : Bool

      def initialize(@text : String, @location : Location, @dynamic : Bool = false) : Nil
      end
    end

    abstract class Node
      getter location : Location

      def initialize(@location : Location) : Nil
      end
    end

    class Document < Node
      getter children : Array(Node)

      def initialize(location : Location, @children : Array(Node)) : Nil
        super(location)
      end
    end

    class Text < Node
      getter segments : Array(Segment)
      getter escape : Escape
      getter? escape_literal : Bool

      def initialize(location : Location, @segments : Array(Segment),
                     @escape : Escape = Escape::Auto, @escape_literal : Bool = false) : Nil
        super(location)
      end
    end

    class Output < Node
      getter expression : Expression
      getter escape : Escape
      getter? preserve : Bool
      # An output block uses a String-returning block convention, NOT Rails'
      # mutable output-buffer protocol. See the component example and design.
      getter children = [] of Node
      property? block : Bool = false

      def initialize(location : Location, @expression : Expression,
                     @escape : Escape = Escape::Auto, @preserve : Bool = false) : Nil
        super(location)
      end
    end

    enum CodeKind
      Statement
      If
      Unless
      While
      Until
      Case
      Begin
      Do
      Branch
    end

    class Code < Node
      getter expression : Expression
      getter kind : CodeKind
      getter keyword : String
      getter children = [] of Node
      # Branches belong to their actual parent, never to a global indent table.
      # This prevents a later `else` from attaching across unrelated siblings.
      getter branches = [] of Code

      def initialize(location : Location, @expression : Expression,
                     @kind : CodeKind, @keyword : String) : Nil
        super(location)
      end
    end

    enum AttributeKind
      Expression
      Text
      Splat
    end

    class Attribute
      getter name : String
      getter kind : AttributeKind
      getter expression : Expression
      getter segments : Array(Segment)

      def initialize(@name : String, @kind : AttributeKind,
                     @expression : Expression, @segments : Array(Segment) = [] of Segment) : Nil
      end
    end

    class Tag < Node
      getter name : String
      getter attributes = [] of Attribute
      getter children = [] of Node
      property inline : Node? = nil
      property? strip_inner : Bool = false
      property? strip_outer : Bool = false
      property? explicit_empty : Bool = false

      def initialize(location : Location, @name : String) : Nil
        super(location)
      end
    end

    class Comment < Node
      getter text : String
      getter children = [] of Node

      def initialize(location : Location, @text : String) : Nil
        super(location)
      end
    end

    class Doctype < Node
    end

    class Filter < Node
      getter name : String
      getter text : String
      getter body_location : Location

      def initialize(location : Location, @name : String, @text : String,
                     @body_location : Location) : Nil
        super(location)
      end
    end
  end
end
