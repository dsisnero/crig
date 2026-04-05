module Crig
  module Embeddings
    # Placeholder document type for an empty embeddings build.
    struct NoDocument
    end

    # Empty builder returned by `EmbeddingsBuilder.new(model)` before the first
    # document fixes the builder's document type.
    struct EmptyEmbeddingsBuilder(M)
      getter model : M

      def initialize(@model : M)
      end

      # Add a document to be embedded.
      # The document can be a String or any type that implements the `Embed` interface.
      def document(document : T) : EmbeddingsBuilder(M, T) forall T
        texts = Crig::Embeddings.to_texts(document)
        array = Array({T, Array(String)}).new(1)
        array << {document, texts}
        EmbeddingsBuilder(M, T).new(@model, array)
      rescue error : Exception
        raise error.is_a?(Crig::Embeddings::EmbedError) ? error : Crig::Embeddings::EmbedError.new(error)
      end

      # Convenience helper matching Rig's common `{id, text}` document workflow.
      def simple_document(id : String, text : String) : EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)
        document(Crig::Embeddings::SimpleDocument.new(id, text))
      end

      # Add multiple documents to be embedded.
      def documents(documents : Enumerable(T)) : EmbeddingsBuilder(M, T) forall T
        documents.reduce(EmbeddingsBuilder(M, T).empty(@model)) { |builder, document| builder.document(document) }
      end

      # Batch convenience helper for the builder-first simple-document path.
      def all_simple_documents(documents : Enumerable(Tuple(String, String))) : EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)
        documents.reduce(EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument).empty(@model)) do |builder, (id, text)|
          builder.simple_document(id, text)
        end
      end

      # Build an empty embeddings set, matching Rust's empty-builder behavior.
      def build : Array({Crig::Embeddings::NoDocument, Crig::OneOrMany(Embedding)})
        [] of {Crig::Embeddings::NoDocument, Crig::OneOrMany(Embedding)}
      end
    end

    # Builder for embedding jobs. This is the primary ergonomic surface used by
    # `client.embeddings(...)` and `client.embeddings_with_ndims(...)`.
    struct EmbeddingsBuilder(M, T)
      getter model : M
      getter documents : Array({T, Array(String)})

      # Start a builder directly from a model when you are not going through a client helper.
      def self.new(model : M) : EmptyEmbeddingsBuilder(M) forall M
        EmptyEmbeddingsBuilder(M).new(model)
      end

      def self.empty(model : M) : self
        new(model, [] of {T, Array(String)})
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

      # Convenience helper for the common `{id, text}` embedding case.
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

      # Batch convenience helper for the common `{id, text}` embedding case.
      def all_simple_documents(documents : Enumerable(Tuple(String, String))) : self
        {% if T == Crig::Embeddings::SimpleDocument %}
          documents.reduce(self) { |builder, (id, text)| builder.simple_document(id, text) }
        {% else %}
          {% raise "all_simple_documents is only available for EmbeddingsBuilder(M, Crig::Embeddings::SimpleDocument)" %}
        {% end %}
      end

      # Execute embedding requests in model-sized batches and return the
      # resulting embeddings grouped back by original document.
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
