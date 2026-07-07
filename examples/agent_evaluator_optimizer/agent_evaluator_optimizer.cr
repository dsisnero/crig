require "../../src/crig"

# Ported from vendor/rig/examples/agent_evaluator_optimizer/src/main.rs
#
# Demonstrates the evaluator-optimizer pattern:
#   1. A generator agent creates a solution for a task
#   2. An evaluator agent reviews it and provides feedback
#   3. The generator iterates using the feedback until the evaluator passes
#
# Requires DEEPSEEK_API_KEY.

struct Evaluation
  include JSON::Serializable

  enum EvalStatus
    Pass
    NeedsImprovement
    Fail
  end

  getter evaluation_status : EvalStatus
  getter feedback : String

  def initialize(@evaluation_status : EvalStatus, @feedback : String)
  end
end

TASK = "Implement a Stack with:
1. push(x)
2. pop()
3. getMin()
All operations should be O(1).
"

client = Crig::Providers::DeepSeek::Client.from_env
model_name = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

generator_agent = client.agent(model_name)
  .preamble(
    "Your goal is to complete the task based on <user input>. If there are feedback
    from your previous generations, you should reflect on them to improve your solution

    Output your answer concisely in the following format:

    Thoughts:
    [Your understanding of the task and feedback and how you plan to improve]

    Response:
    [Your code implementation here]",
  )
  .build

evaluator_agent = client.extractor(Evaluation, model_name)
  .preamble(
    "Evaluate this following code implementation for:
    1. code correctness
    2. time complexity
    3. style and best practices

    You should be evaluating only and not attempting to solve the task.

    Only output \"PASS\" if all criteria are met and you have no further suggestions for improvements.

    Provide detailed feedback if there are areas that need improvement. You should specify what needs improvement and why.

    Only output JSON.",
  )
  .build

memories = [] of String
response = generator_agent.prompt(TASK).send
memories << response

loop do
  eval_result = evaluator_agent.extract("#{TASK}\n\n#{response}")

  if eval_result.evaluation_status.pass?
    break
  else
    context = "#{TASK}\n\n#{eval_result.feedback}"
    response = generator_agent.prompt(context).send
    memories << response
  end
end

puts "Response: #{response}"
