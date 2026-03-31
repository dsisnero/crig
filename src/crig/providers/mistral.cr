module Crig
  module Providers
    module Mistral
      MISTRAL_API_BASE_URL = "https://api.mistral.ai"
    end
  end
end

require "./mistral/client"
require "./mistral/completion"
require "./mistral/embedding"
require "./mistral/transcription"

module Crig
  module Providers
    module Mistral
      struct Client
        include Crig::CompletionClient(Crig::Providers::Mistral::CompletionModel)
        include Crig::EmbeddingsClient(Crig::Providers::Mistral::EmbeddingModel)
        include Crig::TranscriptionClient(Crig::Providers::Mistral::TranscriptionModel)
      end
    end
  end
end
