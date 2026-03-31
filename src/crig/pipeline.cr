module Crig
  module Pipeline
    class ChainError < Exception
      enum Kind
        PromptError
        LookupError
      end

      getter kind : Kind
      getter wrapped_error : Exception

      def initialize(@kind : Kind, @wrapped_error : Exception)
        super(@wrapped_error.message || @wrapped_error.class.name)
      end

      def self.prompt_error(cause : Crig::Completion::PromptError) : self
        new(Kind::PromptError, cause)
      end

      def self.lookup_error(cause : Crig::VectorStoreError) : self
        new(Kind::LookupError, cause)
      end
    end

    struct Result(T, E)
      getter value : T?
      getter error : E?

      def initialize(@value : T? = nil, @error : E? = nil)
      end

      def self.ok(value : T) : self
        new(value: value)
      end

      def self.err(error : E) : self
        new(error: error)
      end

      def unwrap : T
        if error = @error
          raise error if error.is_a?(Exception)
          raise error.to_s
        end

        {% if T == Nil %}
          return nil
        {% end %}

        @value || raise "pipeline result missing value"
      end
    end

    struct PipelineBuilder(E)
      def map(f : Proc(Input, Output)) forall Input, Output
        Crig::Pipeline::Map(Input, Output).new(f)
      end

      def map(&block : Input -> Output) forall Input, Output
        map(block)
      end

      def and_then(f : Proc(Input, Output)) forall Input, Output
        Crig::Pipeline::Then(Input, Output).new(f)
      end

      def and_then(&block : Input -> Output) forall Input, Output
        and_then(block)
      end

      def chain(op)
        op
      end

      def lookup(index, n : Int32, type : Output.class) forall Output
        _ = type
        Crig::Pipeline::AgentOps::Lookup(typeof(index), String, Output).new(index, n)
      end

      def prompt(agent)
        Crig::Pipeline::AgentOps::Prompt(typeof(agent), String).new(agent)
      end

      def extract(extractor : Crig::Extractor(M, Output)) forall M, Output
        Crig::Pipeline::AgentOps::Extract(M, String, Output).new(extractor)
      end

      def passthrough(type : T.class) forall T
        _ = type
        Crig::Pipeline::Passthrough(T).new
      end

      def parallel(
        op1 : Crig::Pipeline::Op(Input, Output1),
        op2 : Crig::Pipeline::Op(Input, Output2),
      ) forall Input, Output1, Output2
        Crig::Pipeline.parallel(op1, op2)
      end

      def parallel(
        op1 : Crig::Pipeline::Op(Input, Output1),
        op2 : Crig::Pipeline::Op(Input, Output2),
        op3 : Crig::Pipeline::Op(Input, Output3),
      ) forall Input, Output1, Output2, Output3
        Crig::Pipeline.parallel(op1, op2, op3)
      end

      def parallel(
        op1 : Crig::Pipeline::Op(Input, Output1),
        op2 : Crig::Pipeline::Op(Input, Output2),
        op3 : Crig::Pipeline::Op(Input, Output3),
        op4 : Crig::Pipeline::Op(Input, Output4),
      ) forall Input, Output1, Output2, Output3, Output4
        Crig::Pipeline.parallel(op1, op2, op3, op4)
      end
    end

    def self.new : PipelineBuilder(ChainError)
      PipelineBuilder(ChainError).new
    end

    def self.with_error(type : E.class) : PipelineBuilder(E) forall E
      _ = type
      PipelineBuilder(E).new
    end
  end

  alias PipelineBuilder = Pipeline::PipelineBuilder
  alias ChainError = Pipeline::ChainError
end

require "./pipeline/op"
require "./pipeline/try_op"
require "./pipeline/parallel"
require "./pipeline/conditional"
require "./pipeline/agent_ops"
