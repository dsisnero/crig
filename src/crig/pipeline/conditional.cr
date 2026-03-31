module Crig
  module Pipeline
    struct ConditionalOp(Input, Output)
      include Op(Input, Output)

      def initialize(@matcher : Proc(Input, Crig::Pipeline::Op(Input, Output)))
      end

      def call(input : Input) : Output
        op = @matcher.call(input)
        op.call(input)
      end
    end

    def self.conditional(type : Input.class, &block : Proc(Input, Crig::Pipeline::Op(Input, Output))) forall Input, Output
      _ = type
      ConditionalOp(Input, Output).new(block)
    end

    struct ConditionalTryOp(Input, Output, Error)
      include TryOp(Input, Output, Error)

      def initialize(@matcher : Proc(Input, Crig::Pipeline::TryOp(Input, Output, Error)))
      end

      def call(input : Input) : Crig::Pipeline::Result(Output, Error)
        op = @matcher.call(input)
        op.try_call(input)
      end
    end

    def self.try_conditional(type : Input.class, &block : Proc(Input, Crig::Pipeline::TryOp(Input, Output, Error))) forall Input, Output, Error
      _ = type
      ConditionalTryOp(Input, Output, Error).new(block)
    end
  end
end
