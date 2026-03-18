module Crig
  module Embeddings
    module VectorDistance
      def dot_product(other : Embedding) : Float64
        vec.zip(other.vec).sum(0.0) { |x, y| x * y }
      end

      def cosine_similarity(other : Embedding, normalized : Bool) : Float64
        dot = dot_product(other)
        return dot if normalized

        magnitude1 = Math.sqrt(vec.sum(0.0) { |value| value**2 })
        magnitude2 = Math.sqrt(other.vec.sum(0.0) { |value| value**2 })
        dot / (magnitude1 * magnitude2)
      end

      def angular_distance(other : Embedding, normalized : Bool) : Float64
        Math.acos(cosine_similarity(other, normalized)) / Math::PI
      end

      def euclidean_distance(other : Embedding) : Float64
        Math.sqrt(vec.zip(other.vec).sum(0.0) { |x, y| (x - y)**2 })
      end

      def manhattan_distance(other : Embedding) : Float64
        vec.zip(other.vec).sum(0.0) { |x, y| (x - y).abs }
      end

      def chebyshev_distance(other : Embedding) : Float64
        vec.zip(other.vec).max_of { |x, y| (x - y).abs }
      end
    end

    struct Embedding
      include VectorDistance
    end
  end
end
