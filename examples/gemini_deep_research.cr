require "../src/crig"

module Crig::Examples::GeminiDeepResearch
  DEEP_RESEARCH_AGENT     = "deep-research-pro-preview-12-2025"
  STREAM_RETRY_DELAY_SECS = 2_u64
  MODEL                   = "gemini-3-pro-preview"
  PROMPT                  = "Research the history of Google TPUs."

  struct StreamState
    property interaction_id : String?
    property last_event_id : String?
    property is_complete : Bool
    property saw_text : Bool

    def initialize(
      @interaction_id : String? = nil,
      @last_event_id : String? = nil,
      @is_complete : Bool = false,
      @saw_text : Bool = false,
    )
    end
  end

  def self.deep_research_params : Crig::Providers::Gemini::Interactions::AdditionalParameters
    Crig::Providers::Gemini::Interactions::AdditionalParameters.new(
      agent: DEEP_RESEARCH_AGENT,
      background: true,
      store: true,
      agent_config: Crig::Providers::Gemini::Interactions::AgentConfig.deep_research(
        thinking_summaries: Crig::Providers::Gemini::Interactions::ThinkingSummaries::Auto
      )
    )
  end

  def self.extract_text(outputs : Array(Crig::Providers::Gemini::Interactions::Content)) : String
    outputs.compact_map do |content|
      content.text.try(&.text) if content.kind.text?
    end.join("\n")
  end

  def self.track_event_id(state : StreamState, event_id : String?) : StreamState
    return state unless event_id
    StreamState.new(state.interaction_id, event_id, state.is_complete, state.saw_text)
  end

  def self.handle_stream_event(
    state : StreamState,
    event : Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent,
  ) : StreamState
    case event.kind
    when .interaction_start?
      interaction = event.interaction.not_nil!
      StreamState.new(interaction.id, event.event_id || state.last_event_id, state.is_complete, state.saw_text)
    when .content_start?
      if content = event.content
        if content.kind.text?
          return StreamState.new(state.interaction_id, event.event_id || state.last_event_id, state.is_complete, true)
        end
      end
      track_event_id(state, event.event_id)
    when .content_delta?
      if delta = event.delta
        if delta.kind.text?
          return StreamState.new(state.interaction_id, event.event_id || state.last_event_id, state.is_complete, true)
        end
      end
      track_event_id(state, event.event_id)
    when .interaction_complete?
      interaction = event.interaction
      StreamState.new(
        interaction.try(&.id) || state.interaction_id,
        event.event_id || state.last_event_id,
        true,
        state.saw_text || !extract_text(interaction.try(&.outputs) || [] of Crig::Providers::Gemini::Interactions::Content).empty?
      )
    when .error?
      StreamState.new(state.interaction_id, event.event_id || state.last_event_id, true, state.saw_text)
    else
      track_event_id(state, event.event_id)
    end
  end

  def self.build_client(api_key : String, base_url : String = Crig::Providers::Gemini::GEMINI_API_BASE_URL) : Crig::Providers::Gemini::InteractionsClient
    Crig::Providers::Gemini::InteractionsClient.new(api_key, base_url)
  end

  def self.build_model(
    client : Crig::Providers::Gemini::InteractionsClient,
    model : String = MODEL,
  ) : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel
    client.completion_model(model)
  end

  def self.build_request(
    model : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel,
    prompt : String = PROMPT,
  ) : Crig::Completion::Request::CompletionRequest
    model.completion_request(prompt)
      .additional_params(JSON.parse(deep_research_params.to_json))
      .build
  end
end
