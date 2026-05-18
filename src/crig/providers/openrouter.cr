module Crig
  module Providers
    module OpenRouter
      OPENROUTER_API_BASE_URL = "https://openrouter.ai/api/v1"
    end
  end
end

require "./openrouter/client"
require "./openrouter/completion"
require "./openrouter/embedding"
require "./openrouter/streaming"
require "./openrouter/audio_generation"
require "./openrouter/transcription"
require "./openrouter/model_listing"
