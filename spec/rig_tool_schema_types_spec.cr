require "./spec_helper"

module Crig
  enum Color
    Red
    Green
    Blue
  end

  struct Config
    include JSON::Serializable

    getter host : String
    getter port : Int32
    getter ssl : Bool?

    def initialize(@host : String, @port : Int32, @ssl : Bool? = nil)
    end
  end

  Crig.rig_tool description: "Process an order" do
    def process_order(
      item : String,
      quantity : Int32,
      price : Float64,
      express : Bool,
      tags : Array(String),
    ) : String
      "ok"
    end
  end

  Crig.rig_tool description: "Pick a color" do
    def pick_color(color : Color) : String
      color.to_s
    end
  end

  Crig.rig_tool description: "Nested config" do
    def set_config(config : Config) : String
      "ok"
    end
  end

  Crig.rig_tool description: "Described params" do
    def search(query : String, limit : Int32, fuzzy : Bool?) : String
      "ok"
    end
  end

  # rig_tool macro generates PROCESS_ORDER = ProcessOrder.new etc.

  describe "rig_tool schema types" do
    it "string parameter type" do
      props = PROCESS_ORDER.parameters["properties"].as_h
      props["item"]["type"].should eq("string")
    end

    it "integer parameter type" do
      props = PROCESS_ORDER.parameters["properties"].as_h
      type = props["quantity"]["type"]
      # json-schema shard emits "integer" for Int32
      (type.as_s == "integer" || type.as_s == "number").should be_true
    end

    it "float parameter type" do
      props = PROCESS_ORDER.parameters["properties"].as_h
      type = props["price"]["type"]
      # json-schema shard emits "number" for Float64
      type.as_s.should eq("number")
    end

    it "boolean parameter type" do
      props = PROCESS_ORDER.parameters["properties"].as_h
      props["express"]["type"].should eq("boolean")
    end

    it "array parameter type with items" do
      props = PROCESS_ORDER.parameters["properties"].as_h
      arr = props["tags"]
      arr["type"].should eq("array")
      arr["items"].should be_a(JSON::Any)
      arr["items"]["type"].should eq("string")
    end

    it "enum parameter type includes enum values" do
      params = PICK_COLOR.parameters
      props = params["properties"].as_h
      color = props["color"]
      color["type"].should eq("string")
      color["enum"].should be_a(JSON::Any)
      enum_vals = color["enum"].as_a.map(&.as_s).sort
      # json-schema shard lowercases enum values
      enum_vals.should eq(["blue", "green", "red"])
    end

    it "nested object parameter generates sub-schema" do
      params = SET_CONFIG.parameters
      props = params["properties"].as_h
      config = props["config"]
      config["type"].should eq("object")
      cfg_props = config["properties"].as_h
      cfg_props["host"]["type"].should eq("string")
      %w(integer number).should contain(cfg_props["port"]["type"].as_s)
      # ssl is an anyOf union containing boolean and null
      ssl = cfg_props["ssl"]
      any_of_types = ssl["anyOf"].as_a.map { |v| v["type"].as_s }
      any_of_types.should contain("boolean")
      cfg_required = config["required"].as_a.map(&.as_s)
      cfg_required.should contain("host")
      cfg_required.should contain("port")
      cfg_required.should_not contain("ssl")
    end

    it "required fields for non-nilable types" do
      required = PROCESS_ORDER.parameters["required"].as_a.map(&.as_s)
      required.should contain("item")
      required.should contain("quantity")
      required.should contain("price")
      required.should contain("express")
      required.should contain("tags")
    end

    it "optional field not in required" do
      params = SET_CONFIG.parameters
      props = params["properties"].as_h
      cfg = props["config"]
      cfg_required = cfg["required"].as_a.map(&.as_s)
      cfg_required.should_not contain("ssl")
    end

    it "memoized parameters returns same object" do
      p1 = PROCESS_ORDER.parameters
      p2 = PROCESS_ORDER.parameters
      p1.should eq(p2)
    end
  end
end
