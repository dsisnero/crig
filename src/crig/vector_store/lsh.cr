module Crig
  module VectorStore
    struct LSH
      getter hyperplanes : Array(Array(Float64))
      getter num_tables : Int32
      getter num_hyperplanes : Int32

      def initialize(dim : Int, @num_tables : Int32, @num_hyperplanes : Int32)
        rng = Random.new(seed_for(dim, @num_tables, @num_hyperplanes))
        @hyperplanes = Array(Array(Float64)).new(@num_tables * @num_hyperplanes) do
          plane = Array(Float64).new(dim) { rng.rand * 2.0 - 1.0 }
          norm = Math.sqrt(plane.sum(0.0) { |value| value * value })
          if norm > 0.0
            plane.map! { |value| value / norm }
          end
          plane
        end
      end

      def hash(vector : Array(Float64), table_idx : Int) : UInt64
        hash = 0_u64
        start = table_idx * @num_hyperplanes
        @hyperplanes[start, @num_hyperplanes].each_with_index do |hyperplane, index|
          dot = vector.zip(hyperplane).sum(0.0) { |value, normal| value * normal }
          if dot >= 0.0
            hash |= 1_u64 << index
          end
        end
        hash
      end

      private def seed_for(dim : Int, num_tables : Int32, num_hyperplanes : Int32) : UInt64
        dim.to_u64 ^ (num_tables.to_u64 << 21) ^ (num_hyperplanes.to_u64 << 42) ^ 0xC0D3_u64
      end
    end

    struct LSHIndex
      getter lsh : LSH
      getter tables : Array(Hash(UInt64, Array(String)))

      def initialize(dim : Int, num_tables : Int32, num_hyperplanes : Int32)
        @lsh = LSH.new(dim, num_tables, num_hyperplanes)
        @tables = Array(Hash(UInt64, Array(String))).new(num_tables) { Hash(UInt64, Array(String)).new }
      end

      def insert(id : String, embedding : Array(Float64)) : self
        @tables.each_with_index do |table, table_idx|
          hash = @lsh.hash(embedding, table_idx)
          ids = table[hash]? || begin
            table[hash] = [] of String
          end
          ids << id
        end
        self
      end

      def query(embedding : Array(Float64)) : Array(String)
        candidates = Set(String).new
        @tables.each_with_index do |table, table_idx|
          hash = @lsh.hash(embedding, table_idx)
          ids = table[hash]?
          next unless ids
          ids.each { |id| candidates << id }
        end
        candidates.to_a
      end

      def clear : self
        @tables.each(&.clear)
        self
      end
    end
  end
end
