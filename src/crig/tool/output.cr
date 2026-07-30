module Crig
  module Tool
    struct ToolOutput
      getter content : OneOrMany(Completion::ToolResultContent)

      def initialize(@content : OneOrMany(Completion::ToolResultContent))
      end

      def self.text(text : String) : self
        one(Completion::ToolResultContent.text(text))
      end

      def self.json(value : JSON::Any) : self
        one(Completion::ToolResultContent.json(value))
      end

      def self.content(content : OneOrMany(Completion::ToolResultContent)) : self
        new(content)
      end

      def self.one(content : Completion::ToolResultContent) : self
        new(OneOrMany(Completion::ToolResultContent).one(content))
      end

      def as_text : String?
        return unless @content.len == 1

        item = @content.first
        item.as_text?
      end

      def as_json : JSON::Any?
        return unless @content.len == 1

        item = @content.first
        item.as_json?
      end

      def as_content : OneOrMany(Completion::ToolResultContent)
        @content
      end

      def into_content : OneOrMany(Completion::ToolResultContent)
        @content
      end

      def render : String
        if text = as_text
          text
        elsif value = as_json
          value.to_json
        else
          "<structured tool output>"
        end
      end

      def to_s(io : IO) : Nil
        kinds = @content.to_a.map do |item|
          case item.kind
          in Completion::ToolResultContent::Kind::Text  then "text"
          in Completion::ToolResultContent::Kind::Image then "image"
          in Completion::ToolResultContent::Kind::Json  then "json"
          end
        end
        io << "ToolOutput(content_count: #{@content.len}, content_kinds: #{kinds})"
      end

      def ==(other : self) : Bool
        @content.to_a == other.content.to_a
      end
    end

    module IntoToolOutput(T)
      abstract def into_tool_output : ToolOutput
    end
  end
end
