module Crig
  module Pipeline
    module Op(Input, Output)
      abstract def call(input : Input) : Output

      def call_async(input : Input) : Channel(Crig::Concurrency::Result(Output))
        Crig::Concurrency.run do
          call(input)
        end
      end

      def batch_call(_n : Int32, input : Enumerable(Input)) : Array(Output)
        input.map { |item| call(item) }.to_a
      end

      def batch_call_async(n : Int32, input : Enumerable(Input)) : Channel(Crig::Concurrency::Result(Array(Output)))
        Crig::Concurrency.run do
          batch_call(n, input)
        end
      end

      def map(f : Proc(Output, NextOutput)) forall NextOutput
        Sequential(typeof(self), Crig::Pipeline::Map(Output, NextOutput), Input, NextOutput).new(
          self,
          Crig::Pipeline::Map(Output, NextOutput).new(f)
        )
      end

      def map(&block : Output -> NextOutput) forall NextOutput
        map(block)
      end

      def and_then(f : Proc(Output, NextOutput)) forall NextOutput
        Sequential(typeof(self), Crig::Pipeline::Then(Output, NextOutput), Input, NextOutput).new(
          self,
          Crig::Pipeline::Then(Output, NextOutput).new(f)
        )
      end

      def and_then(&block : Output -> NextOutput) forall NextOutput
        and_then(block)
      end

      def chain(op : Crig::Pipeline::Op(Output, NextOutput)) forall NextOutput
        Sequential(typeof(self), typeof(op), Input, NextOutput).new(self, op)
      end

      def lookup(index, n : Int32, type : T.class) forall T
        _ = type
        Crig::Pipeline::SequentialTry(typeof(self), Crig::Pipeline::AgentOps::Lookup(typeof(index), Output, T), Input, Array(Tuple(Float64, String, T)), Crig::VectorStoreError).new(
          self,
          Crig::Pipeline::AgentOps::Lookup(typeof(index), Output, T).new(index, n)
        )
      end

      def prompt(agent)
        Crig::Pipeline::SequentialTry(typeof(self), Crig::Pipeline::AgentOps::Prompt(typeof(agent), Output), Input, String, Crig::Completion::PromptError).new(
          self,
          Crig::Pipeline::AgentOps::Prompt(typeof(agent), Output).new(agent)
        )
      end

      def extract(extractor : Crig::Extractor(M, T)) forall M, T
        Crig::Pipeline::SequentialTry(typeof(self), Crig::Pipeline::AgentOps::Extract(M, Output, T), Input, T, Crig::ExtractionError).new(
          self,
          Crig::Pipeline::AgentOps::Extract(M, Output, T).new(extractor)
        )
      end
    end

    struct Sequential(Prev, NextOp, Input, Output)
      include Op(Input, Output)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Output
        @op.call(@prev.call(input))
      end
    end

    struct Map(Input, Output)
      include Op(Input, Output)

      def initialize(@f : Proc(Input, Output))
      end

      def call(input : Input) : Output
        @f.call(input)
      end
    end

    def self.map(f : Proc(Input, Output)) forall Input, Output
      Map(Input, Output).new(f)
    end

    def self.map(&block : Input -> Output) forall Input, Output
      map(block)
    end

    struct Passthrough(T)
      include Op(T, T)

      def call(input : T) : T
        input
      end
    end

    def self.passthrough(type : T.class) : Passthrough(T) forall T
      _ = type
      Passthrough(T).new
    end

    struct Then(Input, Output)
      include Op(Input, Output)

      def initialize(@f : Proc(Input, Output))
      end

      def call(input : Input) : Output
        @f.call(input)
      end
    end

    def self.and_then(f : Proc(Input, Output)) forall Input, Output
      Then(Input, Output).new(f)
    end

    def self.and_then(&block : Input -> Output) forall Input, Output
      and_then(block)
    end
  end
end
