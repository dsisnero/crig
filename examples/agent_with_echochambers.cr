require "../src/crig"

module Crig::Examples::AgentWithEchochambers
  PREAMBLE = <<-TEXT
             You are an assistant designed to help users interact with EchoChambers rooms.
             You can send messages, retrieve message history, and analyze various metrics.
             Follow these instructions carefully:
             1. Understand the user's request and identify which EchoChambers operation they want to perform.
             2. Select the most appropriate tool for the task.
             3. ALWAYS include both username and model in the sender information.
             4. Format your response with the tool name and inputs like this:
                Tool: send_message
                Inputs: {
                    'room_id': '<room_id>',
                    'content': '<message>',
                    'sender': {
                        'username': '<username>',
                        'model': '<model>'
                    }
                }

             Available operations:
             - Send a message to a room (requires room_id, content, and sender info)
             - Get message history from a room (requires room_id, optional limit)
             - Get room metrics (requires room_id)
             - Get agent metrics (requires room_id)
             - Get metrics history (requires room_id)

             Important: ALWAYS include both username and model in the sender information when sending messages.
             If the user specifies a username or model, use those. Otherwise, use 'Rig_Assistant' and 'gpt-4' as defaults.
             TEXT

  class EchoChamberError < Exception
  end

  struct MessageSender
    include JSON::Serializable

    getter username : String
    getter model : String

    def initialize(@username : String, @model : String)
    end
  end

  struct SendMessageArgs
    include JSON::Serializable

    getter content : String
    getter room_id : String
    getter sender : MessageSender

    def initialize(@content : String, @room_id : String, @sender : MessageSender)
    end
  end

  struct GetHistoryArgs
    include JSON::Serializable

    getter room_id : String
    getter limit : Int32?

    def initialize(@room_id : String, @limit : Int32? = nil)
    end
  end

  struct GetMetricsArgs
    include JSON::Serializable

    getter room_id : String

    def initialize(@room_id : String)
    end
  end

  struct SendMessage
    include Crig::Tool(SendMessageArgs, JSON::Any)

    getter api_key : String

    def initialize(@api_key : String)
    end

    def name : String
      "send_message"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "send_message",
        "Send a message to a specified EchoChambers room",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "content":{"type":"string","description":"The message content to send"},
            "room_id":{"type":"string","description":"The ID of the room to send the message to"},
            "sender":{
              "type":"object",
              "properties":{
                "username":{"type":"string","description":"Username of the sender"},
                "model":{"type":"string","description":"Model identifier of the sender"}
              }
            }
          }
        }))
      )
    end

    def call_typed(args : SendMessageArgs) : JSON::Any
      JSON.parse(%({
        "room_id":#{args.room_id.to_json},
        "content":#{args.content.to_json},
        "sender":{"username":#{args.sender.username.to_json},"model":#{args.sender.model.to_json}},
        "api_key_present":#{(!@api_key.empty?).to_json}
      }))
    rescue error : Exception
      raise EchoChamberError.new(error.message || error.class.name)
    end
  end

  struct GetHistory
    include Crig::Tool(GetHistoryArgs, JSON::Any)

    def name : String
      "get_history"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "get_history",
        "Retrieve message history from a specified room",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "room_id":{"type":"string","description":"The ID of the room to get history from"},
            "limit":{"type":"number","description":"Optional limit on number of messages to retrieve"}
          }
        }))
      )
    end

    def call_typed(args : GetHistoryArgs) : JSON::Any
      JSON.parse(%({"room_id":#{args.room_id.to_json},"limit":#{args.limit.to_json}}))
    rescue error : Exception
      raise EchoChamberError.new(error.message || error.class.name)
    end
  end

  struct GetRoomMetrics
    include Crig::Tool(GetMetricsArgs, JSON::Any)

    def name : String
      "get_room_metrics"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "get_room_metrics",
        "Retrieve overall metrics for a room",
        JSON.parse(%({
          "type":"object",
          "properties":{"room_id":{"type":"string","description":"The ID of the room to get metrics for"}}
        }))
      )
    end

    def call_typed(args : GetMetricsArgs) : JSON::Any
      JSON.parse(%({"room_id":#{args.room_id.to_json},"scope":"room"}))
    rescue error : Exception
      raise EchoChamberError.new(error.message || error.class.name)
    end
  end

  struct GetAgentMetrics
    include Crig::Tool(GetMetricsArgs, JSON::Any)

    def name : String
      "get_agent_metrics"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "get_agent_metrics",
        "Retrieve metrics for agents in a room",
        JSON.parse(%({
          "type":"object",
          "properties":{"room_id":{"type":"string","description":"The ID of the room to get agent metrics for"}}
        }))
      )
    end

    def call_typed(args : GetMetricsArgs) : JSON::Any
      JSON.parse(%({"room_id":#{args.room_id.to_json},"scope":"agents"}))
    rescue error : Exception
      raise EchoChamberError.new(error.message || error.class.name)
    end
  end

  struct GetMetricsHistory
    include Crig::Tool(GetMetricsArgs, JSON::Any)

    def name : String
      "get_metrics_history"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "get_metrics_history",
        "Retrieve historical metrics for a room",
        JSON.parse(%({
          "type":"object",
          "properties":{"room_id":{"type":"string","description":"The ID of the room to get metrics history for"}}
        }))
      )
    end

    def call_typed(args : GetMetricsArgs) : JSON::Any
      JSON.parse(%({"room_id":#{args.room_id.to_json},"scope":"history"}))
    rescue error : Exception
      raise EchoChamberError.new(error.message || error.class.name)
    end
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    echochambers_api_key : String,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .tool(SendMessage.new(echochambers_api_key))
      .tool(GetHistory.new)
      .tool(GetRoomMetrics.new)
      .tool(GetAgentMetrics.new)
      .tool(GetMetricsHistory.new)
      .build
  end

  def self.build_chatbot(
    agent : Crig::Agent(M),
    max_turns : Int32 = 10,
  ) forall M
    Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
      .agent(agent)
      .max_turns(max_turns)
      .build
  end
end
