require "../src/haml"

record Post, title : String, subtitle : String, content : String
post = Post.new(title: "Welcome to Haml", subtitle: "A nice way to write templates", content: "Ruby & Crystal love Haml!")

puts Haml.render("#{__DIR__}/haml_demo.html.haml")
