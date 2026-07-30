module Crig
  module Tool
    struct PortableDynamicTool
      getter name : String
      getter description : String
      getter parameters : JSON::Any

      def initialize(@name : String, @description : String, @parameters : JSON::Any, &@callback : JSON::Any -> ToolOutput)
      end

      def definition : Completion::ToolDefinition
        Completion::ToolDefinition.new(
          name: @name,
          description: @description,
          parameters: @parameters,
        )
      end

      def execute(arguments : JSON::Any) : ToolOutput
        @callback.call(arguments)
      end
    end
  end
end
