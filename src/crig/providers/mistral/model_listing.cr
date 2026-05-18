require "http/client"

module Crig
  module Providers
    module Mistral
      struct MistralModelLister
        include Crig::Client::ModelLister(Crig::Providers::Mistral::Client)

        getter client : Crig::Providers::Mistral::Client

        def initialize(@client : Crig::Providers::Mistral::Client)
        end

        def list_all : Crig::ModelList
          path = "/v1/models"
          uri = "#{@client.base_url.rstrip('/')}/#{path.lstrip('/')}"
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@client.api_key}",
            "Accept"        => "application/json",
          }
          response = HTTP::Client.get(uri, headers: headers)
          raise Crig::ModelListingError.api_error(response.status_code, response.body) unless response.success?

          parsed = JSON.parse(response.body)
          entries = parsed["data"].as_a.map do |entry|
            Crig::Model::Model.new(
              entry["id"].as_s,
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
