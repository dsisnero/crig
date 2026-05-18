require "http/client"

module Crig
  module Providers
    module OpenAI
      struct OpenAIModelLister
        include Crig::Client::ModelLister(Crig::Providers::OpenAI::Client)

        getter client : Crig::Providers::OpenAI::Client

        def initialize(@client : Crig::Providers::OpenAI::Client)
        end

        def list_all : Crig::ModelList
          path = "/models"
          uri = "#{@client.base_url.rstrip('/')}/#{path.lstrip('/')}"
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@client.api_key.token}",
            "Accept"        => "application/json",
          }
          response = HTTP::Client.get(uri, headers: headers)
          raise Crig::ModelListingError.api_error(response.status_code, response.body) unless response.success?

          parsed = JSON.parse(response.body)
          entries = parsed["data"].as_a.map do |entry|
            Crig::Model::Model.new(
              entry["id"].as_s,
              owned_by: entry["owned_by"]?.try(&.as_s),
              created_at: entry["created"]?.try(&.as_i64),
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
