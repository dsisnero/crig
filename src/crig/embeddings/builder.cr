module Crig
  module Embeddings
    struct EmbeddingsBuilder(M, T)
      getter model : M
      getter documents : Array({T, Array(String)})

      def initialize(@model : M, @documents : Array({T, Array(String)}) = [] of {T, Array(String)})
      end

      def self.new(model : M) forall M
        allocate.tap do |value|
          value.initialize(model)
        end
      end

      def document(document : T) : self forall T
        texts = Crig::Embeddings.to_texts(document.as(Embed))
        self.class.new(@model, @documents + [{document, texts}])
      end

      def documents(documents : Enumerable(T)) : self forall T
        documents.reduce(self) { |builder, document| builder.document(document) }
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
