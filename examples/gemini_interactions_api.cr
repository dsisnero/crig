require "../src/crig"

module Crig::Examples::GeminiInteractionsAPI
  BASIC_MODEL   = "gemini-3-flash-preview"
  BASIC_PROMPT  = "Give me two fun facts about hummingbirds."
  FOLLOW_PROMPT = "Now answer with a short analogy."
  SEARCH_PROMPT = "Who won the Euro 2024 tournament?"
  URL_1         = "https://www.rust-lang.org/"
  URL_2         = "https://doc.rust-lang.org/book/"
  URL_PROMPT    = "Compare the focus of the pages at #{URL_1} and #{URL_2}. Provide a concise summary."
  CODE_PROMPT   = "What is the sum of the first 50 prime numbers? Use code execution to compute it."
  TOOL_PROMPT   = "Use the add tool to sum 7 and 11."

  def self.build_client(api_key : String, base_url : String = Crig::Providers::Gemini::GEMINI_API_BASE_URL) : Crig::Providers::Gemini::InteractionsClient
    Crig::Providers::Gemini::InteractionsClient.new(api_key, base_url)
  end

  def self.build_model(
    client : Crig::Providers::Gemini::InteractionsClient,
    model : String = BASIC_MODEL,
  ) : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel
    client.completion_model(model)
  end

  def self.extract_text(choice : Crig::OneOrMany(Crig::Completion::AssistantContent)) : String
    choice.to_a.compact_map(&.text.try(&.text)).join
  end

  def self.first_tool_call(choice : Crig::OneOrMany(Crig::Completion::AssistantContent)) : Crig::Completion::ToolCall?
    choice.to_a.find(&.kind.tool_call?).try(&.tool_call)
  end

  def self.basic_request(model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(store: true)
    model.completion_request(BASIC_PROMPT)
      .preamble("Be concise.")
      .additional_params(JSON.parse(params.to_json))
      .build
  end

  def self.follow_request(
    model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel,
    interaction_id : String,
  ) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(
      previous_interaction_id: interaction_id
    )
    model.completion_request(FOLLOW_PROMPT)
      .additional_params(JSON.parse(params.to_json))
      .build
  end

  def self.search_request(model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(
      tools: [Crig::Providers::Gemini::Interactions::Tool.google_search]
    )
    model.completion_request(SEARCH_PROMPT)
      .additional_params(JSON.parse(params.to_json))
      .build
  end

  def self.url_request(model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(
      tools: [Crig::Providers::Gemini::Interactions::Tool.url_context]
    )
    model.completion_request(URL_PROMPT)
      .additional_params(JSON.parse(params.to_json))
      .build
  end

  def self.code_request(model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(
      tools: [Crig::Providers::Gemini::Interactions::Tool.code_execution]
    )
    model.completion_request(CODE_PROMPT)
      .additional_params(JSON.parse(params.to_json))
      .build
  end

  def self.add_tool : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "add",
      "Add two numbers together",
      JSON.parse(%({
        "type":"object",
        "properties":{"x":{"type":"number"},"y":{"type":"number"}},
        "required":["x","y"]
      }))
    )
  end

  def self.tool_request(model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel) : Crig::Completion::Request::CompletionRequest
    params = Crig::Providers::Gemini::Interactions::AdditionalParameters.new(store: true)
    model.completion_request(TOOL_PROMPT)
      .tool(add_tool)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .additional_params(JSON.parse(params.to_json))
      .build
  end
end
