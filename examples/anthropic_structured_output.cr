require "../src/crig"

module Crig::Examples::AnthropicStructuredOutput
  PREAMBLE = "You are a literary critic. Provide thoughtful and concise book reviews."
  PROMPT   = "Write a review of '1984' by George Orwell."

  struct SimilarBook
    include JSON::Serializable

    getter title : String
    getter author : String

    def initialize(@title : String, @author : String)
    end
  end

  struct Recommendation
    include JSON::Serializable

    getter target_audience : String
    getter similar_books : Array(SimilarBook)

    def initialize(@target_audience : String, @similar_books : Array(SimilarBook))
    end
  end

  struct Theme
    include JSON::Serializable

    getter name : String
    getter description : String

    def initialize(@name : String, @description : String)
    end
  end

  struct Author
    include JSON::Serializable

    getter name : String
    getter nationality : String
    getter other_works : Array(String)

    def initialize(@name : String, @nationality : String, @other_works : Array(String))
    end
  end

  struct BookReview
    include JSON::Serializable

    getter title : String
    getter author : Author
    getter rating : Int32
    getter summary : String
    getter themes : Array(Theme)
    getter recommendation : Recommendation

    def initialize(
      @title : String,
      @author : Author,
      @rating : Int32,
      @summary : String,
      @themes : Array(Theme),
      @recommendation : Recommendation,
    )
    end
  end

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_4_SONNET,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .output_schema(BookReview)
      .build
  end

  def self.parse_review(response : String) : BookReview
    BookReview.from_json(response)
  end
end
