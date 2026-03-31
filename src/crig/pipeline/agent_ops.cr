module Crig
  module Pipeline
    module AgentOps
      struct Lookup(Index, Input, Output)
        include Crig::Pipeline::TryOp(Input, Array(Tuple(Float64, String, Output)), Crig::VectorStoreError)

        getter index : Index
        getter n : Int32

        def initialize(@index : Index, @n : Int32)
        end

        def call(input : Input) : Crig::Pipeline::Result(Array(Tuple(Float64, String, Output)), Crig::VectorStoreError)
          request = Crig::VectorSearchRequest.new(input.to_s, @n.to_u64)
          Crig::Pipeline::Result(Array(Tuple(Float64, String, Output)), Crig::VectorStoreError).ok(
            @index.top_n(request, Output)
          )
        rescue ex : Crig::VectorStoreError
          Crig::Pipeline::Result(Array(Tuple(Float64, String, Output)), Crig::VectorStoreError).err(ex)
        end
      end

      def self.lookup(index, n : Int32, type : Output.class) forall Output
        _ = type
        Lookup(typeof(index), String, Output).new(index, n)
      end

      struct Prompt(P, Input)
        include Crig::Pipeline::TryOp(Input, String, Crig::Completion::PromptError)

        getter prompt : P

        def initialize(@prompt : P)
        end

        def call(input : Input) : Crig::Pipeline::Result(String, Crig::Completion::PromptError)
          case prompt = @prompt
          when Crig::Agent
            Crig::Pipeline::Result(String, Crig::Completion::PromptError).ok(prompt.prompt(input.to_s).send)
          else
            Crig::Pipeline::Result(String, Crig::Completion::PromptError).ok(prompt.prompt(input.to_s))
          end
        rescue ex : Crig::Completion::PromptError
          Crig::Pipeline::Result(String, Crig::Completion::PromptError).err(ex)
        end
      end

      def self.prompt(prompt, type : Input.class) forall Input
        _ = type
        Prompt(typeof(prompt), Input).new(prompt)
      end

      struct Extract(M, Input, Output)
        include Crig::Pipeline::TryOp(Input, Output, Crig::ExtractionError)

        getter extractor : Crig::Extractor(M, Output)

        def initialize(@extractor : Crig::Extractor(M, Output))
        end

        def call(input : Input) : Crig::Pipeline::Result(Output, Crig::ExtractionError)
          message = input.is_a?(Crig::Completion::Message) ? input : input.to_s
          Crig::Pipeline::Result(Output, Crig::ExtractionError).ok(@extractor.extract(message))
        rescue ex : Crig::ExtractionError
          Crig::Pipeline::Result(Output, Crig::ExtractionError).err(ex)
        end
      end

      def self.extract(extractor : Crig::Extractor(M, Output), type : Input.class) forall M, Input, Output
        _ = type
        Extract(M, Input, Output).new(extractor)
      end
    end
  end
end
