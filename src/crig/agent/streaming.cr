module Crig
  struct StreamTextDelta
    getter delta : String
    getter aggregated : String

    def initialize(@delta : String, @aggregated : String = "")
    end
  end

  struct StreamToolResult
    getter tool_name : String
    getter tool_call_id : String?
    getter result : String

    def initialize(@tool_name : String, @result : String, @tool_call_id : String? = nil)
    end
  end

  struct StreamDone
    getter response : PromptResponse

    def initialize(@response : PromptResponse)
    end
  end

  struct StreamError
    getter error : Exception

    def initialize(@error : Exception)
    end
  end

  alias DriveItem = StreamTextDelta | StreamToolResult | StreamDone
  alias StreamItem = DriveItem | StreamError
end
