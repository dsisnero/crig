module Crig
  module Client
    module EmbeddingsClient(M)
      abstract def embedding_model(model : String) : M
      abstract def embedding_model_with_ndims(model : String, ndims : Int32) : M

      def embeddings(type : D.class, model : String) : Crig::Embeddings::EmbeddingsBuilderInitializer(M) forall D
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model(model))
      end

      def embeddings_with_ndims(type : D.class, model : String, ndims : Int32) : Crig::Embeddings::EmbeddingsBuilderInitializer(M) forall D
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model_with_ndims(model, ndims))
      end
    end

    module EmbeddingsClientDyn
      abstract def embedding_model(model : String) : Crig::EmbeddingModelDyn
      abstract def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::EmbeddingModelDyn
    end
  end
end
