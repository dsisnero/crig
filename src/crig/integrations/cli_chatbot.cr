module Crig
  module Integrations
    struct NoImplProvided
    end

    module CliChat
      abstract def request(prompt : String, history : Array(Crig::Completion::Message), output : IO) : String

      def show_usage? : Bool
        false
      end

      def usage : Crig::Completion::Usage?
        nil
      end
    end

    struct ChatImpl(T)
      include CliChat

      getter chat : T

      def initialize(@chat : T)
      end

      def request(prompt : String, history : Array(Crig::Completion::Message), output : IO) : String
        response = @chat.chat(prompt, history)
        output.puts(response)
        response
      end
    end

    struct AgentImpl(M)
      include CliChat

      getter agent : Crig::Agent(M)
      getter max_turns : Int32
      getter? show_usage : Bool
      getter usage : Crig::Completion::Usage?

      def initialize(
        @agent : Crig::Agent(M),
        @max_turns : Int32 = 1,
        @show_usage : Bool = false,
        @usage : Crig::Completion::Usage? = nil,
      )
      end

      def request(prompt : String, history : Array(Crig::Completion::Message), output : IO) : String
        result = @agent.stream_prompt(prompt).with_history(history).multi_turn(@max_turns).send_items
        response = String.build do |io|
          result.items.each do |item|
            next unless item.kind.stream_assistant_item?
            assistant_item = item.assistant_item
            next unless assistant_item && assistant_item.kind.text?
            text = assistant_item.text.try(&.text) || ""
            output.print(text)
            io << text
          end
        end

        if final = result.items.last?.try(&.final_response)
          @usage = final.usage
        end

        response
      end
    end

    struct ChatBotBuilder(T)
      getter impl : T

      def initialize(@impl : T)
      end

      def self.new : ChatBotBuilder(NoImplProvided)
        ChatBotBuilder(NoImplProvided).new(NoImplProvided.new)
      end

      def agent(agent : Crig::Agent(M)) : ChatBotBuilder(AgentImpl(M)) forall M
        ChatBotBuilder(AgentImpl(M)).new(AgentImpl(M).new(agent))
      end

      def chat(chatbot : TChat) : ChatBotBuilder(ChatImpl(TChat)) forall TChat
        ChatBotBuilder(ChatImpl(TChat)).new(ChatImpl(TChat).new(chatbot))
      end

      def max_turns(max_turns : Int) : self
        {% if T.stringify.starts_with?("Crig::Integrations::AgentImpl(") %}
          self.class.new(
            T.new(
              @impl.agent,
              max_turns.to_i32,
              @impl.show_usage?,
              @impl.usage,
            )
          )
        {% else %}
          raise "max_turns is only available for agent-backed chatbots"
        {% end %}
      end

      def show_usage : self
        {% if T.stringify.starts_with?("Crig::Integrations::AgentImpl(") %}
          self.class.new(
            T.new(
              @impl.agent,
              @impl.max_turns,
              true,
              @impl.usage,
            )
          )
        {% else %}
          raise "show_usage is only available for agent-backed chatbots"
        {% end %}
      end

      def build : ChatBot(T)
        ChatBot(T).new(@impl)
      end
    end

    struct ChatBot(T)
      getter impl : T

      def initialize(@impl : T)
      end
    end

    struct ChatBot(T)
      def run(input : IO = STDIN, output : IO = STDOUT) : Nil
        history = [] of Crig::Completion::Message

        loop do
          output.print("> ")
          output.flush

          raw_input = input.gets
          break unless raw_input

          prompt = raw_input.strip
          break if prompt == "exit"

          output.puts
          output.puts("========================== Response ============================")

          response = @impl.request(prompt, history.dup, output)
          history << Crig::Completion::Message.user(prompt)
          history << Crig::Completion::Message.assistant(response)

          output.puts
          output.puts("================================================================")
          output.puts

          if @impl.show_usage?
            usage = @impl.usage || Crig::Completion::Usage.new
            output.puts("Input #{usage.input_tokens} tokens")
            output.puts("Output #{usage.output_tokens} tokens")
          end
        end
      end
    end
  end
end
