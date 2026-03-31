module Crig
  module Providers
    module HuggingFace
      HUGGINGFACE_API_BASE_URL = "https://router.huggingface.co"

      enum SubProviderKind
        HFInference
        Together
        SambaNova
        Fireworks
        Hyperbolic
        Nebius
        Novita
        Custom
      end

      struct SubProvider
        getter kind : SubProviderKind
        getter custom_route : String?

        def initialize(@kind : SubProviderKind = SubProviderKind::HFInference, @custom_route : String? = nil)
        end

        def self.hf_inference : self
          new(SubProviderKind::HFInference)
        end

        def self.together : self
          new(SubProviderKind::Together)
        end

        def self.sambanova : self
          new(SubProviderKind::SambaNova)
        end

        def self.fireworks : self
          new(SubProviderKind::Fireworks)
        end

        def self.hyperbolic : self
          new(SubProviderKind::Hyperbolic)
        end

        def self.nebius : self
          new(SubProviderKind::Nebius)
        end

        def self.novita : self
          new(SubProviderKind::Novita)
        end

        def self.custom(route : String) : self
          new(SubProviderKind::Custom, route)
        end

        def completion_endpoint(model : String) : String
          _ = model
          "v1/chat/completions"
        end

        def transcription_endpoint(model : String) : String
          if @kind == SubProviderKind::HFInference
            "/#{model}"
          else
            raise Crig::TranscriptionError.new("transcription endpoint is not supported yet for #{to_s}")
          end
        end

        def image_generation_endpoint(model : String) : String
          if @kind == SubProviderKind::HFInference
            "/#{model}"
          else
            raise Crig::ImageGenerationError.new("image generation endpoint is not supported yet for #{to_s}")
          end
        end

        def model_identifier(model : String) : String
          @kind == SubProviderKind::Fireworks ? "accounts/fireworks/models/#{model}" : model
        end

        def to_s(io : IO) : Nil
          route = case @kind
                  when SubProviderKind::HFInference then "hf-inference/models"
                  when SubProviderKind::Together    then "together"
                  when SubProviderKind::SambaNova   then "sambanova"
                  when SubProviderKind::Fireworks   then "fireworks-ai"
                  when SubProviderKind::Hyperbolic  then "hyperbolic"
                  when SubProviderKind::Nebius      then "nebius"
                  when SubProviderKind::Novita      then "novita"
                  when SubProviderKind::Custom      then @custom_route || ""
                  end
          io << route
        end
      end

      struct HuggingFaceExt
        getter subprovider : SubProvider

        def initialize(@subprovider : SubProvider = SubProvider.hf_inference)
        end
      end

      struct HuggingFaceBuilder
        getter subprovider : SubProvider

        def initialize(@subprovider : SubProvider = SubProvider.hf_inference)
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String
        getter subprovider : SubProvider

        def initialize(
          @api_key : String? = nil,
          @base_url : String = HUGGINGFACE_API_BASE_URL,
          @subprovider : SubProvider = SubProvider.hf_inference,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url, @subprovider)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url, @subprovider)
        end

        def subprovider(subprovider : SubProvider) : self
          self.class.new(@api_key, @base_url, subprovider)
        end

        def build : Client
          key = @api_key || raise "HUGGINGFACE_API_KEY is not set"
          Client.new(key, @base_url, @subprovider)
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String
        getter subprovider : SubProvider

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = HUGGINGFACE_API_BASE_URL, @subprovider : SubProvider = SubProvider.hf_inference)
        end

        def self.new(api_key : String, base_url : String = HUGGINGFACE_API_BASE_URL, subprovider : SubProvider = SubProvider.hf_inference) : self
          new(Crig::BearerAuth.new(api_key), base_url, subprovider)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["HUGGINGFACE_API_KEY"]? || raise "HUGGINGFACE_API_KEY is not set"
          new(api_key)
        end

        def self.from_val(input : String) : self
          new(input)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{subprovider}/#{path.lstrip('/')}"
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          HTTP::Client.exec(
            "POST",
            build_uri(path),
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@api_key.token}",
              "Content-Type"  => "application/json",
              "Accept"        => accept,
            },
            body: body,
          )
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def transcription_model(model : String) : TranscriptionModel
          TranscriptionModel.new(self, model)
        end

        def image_generation_model(model : String) : ImageGenerationModel
          ImageGenerationModel.new(self, model)
        end
      end
    end
  end
end
