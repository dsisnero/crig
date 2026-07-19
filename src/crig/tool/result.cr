require "json"

module Crig
  module Tool
    enum ToolFailureKind
      InvalidArgs
      Timeout
      Cancelled
      NotFound
      PermissionDenied
      RateLimited
      Provider
      Network
      Other

      def as_str : String
        case self
        in InvalidArgs      then "invalid_args"
        in Timeout          then "timeout"
        in Cancelled        then "cancelled"
        in NotFound         then "not_found"
        in PermissionDenied then "permission_denied"
        in RateLimited      then "rate_limited"
        in Provider         then "provider"
        in Network          then "network"
        in Other            then "other"
        end
      end

      def default_retryable : Bool?
        case self
        in Timeout, RateLimited, Network                      then true
        in InvalidArgs, NotFound, PermissionDenied, Cancelled then false
        in Provider, Other                                    then nil
        end
      end

      def to_s(io : IO) : Nil
        io << as_str
      end
    end

    struct ToolFailure
      getter kind : ToolFailureKind
      getter message : String
      property retryable : Bool?
      property code : String?
      property http_status : Int32?

      def initialize(@kind : ToolFailureKind, message : String)
        @message = message
        @retryable = nil
        @code = nil
        @http_status = nil
      end

      protected def self.of_kind(kind : ToolFailureKind, message : String) : self
        failure = new(kind, message)
        failure.retryable = kind.default_retryable
        failure
      end

      def self.invalid_args(message : String) : self
        of_kind(ToolFailureKind::InvalidArgs, message)
      end

      def self.timeout(message : String) : self
        of_kind(ToolFailureKind::Timeout, message)
      end

      def self.cancelled(message : String) : self
        of_kind(ToolFailureKind::Cancelled, message)
      end

      def self.not_found(message : String) : self
        of_kind(ToolFailureKind::NotFound, message)
      end

      def self.permission_denied(message : String) : self
        of_kind(ToolFailureKind::PermissionDenied, message)
      end

      def self.rate_limited(message : String) : self
        of_kind(ToolFailureKind::RateLimited, message)
      end

      def self.provider(message : String) : self
        of_kind(ToolFailureKind::Provider, message)
      end

      def self.network(message : String) : self
        of_kind(ToolFailureKind::Network, message)
      end

      def self.other(message : String) : self
        of_kind(ToolFailureKind::Other, message)
      end

      def with_retryable(retryable : Bool) : self
        @retryable = retryable
        self
      end

      def with_code(code : String) : self
        @code = code
        self
      end

      def with_http_status(status : Int32) : self
        @http_status = status
        self
      end

      def to_s(io : IO) : Nil
        io << @kind.as_str << ": " << @message
      end
    end

    struct ToolOutcome
      enum Kind
        Success
        Error
        Skipped
        Denied
      end

      getter kind : Kind
      getter failure : ToolFailure?

      private def initialize(@kind : Kind, @failure : ToolFailure? = nil)
      end

      def self.success : self
        new(Kind::Success)
      end

      def self.error(failure : ToolFailure) : self
        new(Kind::Error, failure: failure)
      end

      def self.skipped : self
        new(Kind::Skipped)
      end

      def self.denied : self
        new(Kind::Denied)
      end

      def as_str : String
        case @kind
        in Kind::Success then "success"
        in Kind::Error   then "error"
        in Kind::Skipped then "skipped"
        in Kind::Denied  then "denied"
        end
      end

      def success? : Bool
        @kind.success?
      end

      def error? : Bool
        @kind.error?
      end

      def skip? : Bool
        @kind.skipped?
      end

      def denied? : Bool
        @kind.denied?
      end

      def error_kind : ToolFailureKind?
        @failure.try(&.kind)
      end

      def error_kind?(kind : ToolFailureKind) : Bool
        error_kind == kind
      end

      def ==(other : ToolOutcome) : Bool
        @kind == other.kind && @failure == other.failure
      end
    end

    struct ToolReturnOutcome
      enum Kind
        Success
        Error
        Denied
      end

      getter kind : Kind
      getter failure : ToolFailure?

      private def initialize(@kind : Kind, @failure : ToolFailure? = nil)
      end

      def self.success : self
        new(Kind::Success)
      end

      def self.error(failure : ToolFailure) : self
        new(Kind::Error, failure: failure)
      end

      def self.denied : self
        new(Kind::Denied)
      end

      def as_str : String
        case @kind
        in Kind::Success then "success"
        in Kind::Error   then "error"
        in Kind::Denied  then "denied"
        end
      end

      def into_tool_outcome : ToolOutcome
        case @kind
        in Kind::Success then ToolOutcome.success
        in Kind::Error   then ToolOutcome.error(@failure || raise("Bug: Error kind without failure"))
        in Kind::Denied  then ToolOutcome.denied
        end
      end
    end

    struct ToolExecutionResult
      getter model_output : String
      getter outcome : ToolOutcome
      getter extensions : ToolResultExtensions

      def initialize(@model_output : String, @outcome : ToolOutcome, @extensions : ToolResultExtensions = ToolResultExtensions.new)
      end

      def self.success(model_output : String) : self
        new(model_output, ToolOutcome.success)
      end

      def self.failed(model_output : String, failure : ToolFailure) : self
        new(model_output, ToolOutcome.error(failure))
      end

      def self.denied(model_output : String) : self
        new(model_output, ToolOutcome.denied)
      end

      def with_extensions(extensions : ToolResultExtensions) : self
        @extensions = extensions
        self
      end

      def with_extension(extension) : self
        extensions.insert(extension)
        self
      end
    end

    struct ToolReturn(T)
      getter output : T
      getter outcome : ToolReturnOutcome
      getter extensions : ToolResultExtensions

      def self.success(output : U) : ToolReturn(U) forall U
        ToolReturn(U).new(output, ToolReturnOutcome.success)
      end

      def self.failed(output : T, failure : ToolFailure) : ToolReturn(T)
        ToolReturn(T).new(output, ToolReturnOutcome.error(failure))
      end

      def self.denied(output : T) : ToolReturn(T)
        ToolReturn(T).new(output, ToolReturnOutcome.denied)
      end

      protected def initialize(@output : T, @outcome : ToolReturnOutcome, @extensions : ToolResultExtensions = ToolResultExtensions.new)
      end

      def with_outcome(outcome : ToolReturnOutcome) : self
        @outcome = outcome
        self
      end

      def with_extensions(extensions : ToolResultExtensions) : self
        @extensions = extensions
        self
      end

      def with_extension(extension) : self
        extensions.insert(extension)
        self
      end

      def into_execution_result : ToolExecutionResult
        model_output = Crig::Tool.serialize_output(@output)
        ToolExecutionResult.new(model_output, @outcome.into_tool_outcome, @extensions)
      rescue ex : JSON::SerializableError
        outcome = case @outcome.kind
                  in ToolReturnOutcome::Kind::Success
                    ToolOutcome.error(ToolFailure.other(ex.message || "serialization error"))
                  in ToolReturnOutcome::Kind::Error, ToolReturnOutcome::Kind::Denied
                    @outcome.into_tool_outcome
                  end
        ToolExecutionResult.new("failed to serialize tool output: #{ex.message}", outcome, @extensions)
      end
    end

    def self.serialize_output(output) : String
      case output
      when String then output
      else             output.to_json
      end
    end
  end
end
