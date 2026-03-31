require "../src/crig"

module Crig::Examples::AgentEvaluatorOptimizer
  struct Evaluation
    include JSON::Serializable

    getter evaluation_status : EvalStatus
    getter feedback : String

    def initialize(@evaluation_status : EvalStatus, @feedback : String)
    end
  end

  enum EvalStatus
    Pass
    NeedsImprovement
    Fail
  end

  TASK = "Implement a Stack with:
1. push(x)
2. pop()
3. getMin()
All operations should be O(1).
  "

  def self.build_generator_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(
        "
        Your goal is to complete the task based on <user input>. If there are feedback
        from your previous generations, you should reflect on them to improve your solution

        Output your answer concisely in the following format:

        Thoughts:
        [Your understanding of the task and feedback and how you plan to improve]

        Response:
        [Your code implementation here]
      ")
      .build
  end

  def self.build_evaluator_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, Evaluation)
    client.extractor(Evaluation, model)
      .preamble("
        Evaluate this following code implementation for:
        1. code correctness
        2. time complexity
        3. style and best practices

        You should be evaluating only and not attempting to solve the task.

        Only output \"PASS\" if all criteria are met and you have no further suggestions for improvements.

        Provide detailed feedback if there are areas that need improvement. You should specify what needs improvement and why.

        Only output JSON.
      ")
      .build
  end

  def self.run_evaluation_loop(
    generator_agent : Crig::Agent(Crig::Providers::OpenAI::CompletionModel),
    evaluator_agent : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, Evaluation),
  ) : String
    memories = [] of String
    response = generator_agent.prompt(TASK).send
    memories << response

    loop do
      evaluation = evaluator_agent.extract("#{TASK}\n\n#{response}")
      if evaluation.evaluation_status == EvalStatus::Pass
        break
      else
        context = "#{TASK}\n\n#{evaluation.feedback}"
        response = generator_agent.prompt(context).send
        memories << response
      end
    end

    response
  end
end

# Main executable code - always run for examples
begin
  # Create OpenAI client
  client = Crig::Providers::OpenAI::Client.from_env
  completions_client = client.completions_api

  generator_agent = Crig::Examples::AgentEvaluatorOptimizer.build_generator_agent(completions_client)
  evaluator_agent = Crig::Examples::AgentEvaluatorOptimizer.build_evaluator_agent(client)

  response = Crig::Examples::AgentEvaluatorOptimizer.run_evaluation_loop(generator_agent, evaluator_agent)

  puts "Response: #{response}"
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
