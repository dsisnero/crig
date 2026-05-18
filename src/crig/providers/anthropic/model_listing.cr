require "http/client"

module Crig
  module Providers
    module Anthropic
      struct AnthropicModelLister
        include Crig::Client::ModelLister(Crig::Providers::Anthropic::Client)

        getter client : Crig::Providers::Anthropic::Client

        def initialize(@client : Crig::Providers::Anthropic::Client)
        end

        def list_all : Crig::ModelList
          path = "/v1/models"
          uri = "#{@client.base_url.rstrip('/')}/#{path.lstrip('/')}"
          headers = HTTP::Headers{
            "x-api-key"         => @client.api_key,
            "anthropic-version" => "2023-06-01",
            "Accept"            => "application/json",
          }
          response = HTTP::Client.get(uri, headers: headers)
          raise Crig::ModelListingError.api_error(response.status_code, response.body) unless response.success?

          parsed = JSON.parse(response.body)
          entries = parsed["data"].as_a.map do |entry|
            Crig::Model::Model.new(
              entry["id"].as_s,
              name: entry["display_name"].as_s,
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
