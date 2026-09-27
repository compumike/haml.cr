require "../src/haml"

record Item, id : Int32, name : String, url : String, featured : Bool

class Page
  def initialize(@title : String, @items : Array(Item)) : Nil
  end

  Haml.def_to_s "#{__DIR__}/page.html.haml"
end

items = [
  Item.new(1, "A & B", "/item/1?x=1&y=2", true),
  Item.new(2, "Another item", "/item/2", false),
]
Page.new("Haml for Crystal", items).to_s(STDOUT)
