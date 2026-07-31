require "../spec_helper"

struct DummyOneOrManyString
  getter string : String

  def initialize(@string : String)
  end

  def ==(other : self) : Bool
    @string == other.string
  end

  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .string?
      new(pull.read_string)
    when .begin_object?
      string = nil
      pull.read_begin_object
      until pull.kind.end_object?
        key = pull.read_object_key
        if key == "string"
          string = pull.read_string
        else
          pull.skip
        end
      end
      pull.read_end_object
      new(string || "")
    else
      raise "unexpected DummyOneOrManyString payload"
    end
  end

  def to_json(json : JSON::Builder) : Nil
    json.object do
      json.field "string", @string
    end
  end
end

struct DummyOneOrManyStruct
  include JSON::Serializable

  @[JSON::Field(converter: Crig::StringOrOneOrManyConverter(DummyOneOrManyString))]
  getter field : Crig::OneOrMany(DummyOneOrManyString)

  def initialize(@field : Crig::OneOrMany(DummyOneOrManyString))
  end
end

struct DummyOneOrManyStructOption
  include JSON::Serializable

  @[JSON::Field(converter: Crig::StringOrOptionOneOrManyConverter(DummyOneOrManyString))]
  getter field : Crig::OneOrMany(DummyOneOrManyString)?

  def initialize(@field : Crig::OneOrMany(DummyOneOrManyString)?)
  end
end

struct DummyOneOrManyMessage
  include JSON::Serializable

  getter role : String
  @[JSON::Field(converter: Crig::StringOrOptionOneOrManyConverter(DummyOneOrManyString))]
  getter content : Crig::OneOrMany(DummyOneOrManyString)?

  def initialize(@role : String, @content : Crig::OneOrMany(DummyOneOrManyString)?)
  end
end

class MutableOneOrManyValue
  property value : String

  def initialize(@value : String)
  end
end

