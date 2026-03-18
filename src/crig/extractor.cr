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
  end

  struct Extractor(M, T)
    getter agent : Agent(M)
    getter retries : Int32

    def initialize(@agent : Agent(M), @retries : Int32 = 0)
    end

    def model : M
      @agent.model
    end
  end

  struct ExtractorBuilder(M, T)
    getter agent_builder : AgentBuilder(M)
    getter retries_value : Int32

    def initialize(
      model : M,
      @agent_builder : AgentBuilder(M) = AgentBuilder(M).new(model)
        .preamble(EXTRACTOR_PREAMBLE)
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
