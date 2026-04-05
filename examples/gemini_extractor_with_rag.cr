require "../src/crig"

module Crig::Examples::GeminiExtractorWithRag
  APPLICANT_INFO = <<-TEXT
                   Subject: Application details / quick background

                   Hi Procurement Team,

                   My full name is John Doe. I’ve been working in and around manufacturing for about 6 years now.
                   On the technical side, I’m comfortable with Python for data cleanup/automation, SQL for reporting, and PLC/HMI troubleshooting basics.
                   I also use Excel heavily and I’m familiar with Git and basic CI setups.
                 TEXT

  struct Question
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter text : String
    getter answer_options : String

    def initialize(@id : String, @text : String, @answer_options : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@id)
      embedder.embed(@text)
      embedder.embed(@answer_options)
    end
  end

  struct Answer
    include JSON::Serializable

    getter id : String
    getter text : String

    def initialize(@id : String, @text : String)
    end
  end

  struct QuestionnaireResponses
    include JSON::Serializable

    getter responses : Array(Answer)

    def initialize(@responses : Array(Answer))
    end
  end

  PREAMBLE = <<-TEXT
             You are a questionnaire assistant provided by the procurement department to assist the user in answering the questions.
             You are provided with the questions and based on the information available, you must answer the questions with the right format.
             Use the answer ID field to map the answer to the right question ID. Answer as much as possible without inventing information.
           TEXT

  def self.questions : Array(Question)
    [
      Question.new("question_1", "Complete name", "Open question"),
      Question.new(
        "question_2",
        "Years of experience in the manufacturing industry",
        "The answers should be one of the following: Less than 1 year, 1-2 years, 2-5 years, 5-10 years, More than 10 years"
      ),
      Question.new(
        "question_3",
        "Which technical skills do you have related to the job offer?",
        "Open question. Examples are: Python, SQL, Excel, Git, CI, PLC/HMI troubleshooting (Siemens/Allen-Bradley basics)"
      ),
    ]
  end

  def self.build_index(model : M) : Crig::InMemoryVectorIndex(M, Question) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder(M, Question).new(model)
      .documents(questions)
      .build

    Crig::InMemoryVectorStore(Question).from_documents_with_id_f(embeddings, &.id).index(model)
  end

  def self.build_extractor(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_5_FLASH,
    embedding_model_name : String = Crig::Providers::Gemini::EMBEDDING_001,
  ) : Crig::Extractor(Crig::Providers::Gemini::CompletionModel, QuestionnaireResponses)
    embedding_model = client.embedding_model(embedding_model_name)
    client.extractor(QuestionnaireResponses, model)
      .preamble(PREAMBLE)
      .dynamic_context(3, build_index(embedding_model))
      .build
  end
end
