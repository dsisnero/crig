module Crig
  # Trait for high-level streaming prompt interface.
  #
  # This trait provides a simple interface for streaming prompts to a completion model.
  # Implementations can optionally support prompt hooks for observing and controlling
  # the agent's execution lifecycle.
  module StreamingPrompt(M)
    # Stream a simple prompt to the model
    abstract def stream_prompt(prompt : Crig::Completion::Message | String) : Crig::StreamingPromptRequest(M)
  end

  # Trait for high-level streaming chat interface with conversation history.
  #
  # This trait provides an interface for streaming chat completions with support
  # for maintaining conversation history. Implementations can optionally support
  # prompt hooks for observing and controlling the agent's execution lifecycle.
  module StreamingChat(M)
    include StreamingPrompt(M)

    # Stream a chat with history to the model
    #
    # The updated history (including the new prompt and response) is returned
    # in `FinalResponse#history`.
    abstract def stream_chat(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : Crig::StreamingPromptRequest(M)
  end

  # Trait for low-level streaming completion interface
  module StreamingCompletion(M)
    # Generate a streaming completion from a request
    abstract def stream_completion(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : Crig::Completion::Request::CompletionRequestBuilder
  end
end
