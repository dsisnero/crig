require "./wasm_compat"
require "./audio_generation"
require "./agent"
require "./completion"
require "./embeddings"
require "./extractor"
require "./image_generation"
require "./model"
require "./streaming"
require "./transcription"
require "./client/base"

require "./client/audio_generation"
require "./client/builder"
require "./client/completion"
require "./client/embeddings"
require "./client/image_generation"
require "./client/model_listing"
require "./client/transcription"
require "./client/verify"

module Crig
  module Client
  end

  alias AudioGenerationClient = Client::AudioGenerationClient
  alias AudioGenerationClientDyn = Client::AudioGenerationClientDyn
  alias AudioGenerationModelHandle = Client::AudioGenerationModelHandle
  alias AnyClient = Client::AnyClient
  alias CompletionClient = Client::CompletionClient
  alias CompletionClientDyn = Client::CompletionClientDyn
  alias CompletionModelHandle = Client::CompletionModelHandle
  alias DefaultProviders = Client::DefaultProviders
  alias DynClientBuilder = Client::DynClientBuilder
  alias DynClientBuilderError = Client::DynClientBuilderError
  alias EmbeddingsClient = Client::EmbeddingsClient
  alias EmbeddingsClientDyn = Client::EmbeddingsClientDyn
  alias FinalCompletionResponse = Client::FinalCompletionResponse
  alias ImageGenerationClient = Client::ImageGenerationClient
  alias ImageGenerationClientDyn = Client::ImageGenerationClientDyn
  alias ImageGenerationModelHandle = Client::ImageGenerationModelHandle
  alias ModelLister = Client::ModelLister
  alias ModelListingClient = Client::ModelListingClient
  alias ProviderFactory = Client::ProviderFactory
  alias TranscriptionClient = Client::TranscriptionClient
  alias TranscriptionClientDyn = Client::TranscriptionClientDyn
  alias TranscriptionModelHandle = Client::TranscriptionModelHandle
  alias VerifyClient = Client::VerifyClient
  alias VerifyClientDyn = Client::VerifyClientDyn
  alias VerifyError = Client::VerifyError
end
