module Ssherlock
  # One resolved check: the documentation description, the shell command, and
  # the declarative analysis metadata (grouping category, and — for control
  # checks — severity + expected). Metadata fields are nil for plain inventory
  # checks.
  struct Check
    getter description : String?
    getter command : String
    getter category : String?
    getter severity : String?
    getter expected : String?

    def initialize(@command : String, @description : String? = nil,
                   @category : String? = nil, @severity : String? = nil,
                   @expected : String? = nil)
    end
  end
end
