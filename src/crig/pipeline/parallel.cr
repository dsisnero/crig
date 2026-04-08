module Crig
  module Pipeline
    struct Parallel(Op1, Op2, Input, Output1, Output2)
      include Op(Input, Tuple(Output1, Output2))

      getter op1 : Op1
      getter op2 : Op2

      def initialize(@op1 : Op1, @op2 : Op2)
      end

      def call(input : Input) : Tuple(Output1, Output2)
        left_channel = Channel(Output1 | Exception).new(1)
        right_channel = Channel(Output2 | Exception).new(1)

        spawn do
          begin
            left_channel.send(@op1.call(input))
          rescue ex : Exception
            left_channel.send(ex)
          end
        end

        spawn do
          begin
            right_channel.send(@op2.call(input))
          rescue ex : Exception
            right_channel.send(ex)
          end
        end

        left = left_channel.receive
        right = right_channel.receive

        raise left if left.is_a?(Exception)
        raise right if right.is_a?(Exception)

        {left.as(Output1), right.as(Output2)}
      end
    end

    struct ParallelTry(Op1, Op2, Input, Output1, Output2, Error)
      include Op(Input, Crig::Pipeline::Result(Tuple(Output1, Output2), Error))
      include Crig::Pipeline::TryOp(Input, Tuple(Output1, Output2), Error)

      getter op1 : Op1
      getter op2 : Op2

      def initialize(@op1 : Op1, @op2 : Op2)
      end

      def call(input : Input) : Crig::Pipeline::Result(Tuple(Output1, Output2), Error)
        first_channel = @op1.call_async(input)
        second_channel = @op2.call_async(input)

        first = first_channel.receive.unwrap
        second = second_channel.receive.unwrap

        if error = first.error
          return Crig::Pipeline::Result(Tuple(Output1, Output2), Error).err(error)
        end

        if error = second.error
          return Crig::Pipeline::Result(Tuple(Output1, Output2), Error).err(error)
        end

        left = first.value || raise "parallel result missing left value"
        right = second.value || raise "parallel result missing right value"
        Crig::Pipeline::Result(Tuple(Output1, Output2), Error).ok({left, right})
      end
    end

    def self.parallel(
      op1 : Crig::Pipeline::TryOp(Input, Output1, Error),
      op2 : Crig::Pipeline::TryOp(Input, Output2, Error),
    ) forall Input, Output1, Output2, Error
      ParallelTry(typeof(op1), typeof(op2), Input, Output1, Output2, Error).new(op1, op2)
    end

    def self.parallel(
      op1 : Crig::Pipeline::Op(Input, Output1),
      op2 : Crig::Pipeline::Op(Input, Output2),
    ) forall Input, Output1, Output2
      Parallel(typeof(op1), typeof(op2), Input, Output1, Output2).new(op1, op2)
    end

    def self.parallel(
      op1 : Crig::Pipeline::Op(Input, Output1),
      op2 : Crig::Pipeline::Op(Input, Output2),
      op3 : Crig::Pipeline::Op(Input, Output3),
    ) forall Input, Output1, Output2, Output3
      inner = Parallel(typeof(op1), typeof(op2), Input, Output1, Output2).new(op1, op2)
      Parallel(typeof(inner), typeof(op3), Input, Tuple(Output1, Output2), Output3).new(inner, op3)
    end

    def self.parallel(
      op1 : Crig::Pipeline::Op(Input, Output1),
      op2 : Crig::Pipeline::Op(Input, Output2),
      op3 : Crig::Pipeline::Op(Input, Output3),
      op4 : Crig::Pipeline::Op(Input, Output4),
    ) forall Input, Output1, Output2, Output3, Output4
      inner2 = Parallel(typeof(op1), typeof(op2), Input, Output1, Output2).new(op1, op2)
      inner3 = Parallel(typeof(inner2), typeof(op3), Input, Tuple(Output1, Output2), Output3).new(inner2, op3)
      Parallel(typeof(inner3), typeof(op4), Input, Tuple(Tuple(Output1, Output2), Output3), Output4).new(inner3, op4)
    end
  end
end
