require "../src/haml"

fruits = ["apple", "banana", "peach"]

puts Haml.render("#{__DIR__}/fruits.html.haml")
