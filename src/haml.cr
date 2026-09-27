# The application-facing entry point deliberately does not require the parser
# or compiler. Only the small rendering runtime and macros enter application
# semantic analysis. The separate macro-run program loads the compiler.
require "./haml/runtime"
require "./haml/macros"

module Haml
  VERSION = "0.1.0"
end
