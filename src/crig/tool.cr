require "json"
require "json-schema"

module Crig
  module ToolMacro
    struct Result(T, E)
      getter value : T?
      getter error : E?

      def initialize(@value : T? = nil, @error : E? = nil)
      end

      def self.ok(value : T) : self
        new(value: value)
      end

      def self.err(error : E) : self
        new(error: error)
      end
    end

    def self.unwrap(value)
      value
    end

    def self.unwrap(value : Result(T, E)) : T forall T, E
      if error = value.error
        case error
        when Exception
          raise error
        else
          raise error.to_s
        end
      end

      value.value || raise "tool macro result missing value"
    end

    macro json_schema_for(type)
      {% if type.resolve < Enum %}
        json.field "type", "string"
        json.field "enum" do
          json.array do
            {% for const in type.resolve.constants %}
              json.string {{ const.stringify }}
            {% end %}
          end
        end
      {% elsif type.stringify.includes?("String") && !type.stringify.starts_with?("Array(") %}
        json.field "type", "string"
      {% elsif type.stringify.includes?("Bool") %}
        json.field "type", "boolean"
      {% elsif type.stringify.starts_with?("Int") || type.stringify.starts_with?("UInt") || type.stringify.starts_with?("Float") || type.stringify.includes?("Int") || type.stringify.includes?("UInt") || type.stringify.includes?("Float") %}
        json.field "type", "number"
      {% elsif type.is_a?(Generic) && type.name.resolve == Array %}
        json.field "type", "array"
        json.field "items" do
          json.object do
            Crig::ToolMacro.json_schema_for({{ type.type_vars.first }})
          end
        end
      {% else %}
        {% if type.resolve %}
          json.field "type", "object"
          {% if type.resolve.instance_vars.size > 0 %}
            json.field "title", {{ type.resolve.stringify }}
            json.field "properties" do
              json.object do
                {% for ivar in type.resolve.instance_vars %}
                  json.field {{ ivar.name.stringify }} do
                    json.object do
                      {% if ivar.type.resolve && ivar.type.resolve.union_types.size > 0 %}
                        {% non_nil_type = ivar.type.resolve.union_types.reject(&.==(Nil)).first %}
                        {% if non_nil_type %}
                          Crig::ToolMacro.json_schema_for({{ non_nil_type }})
                        {% end %}
                      {% else %}
                        Crig::ToolMacro.json_schema_for({{ ivar.type }})
                      {% end %}
                    end
                  end
                {% end %}
              end
            end
            json.field "required" do
              json.array do
                {% for ivar in type.resolve.instance_vars %}
                  {% unless ivar.type.stringify.includes?("Nil") %}
                    json.string {{ ivar.name.stringify }}
                  {% end %}
                {% end %}
              end
            end
          {% end %}
        {% end %}
      {% end %}
    end
  end

  # Define a tool from a Crystal function. The function's parameter types
  # are used to auto-generate a JSON Schema via `json-schema`. Non-nilable
  # fields are automatically marked required; nilable fields become optional.
  #
  # ## Minimal usage
  # ```
  # Crig.rig_tool do
  #   def echo(text : String) : String
  #     text
  #   end
  # end
  # ```
  #
  # ## With description
  # ```
  # Crig.rig_tool description: "Echo back the input" do
  #   def echo(text : String) : String
  #     text
  #   end
  # end
  # ```
  #
  # ## With error handling
  # ```
  # Crig.rig_tool description: "Divide two numbers" do
  #   def divide(x : Int32, y : Int32) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
  #     if y == 0
  #       Crig::ToolMacro::Result(Int32, Crig::ToolError).err(
  #         Crig::ToolError.new("Division by zero")
  #       )
  #     else
  #       Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x // y)
  #     end
  #   end
  # end
  # ```
  #
  # ## With optional parameters
  # nilable fields are automatically excluded from the required list:
  # ```
  # Crig.rig_tool do
  #   def greet(name : String, greeting : String?) : String
  #     "#{greeting || "Hello"}, #{name}"
  #   end
  # end
  # ```
  macro rig_tool(description = nil, params = nil, required = nil, &block)
    {% function = block.body %}
    {% unless function.is_a?(Def) %}
      {% raise "Crig.rig_tool must wrap a def" %}
    {% end %}

    {% fn_name = function.name.stringify %}
    {% struct_name = fn_name.camelcase.id %}
    {% params_struct_name = (fn_name.camelcase + "Parameters").id %}
    {% static_name = fn_name.upcase.id %}
    {% output_type = function.return_type %}
    {% if output_type.is_a?(Generic) && output_type.name.stringify.ends_with?("::Result") %}
      {% call_output_type = output_type.type_vars[0] %}
    {% else %}
      {% call_output_type = output_type %}
    {% end %}
    {% description_value = description || ("Function to " + function.name.id.stringify) %}
    {% params_map = params || {} of Symbol => StringLiteral %}
    {% required_args = required || [] of Symbol %}

    struct {{ params_struct_name }}
      include JSON::Serializable

      {% for arg in function.args %}
        @[JSON::Field(description: {{ params_map[arg.name.symbolize] || "Parameter #{arg.name.stringify}" }})]
        getter {{ arg.name }} : {{ arg.restriction }}
      {% end %}

      def initialize(
        {% for arg, index in function.args %}
          @{{ arg.name }} : {{ arg.restriction }}{% unless index == function.args.size - 1 %}, {% end %}
        {% end %}
      )
      end
    end

    {{ function }}

    struct {{ struct_name }}
      include Crig::Tool({{ params_struct_name }}, {{ call_output_type }})

      NAME = {{ fn_name }}

      private def invoke(
        {% for arg, index in function.args %}
          {{ arg.name }} : {{ arg.restriction }}{% unless index == function.args.size - 1 %}, {% end %}
        {% end %}
      ) : {{ output_type }}
        {{ function.body }}
      end

      def description : String
        {{ description_value }}
      end

      def parameters : JSON::Any
        schema = {{ params_struct_name }}.json_schema
        JSON.parse(schema.to_json)
      end

      def call_typed(args : {{ params_struct_name }}) : {{ call_output_type }}
        Crig::ToolMacro.unwrap(
          invoke(
            {% for arg, index in function.args %}
              args.{{ arg.name }}{% unless index == function.args.size - 1 %}, {% end %}
            {% end %}
          )
        )
      end
    end

    {{ static_name }} = {{ struct_name }}.new
  end

  class ToolError < Exception
    enum Kind
      ToolCallError
      JsonError
      Other
    end

    getter kind : Kind
    getter source_error : Exception?

    def initialize(message : String, @kind : Kind = Kind::Other, @source_error : Exception? = nil)
      super(message)
    end

    def self.tool_call_error(error : Exception) : self
      message = error.message || error.class.name
      if message.starts_with?("ToolCallError: ")
        new(message, Kind::ToolCallError, error)
      else
        new("ToolCallError: #{message}", Kind::ToolCallError, error)
      end
    end

    def self.json_error(error : Exception) : self
      new("JsonError: #{error.message || error.class.name}", Kind::JsonError, error)
    end
  end

  class ToolSetError < Exception
    enum Kind
      ToolCallError
      ToolNotFoundError
      JsonError
      Interrupted
      Other
    end

    getter kind : Kind
    getter source_error : Exception?

    def initialize(message : String, @kind : Kind = Kind::Other, @source_error : Exception? = nil)
      super(message)
    end

    def self.tool_call_error(error : Exception) : self
      message = error.message || error.class.name
      if message.starts_with?("ToolCallError: ")
        new(message, Kind::ToolCallError, error)
      else
        new("ToolCallError: #{message}", Kind::ToolCallError, error)
      end
    end

    def self.tool_not_found(name : String) : self
      new("ToolNotFoundError: #{name}", Kind::ToolNotFoundError)
    end

    def self.json_error(error : Exception) : self
      new("JsonError: #{error.message || error.class.name}", Kind::JsonError, error)
    end

    def self.interrupted : self
      new("Tool call interrupted", Kind::Interrupted)
    end
  end

  module ToolDyn
    abstract def name : String
    abstract def description : String
    abstract def parameters : JSON::Any
    abstract def call(args : String) : String
  end

  struct EmbeddedToolBox(T)
    include Crig::ToolDyn
    include Crig::ToolEmbeddingDyn

    getter tool : T

    def initialize(@tool : T)
    end

    def name : String
      @tool.name
    end

    def description : String
      @tool.description
    end

    def parameters : JSON::Any
      @tool.parameters
    end

    def call(args : String) : String
      @tool.call(args)
    end

    def context : JSON::Any
      @tool.context
    end

    def embedding_docs : Array(String)
      @tool.embedding_docs
    end
  end

  # ToolSet is the runtime collection used by agents and tool servers.
  # It mirrors Rig's builder-first toolset API and keeps both static and
  # embedding-backed tools under one interface.
  struct ToolSet
    getter tools : Hash(String, Crig::ToolDyn)

    def initialize(@tools : Hash(String, Crig::ToolDyn) = {} of String => Crig::ToolDyn)
    end

    def self.from_tools(tools : Enumerable(Crig::ToolDyn)) : self
      toolset = new
      tools.each { |tool| toolset.add_tool(tool) }
      toolset
    end

    def self.from_tools_boxed(tools : Enumerable(Crig::ToolDyn)) : self
      from_tools(tools)
    end

    # Create a fluent ToolSetBuilder, matching Rig's `ToolSet::builder()`.
    def self.builder : Crig::ToolSetBuilder
      Crig::ToolSetBuilder.new
    end

    def contains(toolname : String) : Bool
      @tools.has_key?(toolname)
    end

    def add_tool(tool : Crig::ToolDyn) : Nil
      @tools[tool.name] = tool
    end

    def add_tool_boxed(tool : Crig::ToolDyn) : Nil
      add_tool(tool)
    end

    def delete_tool(tool_name : String) : Nil
      @tools.delete(tool_name)
    end

    def add_tools(toolset : Crig::ToolSet) : Nil
      @tools.merge!(toolset.tools)
    end

    def get(toolname : String) : Crig::ToolDyn?
      @tools[toolname]?
    end

    # ameba:disable Naming/AccessorMethodName
    def get_tool_definitions : Array(Crig::Completion::ToolDefinition)
      @tools.map { |name, tool| Crig.tool_definition(tool, name) }
    end

    # ameba:enable Naming/AccessorMethodName

    def call(toolname : String, args : String) : String
      tool = @tools[toolname]?
      raise Crig::ToolSetError.tool_not_found(toolname) unless tool

      tool.call(args)
    rescue ex : Crig::ToolError
      raise Crig::ToolSetError.tool_call_error(ex)
    end

    def schemas : Array(Crig::Embeddings::ToolSchema)
      @tools.values.compact_map { |tool| tool.is_a?(Crig::ToolEmbeddingDyn) ? Crig::Embeddings::ToolSchema.try_from(tool) : nil }
    end

    def documents : Array(Crig::Completion::Request::Document)
      @tools.map do |name, tool|
        definition = Crig.tool_definition(tool, name)
        Crig::Completion::Request::Document.new(
          name,
          "Tool: #{name}\nDefinition:\n#{definition.to_json}",
          {} of String => String
        )
      end
    end
  end

  # Wrapper enum that holds either a static (Simple) or embedding-backed (Embedding) tool.
  # Mirrors `ToolType` from the upstream Rust crate.
  class ToolType
    def self.embedding(tool : Crig::ToolEmbeddingDyn) : self
      new(:embedding, tool.as(Crig::ToolDyn))
    end

    def self.simple(tool : Crig::ToolDyn) : self
      new(:simple, tool)
    end

    def initialize(@kind : Symbol, @tool : Crig::ToolDyn)
    end

    def name : String
      @tool.name
    end

    def description : String
      @tool.description
    end

    def parameters : JSON::Any
      @tool.parameters
    end

    def call(args : String) : String
      @tool.call(args)
    end
  end

  # Builder for ToolSet. This is the ergonomic path used when composing mixed
  # static and embedding-backed tools before handing them to an agent or tool server.
  struct ToolSetBuilder
    def initialize(@tools : Array(Crig::ToolDyn) = [] of Crig::ToolDyn)
    end

    # Add a standard executable tool.
    def static_tool(tool : Crig::ToolDyn) : self
      self.class.new(@tools + [tool])
    end

    # Add an embedding-backed tool.
    def dynamic_tool(tool : T) : self forall T
      boxed = Crig::EmbeddedToolBox(T).new(tool)
      self.class.new(@tools + [boxed.as(Crig::ToolDyn)])
    end

    def build : Crig::ToolSet
      Crig::ToolSet.new(
        @tools.to_h do |tool|
          {tool.name, tool}
        end
      )
    end
  end

  def self.tool_definition(tool : Crig::ToolDyn, name : String? = nil) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      name || tool.name,
      tool.description,
      tool.parameters,
    )
  end

  module Tool(Args, Output)
    include ToolDyn

    def name : String
      {% if @type.has_constant?("NAME") %}
        {{ @type.constant("NAME") }}.to_s
      {% else %}
        raise "Tool #{typeof(self)} must define NAME or override #name"
      {% end %}
    end

    abstract def description : String
    abstract def parameters : JSON::Any
    abstract def call_typed(args : Args) : Output

    def call(args : String) : String
      parsed_args = begin
        Args.from_json(args)
      rescue ex
        if args.strip == "null"
          begin
            Args.from_json("{}")
          rescue error
            raise Crig::ToolError.json_error(ex)
          end
        else
          raise Crig::ToolError.json_error(ex)
        end
      end

      output = begin
        call_typed(parsed_args)
      rescue ex
        raise Crig::ToolError.tool_call_error(ex)
      end

      begin
        output.to_json
      rescue ex
        raise Crig::ToolError.json_error(ex)
      end
    end
  end

  module ToolEmbedding(Args, Output, Context)
    include Tool(Args, Output)
    include ToolEmbeddingDyn

    macro included
      def self.init(state, context : {{ Context }}) : self
        _ = state
        _ = context
        raise NotImplementedError.new("Tool embedding {{ @type.name }} must implement .init(state, context)")
      end
    end

    abstract def embedding_docs : Array(String)
    abstract def typed_context : Context

    def context : JSON::Any
      @context_json ||= JSON.parse(typed_context.to_json)
    end
  end
end
