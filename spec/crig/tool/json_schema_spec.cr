require "../../spec_helper"

enum TestEnum
  A; B; C
end

struct NilableFields
  include JSON::Serializable
  getter name : String?
  getter count : Int32?
  getter active : Bool?
  getter status : TestEnum?
  getter required_name : String
end

private def build_nilable_schema
  JSON.parse(JSON.build { |json| json.object { Crig::ToolMacro.json_schema_for(NilableFields) } })
end

describe Crig::ToolMacro, "json_schema_for" do
  it "generates string type for String? field" do
    schema = build_nilable_schema
    props = schema["properties"].as_h
    props["name"]["type"].as_s.should eq("string")
  end

  it "generates number type for Int32? field" do
    schema = build_nilable_schema
    props = schema["properties"].as_h
    props["count"]["type"].as_s.should eq("number")
  end

  it "generates boolean type for Bool? field" do
    schema = build_nilable_schema
    props = schema["properties"].as_h
    props["active"]["type"].as_s.should eq("boolean")
  end

  it "generates string+enum for Enum? field" do
    schema = build_nilable_schema
    props = schema["properties"].as_h
    props["status"]["type"].as_s.should eq("string")
    props["status"]["enum"].as_a.map(&.as_s).sort.should eq(["A", "B", "C"])
  end

  it "excludes nilable fields from required array" do
    schema = build_nilable_schema
    required = schema["required"].as_a.map(&.as_s)
    required.should contain("required_name")
    required.should_not contain("name")
    required.should_not contain("count")
    required.should_not contain("active")
    required.should_not contain("status")
  end

  it "includes non-nilable fields in required array" do
    schema = build_nilable_schema
    required = schema["required"].as_a.map(&.as_s)
    required.size.should eq(1)
    required[0].should eq("required_name")
  end
end
