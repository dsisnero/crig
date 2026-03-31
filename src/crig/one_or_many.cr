module Crig
  class EmptyListError < Exception
    def initialize
      super("Cannot create OneOrMany with an empty vector.")
    end
  end

  module StringOrOneOrManyConverter(T)
    def self.from_json(pull : JSON::PullParser) : Crig::OneOrMany(T)
      Crig::OneOrMany(T).from_json_any(JSON::Any.new(pull))
    end

    def self.to_json(value : Crig::OneOrMany(T), json : JSON::Builder) : Nil
      value.to_json(json)
    end
  end

  module StringOrOptionOneOrManyConverter(T)
    def self.from_json(pull : JSON::PullParser) : Crig::OneOrMany(T)?
      if pull.kind.null?
        pull.read_null
        nil
      else
        Crig::OneOrMany(T).from_json_any(JSON::Any.new(pull))
      end
    end

    def self.to_json(value : Crig::OneOrMany(T)?, json : JSON::Builder) : Nil
      if value
        value.to_json(json)
      else
        json.null
      end
    end
  end

  struct OneOrMany(T)
    include Enumerable(T)

    @first : T
    @rest : Array(T)

    struct Iter(T)
      include Iterator(T)

      def initialize(@values : Array(T), @index : Int32 = 0)
      end

      def next
        return stop if @index >= @values.size

        value = @values[@index]
        @index += 1
        value
      end

      def size_hint : {Int32, Int32?}
        remaining = (@values.size - @index).to_i32
        remaining > 0 ? {1, remaining} : {0, 0}
      end
    end

    struct IntoIter(T)
      include Iterator(T)

      def initialize(@values : Array(T), @index : Int32 = 0)
      end

      def next
        return stop if @index >= @values.size

        value = @values[@index]
        @index += 1
        value
      end

      def size_hint : {Int32, Int32?}
        remaining = (@values.size - @index).to_i32
        remaining > 0 ? {1, remaining} : {0, 0}
      end
    end

    struct IterMut(T)
      include Iterator(T)

      def initialize(@values : Array(T), @index : Int32 = 0)
      end

      def next
        return stop if @index >= @values.size

        value = @values[@index]
        @index += 1
        value
      end

      def size_hint : {Int32, Int32?}
        remaining = (@values.size - @index).to_i32
        remaining > 0 ? {1, remaining} : {0, 0}
      end
    end

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

    # ameba:disable Naming/PredicateName
    def is_empty : Bool
      empty?
    end

    # ameba:enable Naming/PredicateName

    def each(& : T ->) : Nil
      yield @first
      @rest.each { |item| yield item }
    end

    def iter : Iter(T)
      Iter(T).new(to_a)
    end

    def into_iter : IntoIter(T)
      IntoIter(T).new(to_a)
    end

    # Crystal cannot yield Rust-style mutable references, so this iterator returns
    # the same underlying objects for reference types while preserving visit order.
    def iter_mut : IterMut(T)
      IterMut(T).new(to_a)
    end

    def to_a : Array(T)
      [@first] + @rest
    end

    # Transforms each item to a new type, returning a new OneOrMany.
    # Unlike Enumerable#map (which returns an Array), this preserves
    # the OneOrMany guarantee.
    def map_one_or_many(& : T -> U) : OneOrMany(U) forall U
      mapped_first = yield @first
      mapped_rest = @rest.map { |item| yield item }
      OneOrMany(U).new(mapped_first, mapped_rest)
    end

    def to_json(json : JSON::Builder) : Nil
      json.array do
        each(&.to_json(json))
      end
    end

    def self.from_json(input : String) : self
      parser = JSON::PullParser.new(input)
      new(parser)
    end

    def self.new(pull : JSON::PullParser) : self
      from_json_any(JSON::Any.new(pull))
    end

    def self.from_json_any(value : JSON::Any) : self
      if items = value.as_a?
        many(items.map { |entry| T.from_json(entry.to_json) })
      else
        one(T.from_json(value.to_json))
      end
    end
  end
end
