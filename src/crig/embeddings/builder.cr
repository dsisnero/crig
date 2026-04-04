module Crig
  module Embeddings
    # Initializer for creating embeddings builders.
    # Returned by `Crig::Embeddings.builder(model)` to allow type inference.
    struct EmbeddingsBuilderInitializer(M)
      getter model : M

      def initialize(@model : M)
      end

      # Add a document to be embedded.
      # The document can be a String or any type that implements the `Embed` interface.
      # Returns an `EmbeddingsBuilder` with the inferred document type.
      def document(document : T) : EmbeddingsBuilder(M, T) forall T
        texts = Crig::Embeddings.to_texts(document)
        array = Array({T, Array(String)}).new(1)
        array << {document, texts}
        EmbeddingsBuilder(M, T).new(@model, array)
      rescue error : Exception
        raise error.is_a?(Crig::Embeddings::EmbedError) ? error : Crig::Embeddings::EmbedError.new(error)
      end

      def simple_document(id : String, text : String) : EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)
        document(Crig::Embeddings::SimpleDocument.new(id, text))
      end

      # Add multiple documents to be embedded.
      # Returns an `EmbeddingsBuilder` with the inferred document type.
      def documents(documents : Enumerable(T)) : EmbeddingsBuilder(M, T) forall T
        builder = nil
        documents.each do |document|
          if builder.nil?
            builder = document(document)
          else
            builder = builder.document(document)
          end
        end
        builder || raise ArgumentError.new("documents cannot be empty")
      end

      def all_simple_documents(documents : Enumerable(Tuple(String, String))) : EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)
        builder = nil
        documents.each do |id, text|
          if builder.nil?
            builder = simple_document(id, text)
          else
            builder = builder.simple_document(id, text)
          end
        end
        builder || raise ArgumentError.new("documents cannot be empty")
      end
    end

    # A builder for creating embeddings from documents.
    # Start with `Crig::Embeddings.builder(model)` or `EmbeddingsBuilder.new(model)` then add documents.
    # The document type `T` is inferred from the first document added.
    struct EmbeddingsBuilder(M, T)
      getter model : M
      getter documents : Array({T, Array(String)})

      # Create a new embeddings builder with the given model.
      # The document type `T` will be inferred when you add the first document.
      def self.new(model : M) : EmbeddingsBuilderInitializer(M) forall M
        EmbeddingsBuilderInitializer(M).new(model)
      end

      def initialize(@model : M, @documents : Array({T, Array(String)}) = [] of {T, Array(String)})
      end

      # Add a document to be embedded.
      # The document can be a String or any type that implements the `Embed` interface.
      def document(document : T) : self
        texts = Crig::Embeddings.to_texts(document)
        self.class.new(@model, @documents + [{document, texts}])
      rescue error : Exception
        raise error.is_a?(Crig::Embeddings::EmbedError) ? error : Crig::Embeddings::EmbedError.new(error)
      end

      def simple_document(id : String, text : String) : self
        {% if T == Crig::Embeddings::SimpleDocument %}
          document(Crig::Embeddings::SimpleDocument.new(id, text))
        {% else %}
          {% raise "simple_document is only available for EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)" %}
        {% end %}
      end

      # Add multiple documents to be embedded.
      def documents(documents : Enumerable(T)) : self
        documents.reduce(self) { |builder, document| builder.document(document) }
      end

      def all_simple_documents(documents : Enumerable(Tuple(String, String))) : self
        {% if T == Crig::Embeddings::SimpleDocument %}
          documents.reduce(self) { |builder, (id, text)| builder.simple_document(id, text) }
        {% else %}
          {% raise "all_simple_documents is only available for EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)" %}
        {% end %}
      end

      def build : Array({T, Crig::OneOrMany(Embedding)})
        docs = @documents.map(&.[0])
        grouped_texts = @documents.map(&.[1])
        flattened = [] of {Int32, String}

        grouped_texts.each_with_index do |texts, index|
          texts.each do |text|
            flattened << {index, text}
          end
        end

        embeddings_by_doc = Hash(Int32, Array(Embedding)).new { |hash, key| hash[key] = [] of Embedding }
        batch_size = Math.max(1, @model.max_documents)

        flattened.each_slice(batch_size) do |batch|
          ids = batch.map(&.[0])
          texts = batch.map(&.[1])
          embeddings = @model.embed_texts(texts)

          ids.zip(embeddings) do |id, embedding|
            embeddings_by_doc[id] << embedding
          end
        end

        docs.each_with_index.map do |document, index|
          {document, Crig::OneOrMany(Embedding).many(embeddings_by_doc[index])}
        end.to_a
      end
    end
  end
end
