module Crig
  module Client
    # Shared client mixin for embedding-capable providers.
    # The builder helpers here are the most ergonomic way to construct embedding jobs.
    module EmbeddingsClient(M)
      abstract def embedding_model(model : String) : M
      abstract def embedding_model_with_ndims(model : String, ndims : Int32) : M

      # Start an embeddings builder from the provider's default dimensions for a model.
      def embeddings(model : String) : Crig::Embeddings::EmbeddingsBuilderInitializer(M)
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model(model))
      end

      # Typed overload kept for parity with the Rust method-level generic call sites.
      def embeddings(type : D.class, model : String) : Crig::Embeddings::EmbeddingsBuilderInitializer(M) forall D
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model(model))
      end

      # Start an embeddings builder with explicit dimensions.
      def embeddings_with_ndims(model : String, ndims : Int32) : Crig::Embeddings::EmbeddingsBuilderInitializer(M)
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model_with_ndims(model, ndims))
      end

      # Typed overload kept for parity with the Rust method-level generic call sites.
      def embeddings_with_ndims(type : D.class, model : String, ndims : Int32) : Crig::Embeddings::EmbeddingsBuilderInitializer(M) forall D
        Crig::Embeddings::EmbeddingsBuilderInitializer(M).new(embedding_model_with_ndims(model, ndims))
      end
    end

    # Dynamic embedding client surface used by the dyn-client builder.
    module EmbeddingsClientDyn
      abstract def embedding_model(model : String) : Crig::EmbeddingModelDyn
      abstract def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::EmbeddingModelDyn
    end
  end
end