module Crig
  describe OneOrMany do
    it "builds a single item" do
      one_or_many = OneOrMany(String).one("hello")

      one_or_many.to_a.should eq(["hello"])
      one_or_many.len.should eq(1)
      one_or_many.empty?.should be_false
      one_or_many.is_empty.should be_false
      one_or_many.first.should eq("hello")
    end

    it "builds many items and preserves order" do
      one_or_many = OneOrMany(String).many(["hello", "world"])

      one_or_many.to_a.should eq(["hello", "world"])
      one_or_many.rest.should eq(["world"])
      one_or_many.last.should eq("world")
    end

    it "exposes rust-named first and last accessors" do
      one_or_many = OneOrMany(String).many(["hello", "world"])

      one_or_many.first_ref.should eq("hello")
      one_or_many.first_mut.should eq("hello")
      one_or_many.last_ref.should eq("world")
      one_or_many.last_mut.should eq("world")
    end

    it "merges multiple values" do
      merged = OneOrMany(String).merge([
        OneOrMany(String).many(["hello", "world"]),
        OneOrMany(String).one("sup"),
      ])

      merged.to_a.should eq(["hello", "world", "sup"])
    end

    it "builds from an optional iterator when non-empty" do
      one_or_many = OneOrMany(String).from_iter_optional(["hello", "world"])

      one_or_many.should_not be_nil
      one_or_many.not_nil!.to_a.should eq(["hello", "world"])
    end

    it "builds a single item from an optional iterator" do
      one_or_many = OneOrMany(String).from_iter_optional(["hello"])

      one_or_many.should_not be_nil
      one_or_many.not_nil!.len.should eq(1)
      one_or_many.not_nil!.first.should eq("hello")
    end

    it "returns nil for an empty optional iterator" do
      OneOrMany(String).from_iter_optional([] of String).should be_nil
    end

    it "supports push and insert" do
      one_or_many = OneOrMany(String).one("world")
      one_or_many.insert(0, "hello")
      one_or_many.push("sup")

      one_or_many.to_a.should eq(["hello", "world", "sup"])
    end

    it "supports owned iteration for a single item" do
      one_or_many = OneOrMany(String).one("hello")

      one_or_many.into_iter.to_a.should eq(["hello"])
    end

    it "supports owned iteration for multiple items" do
      one_or_many = OneOrMany(String).many(["hello", "world"])

      one_or_many.into_iter.to_a.should eq(["hello", "world"])
    end

    it "supports mutable-style iteration for a single item" do
      one_or_many = OneOrMany(MutableOneOrManyValue).one(MutableOneOrManyValue.new("hello"))

      one_or_many.iter_mut.each do |item|
        item.value = "#{item.value} world"
      end

      one_or_many.first.value.should eq("hello world")
    end

    it "supports mutable-style iteration for multiple reference items" do
      one_or_many = OneOrMany(MutableOneOrManyValue).many([
        MutableOneOrManyValue.new("hello"),
        MutableOneOrManyValue.new("world"),
      ])

      one_or_many.iter_mut.each_with_index do |item, index|
        item.value = "#{item.value} world" if index == 0
      end

      one_or_many.to_a.map(&.value).should eq(["hello world", "world"])
    end

    it "reports iterator size hints" do
      one = OneOrMany(String).one("bar")
      many = OneOrMany(String).many(["foo", "bar", "baz"])

      one.iter.size_hint.should eq({1, 1})
      many.iter.size_hint.should eq({1, 3})
      many.into_iter.size_hint.should eq({1, 3})
      many.iter_mut.size_hint.should eq({1, 3})
    end

    it "deserializes arrays into one-or-many values" do
      one_or_many = OneOrMany(Int32).from_json("[1,2,3]")

      one_or_many.len.should eq(3)
      one_or_many.first.should eq(1)
      one_or_many.rest.should eq([2, 3])
    end

    it "deserializes arrays of maps into one-or-many values" do
      one_or_many = OneOrMany(JSON::Any).from_json(%([{"key":"value1"},{"key":"value2"}]))

      one_or_many.len.should eq(2)
      one_or_many.first.should eq(JSON.parse(%({"key":"value1"})))
      one_or_many.rest.should eq([JSON.parse(%({"key":"value2"}))])
    end

    it "deserializes string-or-many fields from a string" do
      dummy = DummyOneOrManyStruct.from_json(%({"field":"hello"}))

      dummy.field.len.should eq(1)
      dummy.field.first.should eq(DummyOneOrManyString.new("hello"))
    end

    it "deserializes optional string-or-many fields from a string" do
      dummy = DummyOneOrManyStructOption.from_json(%({"field":"hello"}))

      dummy.field.should_not be_nil
      field = dummy.field.not_nil!
      field.len.should eq(1)
      field.first.should eq(DummyOneOrManyString.new("hello"))
    end

    it "deserializes optional string-or-many fields from a list" do
      dummy = DummyOneOrManyStructOption.from_json(%({"field":[{"string":"hello"},{"string":"world"}]}))

      dummy.field.should_not be_nil
      field = dummy.field.not_nil!
      field.len.should eq(2)
      field.first.should eq(DummyOneOrManyString.new("hello"))
      field.rest.should eq([DummyOneOrManyString.new("world")])
    end

    it "deserializes optional string-or-many fields from null" do
      dummy = DummyOneOrManyStructOption.from_json(%({"field":null}))

      dummy.field.should be_nil
    end

    it "deserializes null content through the optional converter" do
      dummy = DummyOneOrManyMessage.from_json(%({"role":"assistant","content":null}))

      dummy.role.should eq("assistant")
      dummy.content.should be_nil
    end

    it "rejects empty collections" do
      expect_raises(Crig::EmptyListError, "Cannot create OneOrMany with an empty vector.") do
        OneOrMany(String).many([] of String)
      end
    end
  end
end
