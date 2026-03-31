require "./cohere/client"
require "./cohere/completion"
require "./cohere/embedding"
require "./cohere/streaming"

module Crig
  module Providers
    module Cohere
      COMMAND                     = "command"
      COMMAND_LIGHT               = "command-light"
      COMMAND_LIGHT_NIGHTLY       = "command-light-nightly"
      COMMAND_NIGHTLY             = "command-nightly"
      COMMAND_R                   = "command-r"
      COMMAND_R_PLUS              = "command-r-plus"
      EMBED_ENGLISH_V3            = "embed-english-v3.0"
      EMBED_ENGLISH_LIGHT_V3      = "embed-english-light-v3.0"
      EMBED_MULTILINGUAL_V3       = "embed-multilingual-v3.0"
      EMBED_MULTILINGUAL_LIGHT_V3 = "embed-multilingual-light-v3.0"

      def self.model_dimensions_from_identifier(model : String) : Int32?
        case model
        when EMBED_ENGLISH_V3, EMBED_MULTILINGUAL_V3
          1024
        when EMBED_ENGLISH_LIGHT_V3, EMBED_MULTILINGUAL_LIGHT_V3
          384
        end
      end
    end
  end
end
