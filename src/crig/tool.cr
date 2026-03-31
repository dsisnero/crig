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
      {% type_name = type.stringify %}
      {% if type_name.includes?("String") && !type_name.starts_with?("Array(") %}
        json.field "type", "string"
      {% elsif type_name.includes?("Bool") %}
        json.field "type", "boolean"
      {% elsif type_name.starts_with?("Int") || type_name.starts_with?("UInt") || type_name.starts_with?("Float") || type_name.includes?("Int") || type_name.includes?("UInt") || type_name.includes?("Float") %}
        json.field "type", "number"
      {% elsif type.is_a?(Generic) && type.name.resolve == Array %}
        json.field "type", "array"
        json.field "items" do
          json.object do
            Crig::ToolMacro.json_schema_for({{ type.type_vars.first }})
          end
        end
      {% else %}
        json.field "type", "object"
        {% if type.resolve.instance_vars.size > 0 %}
          json.field "title", {{ type.resolve.stringify }}
          json.field "properties" do
            json.object do
              {% for ivar in type.resolve.instance_vars %}
                json.field {{ ivar.name.stringify }} do
                  json.object do
                    Crig::ToolMacro.json_schema_for({{ ivar.type }})
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
    end
  end

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

      def definition(prompt : String) : Crig::Completion::ToolDefinition
        _ = prompt
        parameters = JSON.build do |json|
          json.object do
            json.field "type", "object"
            json.field "properties" do
              json.object do
                {% for arg in function.args %}
                  json.field {{ arg.name.stringify }} do
                    json.object do
                      Crig::ToolMacro.json_schema_for({{ arg.restriction }})
                      json.field "description", {{ params_map[arg.name.symbolize] || "Parameter #{arg.name.stringify}" }}
                    end
                  end
                {% end %}
              end
            end
            json.field "required" do
              json.array do
                {% for req in required_args %}
                  json.string {{ req.id.stringify }}
                {% end %}
              end
            end
          end
        end

        Crig::Completion::ToolDefinition.new(
          {{ fn_name }},
          {{ description_value }},
          JSON.parse(parameters)
        )
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
    abstract def definition(prompt : String) : Crig::Completion::ToolDefinition
    abstract def call(args : String) : String
  end

  struct ToolType
    enum Kind
      Simple
      Embedding
    end

    getter kind : Kind

    def initialize(
      @kind : Kind,
      @simple : Crig::ToolDyn? = nil,
      @embedding_tool : Crig::ToolDyn? = nil,
      @embedding_schema_source : Crig::ToolEmbeddingDyn? = nil,
    )
    end

    def self.simple(tool : Crig::ToolDyn) : self
      new(Kind::Simple, simple: tool)
    end

    def self.embedding(tool : T) : self forall T
      new(Kind::Embedding, embedding_tool: tool.as(Crig::ToolDyn), embedding_schema_source: tool.as(Crig::ToolEmbeddingDyn))
    end

    def name : String
      case @kind
      in .simple?
        if tool = @simple
          tool.name
        else
          raise "missing simple tool"
        end
      in .embedding?
        if tool = @embedding_tool
          tool.name
        else
          raise "missing embedding tool"
        end
      end
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      case @kind
      in .simple?
        if tool = @simple
          tool.definition(prompt)
        else
          raise "missing simple tool"
        end
      in .embedding?
        if tool = @embedding_tool
          tool.definition(prompt)
        else
          raise "missing embedding tool"
        end
      end
    end

    def call(args : String) : String
      case @kind
      in .simple?
        if tool = @simple
          tool.call(args)
        else
          raise "missing simple tool"
        end
      in .embedding?
        if tool = @embedding_tool
          tool.call(args)
        else
          raise "missing embedding tool"
        end
      end
    end

    def embedding_schema? : Crig::Embeddings::ToolSchema?
      return unless @kind.embedding?

      source = @embedding_schema_source || @embedding_tool.try(&.as?(Crig::ToolEmbeddingDyn))
      return unless source

      Crig::Embeddings::ToolSchema.try_from(source)
    end
  end

  struct ToolSet
    getter tools : Hash(String, Crig::ToolType)

    def initialize(@tools : Hash(String, Crig::ToolType) = {} of String => Crig::ToolType)
    end

    def self.from_tools(tools : Enumerable(Crig::ToolDyn)) : self
      toolset = new
      tools.each { |tool| toolset.add_tool(tool) }
      toolset
    end

    def self.from_tools_boxed(tools : Enumerable(Crig::ToolDyn)) : self
      from_tools(tools)
    end

    def self.builder : Crig::ToolSetBuilder
      Crig::ToolSetBuilder.new
    end

    def contains(toolname : String) : Bool
      @tools.has_key?(toolname)
    end

    def add_tool(tool : Crig::ToolDyn) : Nil
      @tools[tool.name] = Crig::ToolType.simple(tool)
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

    def get(toolname : String) : Crig::ToolType?
      @tools[toolname]?
    end

    # ameba:disable Naming/AccessorMethodName
    def get_tool_definitions : Array(Crig::Completion::ToolDefinition)
      @tools.values.map(&.definition(""))
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
      @tools.values.compact_map(&.embedding_schema?)
    end

    def documents : Array(Crig::Completion::Request::Document)
      @tools.values.map do |tool|
        Crig::Completion::Request::Document.new(
          tool.name,
          "Tool: #{tool.name}\nDefinition:\n#{tool.definition("").to_json}",
          {} of String => String
        )
      end
    end
  end

  struct ToolSetBuilder
    def initialize(@tools : Array(Crig::ToolType) = [] of Crig::ToolType)
    end

    def static_tool(tool : Crig::ToolDyn) : self
      self.class.new(@tools + [Crig::ToolType.simple(tool)])
    end

    def dynamic_tool(tool : T) : self forall T
      self.class.new(@tools + [Crig::ToolType.embedding(tool)])
    end

    def build : Crig::ToolSet
      Crig::ToolSet.new(
        @tools.to_h do |tool|
          {tool.name, tool}
        end
      )
    end
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

    abstract def definition(prompt : String) : Crig::Completion::ToolDefinition
    abstract def call_typed(args : Args) : Output

    def call(args : String) : String
      parsed_args = begin
        Args.from_json(args)
      rescue ex
        raise Crig::ToolError.json_error(ex)
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
