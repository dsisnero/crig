require "../spec_helper"

module Crig
  describe ExtractionResponse do
    it "stores extracted data with usage" do
      response = ExtractionResponse(String).new(
        "hello",
        Completion::Usage.new(input_tokens: 1, output_tokens: 2)
      )

      response.data.should eq("hello")
      response.usage.input_tokens.should eq(1)
      response.usage.output_tokens.should eq(2)
    end
  end

  describe Extractor(FakeStructuredCompletionModel, WeatherPayload) do
    it "extracts payloads through the submit tool path" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        struct WeatherPayload
          include JSON::Serializable

          getter city : String
          getter temperature : Int32

          def initialize(@city : String, @temperature : Int32)
          end
        end

        class ProbeStructuredModel
          include Crig::Completion::CompletionModel

          getter last_request : Crig::Completion::Request::CompletionRequest?

          def completion(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(%({"city":"Denver","temperature":72})),
                )
              ),
              Crig::Completion::Usage.new(output_tokens: 4),
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        model = ProbeStructuredModel.new
        extractor = Crig::ExtractorBuilder(ProbeStructuredModel, WeatherPayload).new(model)
          .build
        payload = extractor.extract("weather")

        puts(JSON.build do |json|
          json.object do
            json.field "city", payload.city
            json.field "temperature", payload.temperature
            json.field "tools" do
              json.array do
                model.last_request.not_nil!.tools.each do |tool|
                  json.string(tool.name)
                end
              end
            end
          end
        end)
      CRYSTAL

      result["city"].as_s.should eq("Denver")
      result["temperature"].as_i.should eq(72)
      result["tools"].as_a.map(&.as_s).should contain("submit")
    end

    it "returns extracted data with usage" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        struct WeatherPayload
          include JSON::Serializable

          getter city : String
          getter temperature : Int32

          def initialize(@city : String, @temperature : Int32)
          end
        end

        class ProbeStructuredModel
          include Crig::Completion::CompletionModel

          def completion(request : Crig::Completion::Request::CompletionRequest)
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(%({"city":"Denver","temperature":72})),
                )
              ),
              Crig::Completion::Usage.new(output_tokens: 4),
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        model = ProbeStructuredModel.new
        extractor = Crig::ExtractorBuilder(ProbeStructuredModel, WeatherPayload).new(model)
          .build
        response = extractor.extract_with_usage("weather")

        puts(JSON.build do |json|
          json.object do
            json.field "city", response.data.city
            json.field "output_tokens", response.usage.output_tokens
          end
        end)
      CRYSTAL

      result["city"].as_s.should eq("Denver")
      result["output_tokens"].as_i.should eq(4)
    end

    it "forwards chat history into the completion request" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        struct WeatherPayload
          include JSON::Serializable

          getter city : String
          getter temperature : Int32

          def initialize(@city : String, @temperature : Int32)
          end
        end

        class ProbeStructuredModel
          include Crig::Completion::CompletionModel

          getter last_request : Crig::Completion::Request::CompletionRequest?

          def completion(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(%({"city":"Denver","temperature":72})),
                )
              ),
              Crig::Completion::Usage.new(output_tokens: 4),
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        model = ProbeStructuredModel.new
        extractor = Crig::ExtractorBuilder(ProbeStructuredModel, WeatherPayload).new(model)
          .build
        history = [Crig::Completion::Message.assistant("Earlier answer")]

        extractor.extract_with_chat_history("weather", history)

        puts(JSON.build do |json|
          json.object do
            json.field "roles" do
              json.array do
                model.last_request.not_nil!.chat_history.each do |message|
                  json.string(message.role.to_s)
                end
              end
            end
            json.field "texts" do
              json.array do
                model.last_request.not_nil!.chat_history.each do |message|
                  text = message.content.to_a.compact_map do |item|
                    if item.is_a?(Crig::Completion::UserContent) && item.kind.text?
                      item.text.try(&.text)
                    elsif item.is_a?(Crig::Completion::AssistantContent) && item.kind.text?
                      item.text.try(&.text)
                    end
                  end.first? || ""
                  json.string(text)
                end
              end
            end
          end
        end)
      CRYSTAL

      result["roles"].as_a.map(&.as_s).should eq(["Assistant", "User"])
      result["texts"].as_a.first.as_s.includes?("Earlier answer").should be_true
      result["texts"].as_a.last.as_s.includes?("weather").should be_true
    end
  end

  describe ExtractorBuilder(FakeStructuredCompletionModel, WeatherPayload) do
    it "forwards defaults, builder settings, and dynamic context into the built extractor" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        struct ProbeWeatherPayload
          include JSON::Serializable

          getter city : String
          getter temperature : Int32

          def initialize(@city : String, @temperature : Int32)
          end
        end

        struct ProbeStoredDoc
          include JSON::Serializable

          getter id : String
          getter name : String

          def initialize(@id : String, @name : String)
          end
        end

        class ProbeStructuredCompletionModel
          include Crig::Completion::CompletionModel

          def completion(request : Crig::Completion::Request::CompletionRequest)
            submit_tool = request.tools.find { |tool| tool.name == "submit" }
            choice = if submit_tool
                       Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                         Crig::Completion::AssistantContent.tool_call(
                           "tool_call_submit",
                           "submit",
                           JSON.parse(%({"city":"Denver","temperature":72})),
                         )
                       )
                     else
                       Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                         Crig::Completion::AssistantContent.text(%({"city":"Denver","temperature":72}))
                       )
                     end

            Crig::Completion::CompletionResponse(String).new(
              choice,
              Crig::Completion::Usage.new(output_tokens: 4),
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            _ = request
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        class ProbeEmbeddingModel
          include Crig::Embeddings::EmbeddingModel

          def max_documents : Int32
            2
          end

          def ndims : Int32
            1
          end

          def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
            texts.map { |text| Crig::Embeddings::Embedding.new("embed:#{text}", [1.0]) }.to_a
          end
        end

        def vector_embedding(document : String, values : Array(Float64)) : Crig::OneOrMany(Crig::Embeddings::Embedding)
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(Crig::Embeddings::Embedding.new(document, values))
        end

        model = ProbeStructuredCompletionModel.new
        embedding_model = ProbeEmbeddingModel.new
        store = Crig::InMemoryVectorStore(ProbeStoredDoc).from_documents_with_ids([
          {
            "doc-1",
            ProbeStoredDoc.new("doc-1", "Denver"),
            vector_embedding("Denver weather", [1.0]),
          },
        ])
        index = store.index(embedding_model)
        request = Crig::VectorSearchRequest.new("weather", 1_u64)

        extractor = Crig::ExtractorBuilder(ProbeStructuredCompletionModel, ProbeWeatherPayload).new(model)
          .preamble("Only extract weather.")
          .context("Denver forecast")
          .additional_params(JSON.parse(%({"mode":"strict"})))
          .max_tokens(128)
          .tool_choice(Crig::Completion::ToolChoice.auto)
          .dynamic_context(1, index)
          .retries(2)
          .build

        puts(JSON.build do |json|
          json.object do
            json.field "retries", extractor.retries
            json.field "preamble", extractor.agent.preamble
            json.field "static_context" do
              json.array do
                extractor.agent.static_context.each { |doc| json.string(doc.text) }
              end
            end
            json.field "mode", extractor.agent.additional_params.try(&.["mode"].as_s)
            json.field "max_tokens", extractor.agent.max_tokens
            json.field "tool_choice_auto", extractor.agent.tool_choice == Crig::Completion::ToolChoice.auto
            json.field "has_output_schema", !extractor.agent.output_schema.nil?
            json.field "static_tools_size", extractor.agent.static_tools.size
            json.field "has_tool_server", !extractor.agent.tool_server_handle.nil?
            json.field "dynamic_context_size", extractor.agent.dynamic_context.size
            json.field "first_dynamic_doc_id", extractor.agent.dynamic_context.first.search(request).first[1]
          end
        end)
      CRYSTAL

      result["retries"].as_i.should eq(2)
      result["preamble"].as_s.includes?(Crig::EXTRACTOR_PREAMBLE).should be_true
      result["preamble"].as_s.includes?("ADDITIONAL INSTRUCTIONS").should be_true
      result["static_context"].as_a.map(&.as_s).should eq(["Denver forecast"])
      result["mode"].as_s.should eq("strict")
      result["max_tokens"].as_i64.should eq(128)
      result["tool_choice_auto"].as_bool.should be_true
      result["has_output_schema"].as_bool.should be_true
      result["static_tools_size"].as_i.should eq(0)
      result["dynamic_context_size"].as_i.should eq(1)
      result["first_dynamic_doc_id"].as_s.should eq("doc-1")
    end
  end

  describe ExtractionResponse(WeatherPayload) do
    it "stores extracted data and usage" do
      response = ExtractionResponse(WeatherPayload).new(
        WeatherPayload.new("Denver", 72),
        Completion::Usage.new(total_tokens: 4),
      )

      response.data.city.should eq("Denver")
      response.usage.total_tokens.should eq(4)
    end
  end

  describe ExtractionError do
    it "builds the parity-style no-data helper" do
      ExtractionError.no_data.message.should eq("No data extracted")
    end
  end
end
