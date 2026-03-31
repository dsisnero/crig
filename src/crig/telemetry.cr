module Crig
  module Telemetry
    module ProviderRequestExt(InputMessage)
      abstract def input_messages : Array(InputMessage)
      abstract def system_prompt : String?
      abstract def model_name : String
      abstract def prompt : String?

      # ameba:disable Naming/AccessorMethodName
      def get_input_messages : Array(InputMessage)
        input_messages
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_system_prompt : String?
        system_prompt
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_model_name : String
        model_name
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_prompt : String?
        prompt
      end
      # ameba:enable Naming/AccessorMethodName
    end

    module ProviderResponseExt(OutputMessage, UsageType)
      abstract def response_id : String?
      abstract def response_model_name : String?
      abstract def output_messages : Array(OutputMessage)
      abstract def text_response : String?
      abstract def usage : UsageType?

      # ameba:disable Naming/AccessorMethodName
      def get_response_id : String?
        response_id
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_response_model_name : String?
        response_model_name
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_output_messages : Array(OutputMessage)
        output_messages
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_text_response : String?
        text_response
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_usage : UsageType?
        usage
      end
      # ameba:enable Naming/AccessorMethodName
    end

    module SpanCombinator
      abstract def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
      abstract def record_response_metadata(response) : Nil
      abstract def record_model_input(messages) : Nil
      abstract def record_model_output(messages) : Nil
    end

    struct Span
      include SpanCombinator

      def self.current : Span
        new
      end

      def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
      end

      def record_response_metadata(response) : Nil
      end

      def record_model_input(messages) : Nil
      end

      def record_model_output(messages) : Nil
      end

      def record(key : String, value : String) : Nil
      end

      def record(key : String, value : Int32) : Nil
      end

      def record(key : String, value : Int64) : Nil
      end

      def record(key : String, value : Float64) : Nil
      end

      def record(key : String, value : Bool) : Nil
      end

      def record(key : String, value : Nil) : Nil
      end

      def in_scope(&)
        yield
      end

      # ameba:disable Naming/PredicateName
      def is_disabled : Bool
        true
      end
    end
  end

  alias ProviderRequestExt = Telemetry::ProviderRequestExt
  alias ProviderResponseExt = Telemetry::ProviderResponseExt
  alias SpanCombinator = Telemetry::SpanCombinator
  alias Span = Telemetry::Span
end
