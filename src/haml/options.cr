module Haml
  # Intentionally small. No implicit HTML4/XML modes, runtime global settings,
  # or compiler plugins. New switches should require corresponding specs.
  struct Options
    getter indent_width : Int32
    getter source_locations : Bool
    getter max_depth : Int32

    def initialize(@indent_width : Int32 = 2, @source_locations : Bool = true,
                   @max_depth : Int32 = 128) : Nil
      raise ArgumentError.new("indent_width must be between 1 and 8") unless (1..8).includes?(@indent_width)
      raise ArgumentError.new("max_depth must be between 1 and 256") unless (1..256).includes?(@max_depth)
    end
  end
end
