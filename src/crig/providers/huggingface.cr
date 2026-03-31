module Crig
  module Providers
    module HuggingFace
    end
  end
end

require "./huggingface/client"
require "./huggingface/completion"
require "./huggingface/image_generation"
require "./huggingface/transcription"

module Crig
  module Providers
    module HuggingFace
      struct Client
        include Crig::CompletionClient(Crig::Providers::HuggingFace::CompletionModel)
        include Crig::TranscriptionClient(Crig::Providers::HuggingFace::TranscriptionModel)
        include Crig::ImageGenerationClient(Crig::Providers::HuggingFace::ImageGenerationModel)
      end
    end
  end
end
