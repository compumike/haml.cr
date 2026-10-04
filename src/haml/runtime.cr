require "html"

module Haml
  module Runtime
    VOID_TAGS = %w(area base br col embed hr img input link meta param source track wbr)

    # These are presence/absence attributes (including the commonly treated
    # boolean-like `hidden`). Textual values remain possible, e.g. hidden's
    # "until-found" state. data-* and aria-* are intentionally NOT in this list.
    BOOLEAN_ATTRIBUTES = %w(allowfullscreen async autofocus autoplay checked controls default defer disabled formnovalidate hidden inert ismap itemscope loop multiple muted nomodule novalidate open playsinline readonly required reversed selected)

    def self.void_tag?(name : String) : Bool
      # This is equivalent to:
      #   VOID_TAGS.includes?(name.downcase)
      # which is the same as:
      #   VOID_TAGS.any? { |tag| tag.compare(name, case_insensitive: true).zero? } # no allocations
      # But this case dispatch is faster and still has zero allocations.

      # Keep in sync with VOID_TAGS:
      case name.bytesize
      when 2
        return true if "br".compare(name, case_insensitive: true).zero?
        return true if "hr".compare(name, case_insensitive: true).zero?
      when 3
        return true if "col".compare(name, case_insensitive: true).zero?
        return true if "img".compare(name, case_insensitive: true).zero?
        return true if "wbr".compare(name, case_insensitive: true).zero?
      when 4
        return true if "area".compare(name, case_insensitive: true).zero?
        return true if "base".compare(name, case_insensitive: true).zero?
        return true if "link".compare(name, case_insensitive: true).zero?
        return true if "meta".compare(name, case_insensitive: true).zero?
      when 5
        return true if "embed".compare(name, case_insensitive: true).zero?
        return true if "input".compare(name, case_insensitive: true).zero?
        return true if "param".compare(name, case_insensitive: true).zero?
        return true if "track".compare(name, case_insensitive: true).zero?
      when 6
        return true if "source".compare(name, case_insensitive: true).zero?
      end
      false
    end

    def self.write_preserved(io : IO, value : T) : Nil forall T
      # Preservation encodes newlines AFTER escaping, so &#10; is not escaped a
      # second time. An intermediate buffer is an explicit exception to the
      # streaming fast path; ordinary output does not allocate an escaped copy.
      escaped = String.build { |buffer| HTML.escape(value.to_s, buffer) }
      io << escaped.gsub("\r\n", "\n").gsub('\n', "&#10;")
    end

    def self.valid_attribute_name?(name : String) : Bool
      # Escaping attribute names is not sufficient: whitespace could still start
      # another attribute. Reject forbidden syntax instead. This applies equally
      # to authored names and keys from a dynamic attribute splat.
      return false if name.empty?
      name.each_char do |char|
        return false if char.ord <= 32 || char.ord == 127 || "\"'<>/=\u0000".includes?(char)
      end
      true
    end

    # All heterogeneous user values are normalized AT THE BOUNDARY. Storage has
    # one small, stable union regardless of the application's model types. An
    # expression passed to add/add_all is evaluated once by Crystal before this
    # method is entered. There is no repeated evaluation for boolean checks.
    class Attributes
      @values = {} of String => (String | Bool)
      @classes = [] of String
      @ids = [] of String
      @depth_limit : Int32

      def initialize(@depth_limit : Int32 = 64) : Nil
        raise ArgumentError.new("depth_limit must be positive") if @depth_limit < 1
      end

      def add(name : String, value : T) : Nil forall T
        validate_name(name)
        case name
        when "class"
          collect_tokens(value, @classes, true, 0)
          save_tokens("class", @classes, " ")
        when "id"
          collect_tokens(value, @ids, false, 0)
          save_tokens("id", @ids, "_")
        when "data", "aria"
          expand(name, value, 0)
        else
          set(name, value)
        end
      end

      def add_all(values : Hash | NamedTuple) : Nil
        # Only maps and named tuples are accepted. Unsupported types fail at
        # Crystal compile time instead of silently rendering inspect output.
        values.each { |key, value| add(key.to_s, value) }
      end

      def write_to(io : IO) : Nil
        @values.each do |name, value|
          io << ' ' << name
          unless value == true
            io << "=\""
            HTML.escape(value.to_s, io)
            io << '"'
          end
        end
      end

      private def validate_name(name : String) : Nil
        unless Runtime.valid_attribute_name?(name)
          raise ArgumentError.new("invalid HTML attribute name: #{name.inspect}")
        end
      end

      private def check_depth(depth : Int32) : Nil
        if depth > @depth_limit
          raise ArgumentError.new("attribute nesting exceeds #{@depth_limit}; check for a cycle")
        end
      end

      private def save_tokens(name : String, tokens : Array(String), separator : String) : Nil
        if tokens.empty?
          @values.delete(name)
        else
          @values[name] = tokens.join(separator)
        end
      end

      private def collect_tokens(value : Array | Tuple, target : Array(String),
                                 deduplicate : Bool, depth : Int32) : Nil
        check_depth(depth)
        value.each { |item| collect_tokens(item, target, deduplicate, depth + 1) }
      end

      private def collect_tokens(value : T, target : Array(String),
                                 deduplicate : Bool, depth : Int32) : Nil forall T
        check_depth(depth)
        return if value.nil? || value == false
        text = value.to_s
        # Class strings are token lists; IDs are not split at whitespace. Both
        # accept numeric values; zero and the string "false" are NOT falsey.
        if deduplicate
          text.split.each { |token| target << token unless target.includes?(token) }
        else
          target << text unless text.empty?
        end
      end

      private def expand(prefix : String, values : Hash | NamedTuple, depth : Int32) : Nil
        check_depth(depth)
        values.each do |key, value|
          suffix = key.to_s.tr("_", "-")
          raise ArgumentError.new("empty data/aria subkey") if suffix.empty?
          name = "#{prefix}-#{suffix}"
          validate_name(name)
          expand(name, value, depth + 1)
        end
      end

      private def expand(prefix : String, value : T, depth : Int32) : Nil forall T
        check_depth(depth)
        set(prefix, value)
      end

      private def set(name : String, value : T) : Nil forall T
        if value.nil?
          @values.delete(name)
        elsif Runtime::BOOLEAN_ATTRIBUTES.any? { |attribute| attribute.compare(name, case_insensitive: true).zero? } && value.is_a?(Bool)
          if value
            @values[name] = true
          else
            @values.delete(name)
          end
        else
          # In particular aria-hidden=false becomes aria-hidden="false".
          # Values are converted to text here and escaped by write_to.
          @values[name] = value.to_s
        end
      end
    end
  end
end
