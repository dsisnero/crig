module Crig
  enum OutputMode
    Auto
    Tool
    Native
    Prompted

    def self.default : OutputMode
      OutputMode::Auto
    end
  end

  struct PendingToolCall
    include JSON::Serializable

    getter tool_call : Completion::ToolCall
    getter preresolved_result : Completion::UserContent?
    getter internal_call_id : String?

    def initialize(
      @tool_call : Completion::ToolCall,
      @preresolved_result : Completion::UserContent? = nil,
      @internal_call_id : String? = nil,
    )
    end
  end

  struct ModelTurn
    include JSON::Serializable

    getter message_id : String?
    getter choice : OneOrMany(Completion::AssistantContent)
    getter usage : Completion::Usage
    getter executable_tool_names : Array(String)
    getter allowed_tool_names : Array(String)

    def initialize(
      @message_id : String? = nil,
      @choice : OneOrMany(Completion::AssistantContent) = OneOrMany(Completion::AssistantContent).none,
      @usage : Completion::Usage = Completion::Usage.new,
      @executable_tool_names : Array(String) = [] of String,
      @allowed_tool_names : Array(String) = [] of String,
    )
    end
  end

  enum AgentRunStep
    CallModel
    CallTools
    Done
  end

  enum ModelTurnOutcome
    Continue
    NeedsResolution
    TurnRetried
  end

  # Sans-IO agent loop state machine.
  # This is the serializable core that AgentRunner drives.
  struct AgentRun
    include JSON::Serializable

    property max_turns : Int32 = 0
    property max_invalid_tool_call_retries : Int32 = 0
    property tool_choice : Completion::ToolChoice?
    property output_tool_name : String?
    @[JSON::Field(ignore)]
    property output_schema : JSON::Any?
    property max_output_retries : Int32 = 0
    property output_retries : Int32 = 0
    property chat_history : Array(Completion::Message)?
    property new_messages : Array(Completion::Message) = [] of Completion::Message
    property current_turn : Int32 = 0
    property usage : Completion::Usage = Completion::Usage.new
    property completion_calls : Array(CompletionCall) = [] of CompletionCall

    def self.new(prompt : Completion::Message) : self
      run = allocate
      run.initialize(prompt)
      run
    end

    protected def initialize(prompt : Completion::Message)
      @new_messages = [prompt]
    end

    def with_history(history : Array(Completion::Message)) : self
      @chat_history = history
      self
    end

    def max_turns(value : Int32) : self
      @max_turns = value
      self
    end

    def max_invalid_tool_call_retries(retries : Int32) : self
      @max_invalid_tool_call_retries = retries
      self
    end

    def with_tool_choice(tool_choice : Completion::ToolChoice) : self
      @tool_choice = tool_choice
      self
    end

    def with_output_tool_name(name : String) : self
      @output_tool_name = name
      self
    end

    def with_output_validation(schema : JSON::Any?, max_retries : Int32) : self
      @output_schema = schema
      @max_output_retries = max_retries
      self
    end

    def turn : Int32
      @current_turn
    end

    def messages : Array(Completion::Message)
      @new_messages
    end

    def is_done? : Bool
      false # Full state machine not yet ported
    end
  end
end
