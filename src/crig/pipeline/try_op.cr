module Crig
  module Pipeline
    module TryOp(Input, Output, Error)
    end

    struct SequentialTry(Prev, NextOp, Input, Output, Error)
      include Op(Input, Crig::Pipeline::Result(Output, Error))
      include Crig::Pipeline::TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        @op.call(@prev.call(input))
      end
    end

    struct MapTry(Input, Output, Error)
      include Op(Input, Crig::Pipeline::Result(Output, Error))
      include Crig::Pipeline::TryOp(Input, Output, Error)

      def initialize(@f : Proc(Input, Crig::Pipeline::Result(Output, Error)))
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        @f.call(input)
      end
    end

    def self.map(f : Proc(Input, Crig::Pipeline::Result(Output, Error))) forall Input, Output, Error
      MapTry(Input, Output, Error).new(f)
    end

    struct ThenTry(Input, Output, Error)
      include Op(Input, Crig::Pipeline::Result(Output, Error))
      include Crig::Pipeline::TryOp(Input, Output, Error)

      def initialize(@f : Proc(Input, Crig::Pipeline::Result(Output, Error)))
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        @f.call(input)
      end
    end

    def self.and_then(f : Proc(Input, Crig::Pipeline::Result(Output, Error))) forall Input, Output, Error
      Then(Input, Output, Error).new(f)
    end

    def self.and_then(&block : Input -> Crig::Pipeline::Result(Output, Error)) forall Input, Output, Error
      and_then(block)
    end

    module TryOp(Input, Output, Error)
      include Op(Input, Crig::Pipeline::Result(Output, Error))

      def try_call(input : Input) : Crig::Pipeline::Result(Output, Error)
        call(input)
      end

      def try_call_async(input : Input) : Channel(Crig::Concurrency::Result(Crig::Pipeline::Result(Output, Error)))
        Crig::Concurrency.run do
          try_call(input)
        end
      end

      def try_batch_call(_n : Int32, input : Enumerable(Input)) : Crig::Pipeline::Result(Array(Output), Error)
        output = [] of Output

        input.each do |item|
          result = try_call(item)
          if error = result.error
            return Crig::Pipeline::Result(Array(Output), Error).err(error)
          end

          if value = result.value
            output << value
          end
        end

        Crig::Pipeline::Result(Array(Output), Error).ok(output)
      end

      def try_batch_call_async(n : Int32, input : Enumerable(Input)) : Channel(Crig::Concurrency::Result(Crig::Pipeline::Result(Array(Output), Error)))
        Crig::Concurrency.run do
          try_batch_call(n, input)
        end
      end

      def map_ok(f : Proc(Output, NextOutput)) forall NextOutput
        MapOk(typeof(self), Crig::Pipeline::Map(Output, NextOutput), Input, Output, Error, NextOutput).new(
          self,
          Crig::Pipeline::Map(Output, NextOutput).new(f)
        )
      end

      def map_ok(&block : Output -> NextOutput) forall NextOutput
        map_ok(block)
      end

      def map_err(&block : Error -> NextError) forall NextError
        map_err(block)
      end

      def map_err(f : Proc(Error, NextError)) forall NextError
        MapErr(typeof(self), Crig::Pipeline::Map(Error, NextError), Input, Output, Error, NextError).new(
          self,
          Crig::Pipeline::Map(Error, NextError).new(f)
        )
      end

      def map_err(&block : Error -> NextError) forall NextError
        map_err(block)
      end

      def and_then(f : Proc(Output, Crig::Pipeline::Result(NextOutput, Error))) forall NextOutput
        AndThen(typeof(self), Crig::Pipeline::ThenTry(Output, NextOutput, Error), Input, Output, Error, NextOutput).new(
          self,
          Crig::Pipeline::ThenTry(Output, NextOutput, Error).new(f)
        )
      end

      def or_else(f : Proc(Error, Crig::Pipeline::Result(Output, NextError))) forall NextError
        OrElse(typeof(self), Crig::Pipeline::ThenTry(Error, Output, NextError), Input, Output, Error, NextError).new(
          self,
          Crig::Pipeline::ThenTry(Error, Output, NextError).new(f)
        )
      end

      def chain_ok(op : Crig::Pipeline::Op(Output, NextOutput)) forall NextOutput
        TrySequential(typeof(self), typeof(op), Input, Output, Error, NextOutput).new(self, op)
      end

      def lookup(index, n : Int32, type : T.class) forall T
        _ = type
        and_then(->(value : Output) { Crig::Pipeline::AgentOps::Lookup(typeof(index), Output, T).new(index, n).call(value) })
      end

      def prompt(agent)
        and_then(->(value : Output) { Crig::Pipeline::AgentOps::Prompt(typeof(agent), Output).new(agent).call(value) })
      end

      def extract(extractor : Crig::Extractor(M, T)) forall M, T
        and_then(->(value : Output) { Crig::Pipeline::AgentOps::Extract(M, Output, T).new(extractor).call(value) })
      end
    end

    struct MapOk(Prev, NextOp, Input, PrevOutput, Error, Output)
      include TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        result = @prev.try_call(input)
        if error = result.error
          return Crig::Pipeline::Result(Output, Error).err(error)
        end

        value = result.value || raise "pipeline result missing value"
        Crig::Pipeline::Result(Output, Error).ok(@op.call(value))
      end
    end

    struct MapErr(Prev, NextOp, Input, Output, PrevError, Error)
      include TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        result = @prev.try_call(input)
        unless error = result.error
          value = result.value || raise "pipeline result missing value"
          return Crig::Pipeline::Result(Output, Error).ok(value)
        end

        Crig::Pipeline::Result(Output, Error).err(@op.call(error))
      end
    end

    struct AndThen(Prev, NextOp, Input, PrevOutput, Error, Output)
      include TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        result = @prev.try_call(input)
        if error = result.error
          return Crig::Pipeline::Result(Output, Error).err(error)
        end

        value = result.value || raise "pipeline result missing value"
        @op.call(value)
      end
    end

    struct OrElse(Prev, NextOp, Input, Output, PrevError, Error)
      include TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        result = @prev.try_call(input)
        unless error = result.error
          value = result.value || raise "pipeline result missing value"
          return Crig::Pipeline::Result(Output, Error).ok(value)
        end

        @op.call(error)
      end
    end

    struct TrySequential(Prev, NextOp, Input, PrevOutput, Error, Output)
      include TryOp(Input, Output, Error)

      getter prev : Prev
      getter op : NextOp

      def initialize(@prev : Prev, @op : NextOp)
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        result = @prev.try_call(input)
        if error = result.error
          return Crig::Pipeline::Result(Output, Error).err(error)
        end

        value = result.value || raise "pipeline result missing value"
        Crig::Pipeline::Result(Output, Error).ok(@op.call(value))
      end
    end
  end
end
