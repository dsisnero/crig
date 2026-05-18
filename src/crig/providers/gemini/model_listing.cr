require "http/client"

module Crig
  module Providers
    module Gemini
      struct GeminiModelLister
        include Crig::Client::ModelLister(Crig::Providers::Gemini::Client)

        getter client : Crig::Providers::Gemini::Client

        def initialize(@client : Crig::Providers::Gemini::Client)
        end

        def list_all : Crig::ModelList
          path = "/v1beta/models"
          uri = "#{@client.base_url.rstrip('/')}/#{path.lstrip('/')}?key=#{@client.api_key}"
          headers = HTTP::Headers{"Accept" => "application/json"}
          response = HTTP::Client.get(uri, headers: headers)
          raise Crig::ModelListingError.api_error(response.status_code, response.body) unless response.success?

          parsed = JSON.parse(response.body)
          entries = parsed["models"].as_a.map do |entry|
            id = entry["name"].as_s.split('/').last
            Crig::Model::Model.new(
              id,
              name: entry["displayName"]?.try(&.as_s),
              description: entry["description"]?.try(&.as_s),
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
