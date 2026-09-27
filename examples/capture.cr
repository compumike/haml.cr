require "../src/haml"

def card(title : String, &block : -> String) : String
  # The template-generated block returns a String containing already-rendered
  # markup. The helper escapes its own dynamic text, and the template uses
  # explicit `!=` to insert the resulting markup.
  body = yield
  String.build do |io|
    io << "<section class=\"card\"><h2>"
    Haml::Runtime.write_forced(io, title)
    io << "</h2>" << body << "</section>"
  end
end

name = "<Reader>"
print Haml.render_string(%q|!= card("Hello & welcome") do
  %p= name
|)
