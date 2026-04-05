require "../src/crig"

module Crig::Examples::Debate
  POSITION_A = <<-TEXT
               You believe that religion is a useful concept.
               This could be for security, financial, ethical, philosophical, metaphysical, religious or any kind of other reason.
               You choose what your arguments are.
               I will argue against you and you must rebuke me and try to convince me that I am wrong.
               Make your statements short and concise.
             TEXT

  POSITION_B = <<-TEXT
               You believe that religion is a harmful concept.
               This could be for security, financial, ethical, philosophical, metaphysical, religious or any kind of other reason.
               You choose what your arguments are.
               I will argue against you and you must rebuke me and try to convince me that I am wrong.
               Make your statements short and concise.
             TEXT

  struct Exchange
    getter prompt_a : String
    getter response_a : String
    getter response_b : String

    def initialize(@prompt_a : String, @response_a : String, @response_b : String)
    end
  end

  class Debater(A, B)
    getter agent_a : Crig::Agent(A)
    getter agent_b : Crig::Agent(B)
    getter label_a : String
    getter label_b : String

    def initialize(
      @agent_a : Crig::Agent(A),
      @agent_b : Crig::Agent(B),
      @label_a : String = "GPT-4",
      @label_b : String = "Coral",
    )
    end

    def rounds(n : Int32) : Array(Exchange)
      history_a = [] of Crig::Completion::Message
      history_b = [] of Crig::Completion::Message
      last_resp_b = nil.as(String?)
      exchanges = [] of Exchange

      n.times do
        prompt_a = last_resp_b || "Plead your case!"
        resp_a = @agent_a.prompt(prompt_a).with_history(history_a).send
        resp_b = @agent_b.prompt(resp_a).with_history(history_b).send
        exchanges << Exchange.new(prompt_a, resp_a, resp_b)
        last_resp_b = resp_b
      end

      exchanges
    end
  end

  def self.build_debater(
    openai_client : Crig::Providers::OpenAI::Client,
    cohere_client : Crig::Providers::Cohere::Client,
    position_a : String = POSITION_A,
    position_b : String = POSITION_B,
  ) : Debater(Crig::Providers::OpenAI::ResponsesCompletionModel, Crig::Providers::Cohere::CompletionModel)
    Debater(Crig::Providers::OpenAI::ResponsesCompletionModel, Crig::Providers::Cohere::CompletionModel).new(
      openai_client.agent(Crig::Providers::OpenAI::GPT_4).preamble(position_a).build,
      cohere_client.agent(Crig::Providers::Cohere::COMMAND_R).preamble(position_b).build,
    )
  end

  def self.run_rounds(
    debater : Debater(A, B),
    rounds : Int32 = 4,
  ) : Array(Exchange) forall A, B
    debater.rounds(rounds)
  end
end
