# Run this with: crystal run examples/haml_demo.cr

require "../src/haml"

record Post, title : String, subtitle : String, content : String
example_post = Post.new(title: "Welcome to Haml", subtitle: "A nice way to write templates", content: "Ruby & Crystal love Haml!")

def my_view(post : Post) : String
  Haml.render("#{__DIR__}/haml_demo.html.haml")
end

puts my_view(example_post)
