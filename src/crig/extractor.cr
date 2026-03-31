module Crig
  EXTRACTOR_PREAMBLE = "You are an AI assistant whose purpose is to extract structured data from the provided text.\nYou will have access to a `submit` function that defines the structure of the data to extract from the provided text.\nUse the `submit` function to submit the structured data.\nBe sure to fill out every field and ALWAYS CALL THE `submit` function, even with default values!!!."

  struct ExtractionResponse(T)
    getter data : T
    getter usage : Completion::Usage

    def initialize(@data : T, @usage : Completion::Usage)
    end
  end

  class ExtractionError < Exception
    def self.no_data : self
      new("No data extracted")
    end

    def self.deserialization_error(error : Exception) : self
      new("Failed to deserialize the extracted data: #{error.message || error.class.name}")
    end

    def self.completion_error(error : Exception) : self
      new("CompletionError: #{error.message || error.class.name}")
    end
  end

  struct ExtractorSubmitTool(T)
    include Crig::Tool(T, T)

    def name : String
      "submit"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      parameters = JSON.parse(
        JSON.build do |json|
          json.object do
            {% begin %}
              Crig::ToolMacro.json_schema_for({{ @type.type_vars[0] }})
            {% end %}
          end
        end
      )

      Crig::Completion::ToolDefinition.new(
        name,
        "Submit the structured data you extracted from the provided text.",
        parameters,
      )
    end

    def call_typed(args : T) : T
      args
    end
  end

  struct Extractor(M, T)
    getter agent : Agent(M)
    getter retries : Int32

    def initialize(@agent : Agent(M), @retries : Int32 = 0)
    end

    def model : M
      @agent.model
    end

    def extract(text : Crig::Completion::Message | String) : T
      extract_with_chat_history(text, [] of Crig::Completion::Message)
    end

    def extract_with_chat_history(
      text : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : T
      extract_with_chat_history_with_usage(text, chat_history).data
    end

    def extract_with_usage(text : Crig::Completion::Message | String) : ExtractionResponse(T)
      extract_with_chat_history_with_usage(text, [] of Crig::Completion::Message)
    end

    def extract_with_chat_history_with_usage(
      text : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : ExtractionResponse(T)
      usage = Crig::Completion::Usage.new
      last_error = nil.as(Exception?)

      (0..@retries).each do
        begin
          data, response_usage = extract_json_with_usage(text, chat_history)
          usage.add!(response_usage)
          return ExtractionResponse(T).new(data, usage)
        rescue ex
          last_error = ex
        end
      end

      raise last_error || ExtractionError.no_data
    end

    private def extract_json_with_usage(
      text : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : {T, Crig::Completion::Usage}
      response = begin
        @agent.completion(text, chat_history).send(@agent.model)
      rescue ex : Crig::Completion::CompletionError
        raise ExtractionError.completion_error(ex)
      end

      arguments = response.choice.to_a.compact_map do |content|
        next unless content.kind.tool_call?
        tool_call = content.tool_call
        next unless tool_call
        next unless tool_call.function.name == "submit"
        tool_call.function.arguments
      end

      raw_data = arguments.last? || raise ExtractionError.no_data

      begin
        {T.from_json(raw_data.to_json), response.usage}
      rescue ex
        raise ExtractionError.deserialization_error(ex)
      end
    end
  end

  struct ExtractorBuilder(M, T)
    getter agent_builder : AgentBuilder(M)
    getter retries_value : Int32

    def initialize(
      model : M,
      @agent_builder : AgentBuilder(M) = AgentBuilder(M).new(model)
        .preamble(EXTRACTOR_PREAMBLE)
        .tool(ExtractorSubmitTool(T).new)
        .tool_choice(Crig::Completion::ToolChoice.required),
      @retries_value : Int32 = 0,
    )
    end

    def retries(retries : Int32) : self
      self.class.new(@agent_builder.model, @agent_builder, retries)
    end

    def preamble(preamble : String) : self
      extra = "\n=============== ADDITIONAL INSTRUCTIONS ===============\n#{preamble}"
      self.class.new(@agent_builder.model, @agent_builder.append_preamble(extra), @retries_value)
    end

    def context(doc : String) : self
      self.class.new(@agent_builder.model, @agent_builder.context(doc), @retries_value)
    end

    def additional_params(params : JSON::Any) : self
      self.class.new(@agent_builder.model, @agent_builder.additional_params(params), @retries_value)
    end

    def max_tokens(max_tokens : Int64) : self
      self.class.new(@agent_builder.model, @agent_builder.max_tokens(max_tokens), @retries_value)
    end

    def tool_choice(choice : Crig::Completion::ToolChoice) : self
      self.class.new(@agent_builder.model, @agent_builder.tool_choice(choice), @retries_value)
    end

    def dynamic_context(sample : Int32, dynamic_context) : self
      self.class.new(@agent_builder.model, @agent_builder.dynamic_context(sample, dynamic_context), @retries_value)
    end

    def build : Extractor(M, T)
      Extractor(M, T).new(@agent_builder.build, @retries_value)
    end
  end
end
