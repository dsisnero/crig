require "json"

module Crig
  module Tool
    enum ToolErrorKind
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

      def default_model_feedback : String
        case self
        in InvalidArgs      then "tool arguments were invalid"
        in Timeout          then "tool execution timed out"
        in Cancelled        then "tool execution was cancelled"
        in NotFound         then "the requested tool or resource was not found"
        in PermissionDenied then "the tool denied the request"
        in RateLimited      then "the tool was rate limited; try again later"
        in Provider         then "the tool provider failed"
        in Network          then "the tool could not reach its upstream service"
        in Other            then "the tool failed"
        end
      end

      def to_s(io : IO) : Nil
        io << as_str
      end
    end

    struct ToolExecutionError
      getter kind : ToolErrorKind
      getter message : String
      getter retryable : Bool?
      getter code : String?
      getter http_status : Int32?
      getter? refusal : Bool
      getter model_output : ToolOutput?
      getter source : Exception?

      def initialize(
        @kind : ToolErrorKind,
        @message : String,
        @retryable : Bool? = nil,
        @code : String? = nil,
        @http_status : Int32? = nil,
        @refusal : Bool = false,
        @model_output : ToolOutput? = nil,
        @source : Exception? = nil,
      )
      end

      private def self.with_defaults(kind : ToolErrorKind, message : String, refusal : Bool = false) : self
        model_out = ToolOutput.text(message)
        new(kind, message, retryable: kind.default_retryable, refusal: refusal, model_output: model_out)
      end

      def self.invalid_args(message : String) : self
        with_defaults(ToolErrorKind::InvalidArgs, message)
      end

      def self.timeout(message : String) : self
        with_defaults(ToolErrorKind::Timeout, message)
      end

      def self.cancelled(message : String) : self
        with_defaults(ToolErrorKind::Cancelled, message)
      end

      def self.not_found(message : String) : self
        with_defaults(ToolErrorKind::NotFound, message)
      end

      def self.permission_denied(message : String) : self
        with_defaults(ToolErrorKind::PermissionDenied, message)
      end

      def self.refused(message : String) : self
        with_defaults(ToolErrorKind::PermissionDenied, message, refusal: true)
      end

      def self.rate_limited(message : String) : self
        with_defaults(ToolErrorKind::RateLimited, message)
      end

      def self.provider(message : String) : self
        with_defaults(ToolErrorKind::Provider, message)
      end

      def self.network(message : String) : self
        with_defaults(ToolErrorKind::Network, message)
      end

      def self.other(message : String) : self
        with_defaults(ToolErrorKind::Other, message)
      end

      def self.from_error(error : self) : self
        error
      end

      def self.from_error(error : Exception) : self
        other(error.message || "unknown error").redact_model_feedback.with_source(error)
      end

      def model_feedback : String?
        @model_output.try(&.as_text)
      end

      def with_model_feedback(feedback : String) : self
        ToolExecutionError.new(@kind, @message, retryable: @retryable, code: @code, http_status: @http_status, refusal: @refusal, model_output: ToolOutput.text(feedback), source: @source)
      end

      def with_model_output(output : ToolOutput) : self
        ToolExecutionError.new(@kind, @message, retryable: @retryable, code: @code, http_status: @http_status, refusal: @refusal, model_output: output, source: @source)
      end

      def redact_model_feedback : self
        with_model_feedback(@kind.default_model_feedback)
      end

      def with_retryable(retryable : Bool) : self
        ToolExecutionError.new(@kind, @message, retryable: retryable, code: @code, http_status: @http_status, refusal: @refusal, model_output: @model_output, source: @source)
      end

      def with_code(code : String) : self
        ToolExecutionError.new(@kind, @message, retryable: @retryable, code: code, http_status: @http_status, refusal: @refusal, model_output: @model_output, source: @source)
      end

      def with_http_status(status : Int32) : self
        ToolExecutionError.new(@kind, @message, retryable: @retryable, code: @code, http_status: status, refusal: @refusal, model_output: @model_output, source: @source)
      end

      def with_source(source : Exception) : self
        ToolExecutionError.new(@kind, @message, retryable: @retryable, code: @code, http_status: @http_status, refusal: @refusal, model_output: @model_output, source: source)
      end

      def to_s(io : IO) : Nil
        io << @kind.as_str << ": " << @message
      end
    end

    struct ToolResult
      getter output : ToolOutput
      getter disposition : ToolDisposition
      @error : ToolExecutionError?

      def initialize(@disposition : ToolDisposition, @output : ToolOutput, @error : ToolExecutionError? = nil)
      end

      def self.success(output : ToolOutput) : self
        new(ToolDisposition::Success, output)
      end

      def self.failed(err : ToolExecutionError) : self
        if err.refusal?
          new(ToolDisposition::Refused, err.model_output || ToolOutput.text(err.message), err)
        else
          new(ToolDisposition::Error, err.model_output || ToolOutput.text(err.message), err)
        end
      end

      def self.skipped(reason : String) : self
        new(ToolDisposition::Skipped, ToolOutput.text(reason))
      end

      def success? : Bool
        @disposition.success?
      end

      def error? : Bool
        @disposition.error?
      end

      def error : ToolExecutionError?
        return unless @disposition.error?
        @error
      end

      def skipped? : Bool
        @disposition.skipped?
      end

      def refused? : Bool
        @disposition.refused?
      end

      def refusal : ToolExecutionError?
        return unless @disposition.refused?
        @error
      end

      # ameba:disable Naming/PredicateName
      def is_error_kind(kind : ToolErrorKind) : Bool
        @disposition.error? && @error.try(&.kind) == kind
      end

      def status_name : String
        case @disposition
        in ToolDisposition::Success then "success"
        in ToolDisposition::Error   then "error"
        in ToolDisposition::Refused then "denied"
        in ToolDisposition::Skipped then "skipped"
        end
      end
    end

    enum ToolDisposition
      Success
      Error
      Refused
      Skipped
    end
  end
end
