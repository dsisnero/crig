require "http/client"

module Crig
  module Providers
    module OpenRouter
      struct OpenRouterModelLister
        include Crig::Client::ModelLister(Crig::Providers::OpenRouter::Client)

        getter client : Crig::Providers::OpenRouter::Client

        def initialize(@client : Crig::Providers::OpenRouter::Client)
        end

        def list_all : Crig::ModelList
          path = "/models"
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
              name: entry["name"]?.try(&.as_s),
              description: entry["description"]?.try(&.as_s),
              context_length: entry["context_length"]?.try(&.as_i),
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
