module Crig
  class EmptyListError < Exception
    def initialize
      super("Cannot create OneOrMany with an empty vector.")
    end
  end

  struct OneOrMany(T)
    include Enumerable(T)

    @first : T
    @rest : Array(T)

    def initialize(@first : T, @rest : Array(T) = [] of T)
    end

    def self.one(item : T) : self
      new(item)
    end

    def self.many(items : Enumerable(T)) : self
      values = items.to_a
      raise EmptyListError.new if values.empty?

      new(values[0], values[1..] || [] of T)
    end

    def self.merge(items : Enumerable(self)) : self
      many(items.flat_map(&.to_a))
    end

    def first : T
      @first
    end

    def first_ref : T
      @first
    end

    def first_mut : T
      @first
    end

    def last : T
      @rest.last? || @first
    end

    def last_ref : T
      last
    end

    def last_mut : T
      last
    end

    def rest : Array(T)
      @rest.dup
    end

    def push(item : T) : Nil
      @rest << item
    end

    def insert(index : Int, item : T) : Nil
      if index == 0
        old_first = @first
        @first = item
        @rest.insert(0, old_first)
      else
        @rest.insert(index - 1, item)
      end
    end

    def len : Int32
      (1 + @rest.size).to_i32
    end

    def empty? : Bool
      false
    end

    def each(& : T ->) : Nil
      yield @first
      @rest.each { |item| yield item }
    end

    def iter
      to_a.each
    end

    # Crystal does not expose Rust-style mutable references, so mutable iteration
    # uses the container's array semantics rather than dedicated iterator structs.
    def iter_mut
      values = to_a
      @first = values.shift
      @rest = values
      values.unshift(@first)
      values.each
    end

    def to_a : Array(T)
      [@first] + @rest
    end
  end
end
