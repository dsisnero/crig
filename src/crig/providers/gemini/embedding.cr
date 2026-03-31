module Crig
  module Providers
    module Gemini
      EMBEDDING_001 = "gemini-embedding-001"
      EMBEDDING_004 = "text-embedding-004"

      enum TaskType
        Unspecified
        RetrievalQuery
        RetrievalDocument
        SemanticSimilarity
        Classification
        Clustering
        QuestionAnswering
        FactVerification

        def to_wire : String
          value = case self
                  in .unspecified?         then "UNSPECIFIED"
                  in .retrieval_query?     then "RETRIEVAL_QUERY"
                  in .retrieval_document?  then "RETRIEVAL_DOCUMENT"
                  in .semantic_similarity? then "SEMANTIC_SIMILARITY"
                  in .classification?      then "CLASSIFICATION"
                  in .clustering?          then "CLUSTERING"
                  in .question_answering?  then "QUESTION_ANSWERING"
                  in .fact_verification?   then "FACT_VERIFICATION"
                  end
          value
        end
      end

      struct EmbeddingContentPart
        getter text : String
        getter inline_data : Blob?
        getter function_call : FunctionCall?
        getter function_response : FunctionResponse?
        getter file_data : FileData?
        getter executable_code : ExecutableCode?
        getter code_execution_result : CodeExecutionResult?

        def initialize(
          @text : String,
          @inline_data : Blob? = nil,
          @function_call : FunctionCall? = nil,
          @function_response : FunctionResponse? = nil,
          @file_data : FileData? = nil,
          @executable_code : ExecutableCode? = nil,
          @code_execution_result : CodeExecutionResult? = nil,
        )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "text", @text
            if inline_data = @inline_data
              json.field "inlineData", inline_data
            end
            if function_call = @function_call
              json.field "functionCall", function_call
            end
            if function_response = @function_response
              json.field "functionResponse", function_response
            end
            if file_data = @file_data
              json.field "fileData", file_data
            end
            if executable_code = @executable_code
              json.field "executableCode", executable_code
            end
            if code_execution_result = @code_execution_result
              json.field "codeExecutionResult", code_execution_result
            end
          end
        end
      end

      struct EmbeddingContent
        getter parts : Array(EmbeddingContentPart)
        getter role : String?

        def initialize(@parts : Array(EmbeddingContentPart), @role : String? = nil)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "parts", @parts
            if role = @role
              json.field "role", role
            end
          end
        end
      end

      struct EmbedContentRequest
        getter model : String
        getter content : EmbeddingContent
        getter task_type : TaskType
        getter title : String?
        getter output_dimensionality : Int32?

        def initialize(
          @model : String,
          @content : EmbeddingContent,
          @task_type : TaskType = TaskType::Unspecified,
          @title : String? = nil,
          @output_dimensionality : Int32? = nil,
        )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "model", @model
            json.field "content", @content
            json.field "taskType", @task_type.to_wire
            if title = @title
              json.field "title", title
            end
            if output_dimensionality = @output_dimensionality
              json.field "outputDimensionality", output_dimensionality
            end
          end
        end
      end

      struct EmbeddingValues
        include JSON::Serializable

        getter values : Array(Float64)

        def initialize(@values : Array(Float64))
        end
      end

      struct EmbeddingResponse
        include JSON::Serializable

        getter embeddings : Array(EmbeddingValues)

        def initialize(@embeddings : Array(EmbeddingValues))
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32)
        end

        def self.make(client : Client, model : String, dims : Int32?) : self
          new(client, model, dims || 768)
        end

        def self.with_model(client : Client, model : String, dims : Int32?) : self
          make(client, model, dims)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a
          requests = documents.map do |document|
            EmbedContentRequest.new(
              "models/#{@model}",
              EmbeddingContent.new([EmbeddingContentPart.new(document)]),
              output_dimensionality: @ndims > 0 ? @ndims : nil,
            )
          end

          body = String.build do |io|
            JSON.build(io) do |json|
              json.object do
                json.field "requests" do
                  json.array do
                    requests.each(&.to_json(json))
                  end
                end
              end
            end
          end

          response = @client.post_json("/v1beta/models/#{@model}:batchEmbedContents", body)
          text = response.body
          if response.status_code >= 400
            raise Crig::Embeddings::EmbeddingError.new(text)
          end

          parsed = JSON.parse(text)
          body_wrapper = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = body_wrapper.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end

          embedding_response = body_wrapper.ok || raise(Crig::Embeddings::EmbeddingError.new("Missing Gemini embedding response"))
          if embedding_response.embeddings.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embedding_response.embeddings.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.values)
          end
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::Gemini::EmbeddingModel)

        def embedding_model(model : String) : Crig::Providers::Gemini::EmbeddingModel
          Crig::Providers::Gemini::EmbeddingModel.make(self, model, nil)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::Providers::Gemini::EmbeddingModel
          Crig::Providers::Gemini::EmbeddingModel.make(self, model, ndims)
        end
      end
    end
  end
end
