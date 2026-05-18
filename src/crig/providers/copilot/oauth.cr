require "http/client"
require "json"
require "base64"

module Crig
  module Providers
    module Copilot
      # OAuth device-code authentication for GitHub Copilot.
      #
      # Flow:
      # 1. Request device code from GitHub
      # 2. Show user the verification URL and code
      # 3. Poll for access token
      # 4. Exchange GitHub token for Copilot API key
      # 5. Cache API key to disk for reuse
      module OAuth
        GITHUB_CLIENT_ID        = "Iv1.b507a08c87ecfe98"
        GITHUB_DEVICE_CODE_URL  = "https://github.com/login/device/code"
        GITHUB_ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"
        GITHUB_API_KEY_URL      = "https://api.github.com/copilot_internal/v2/token"

        DEVICE_CODE_POLL_SLEEP_SECONDS = 5_u64
        DEVICE_CODE_TIMEOUT_SECONDS    = 15 * 60_u64
        DEVICE_CODE_SLOW_DOWN_SECONDS  = 5_u64

        struct DeviceCodePrompt
          getter verification_uri : String
          getter user_code : String

          def initialize(@verification_uri : String, @user_code : String)
          end
        end

        struct DeviceCodeResponse
          include JSON::Serializable

          getter device_code : String
          getter user_code : String
          getter verification_uri : String
          getter expires_in : Int64?
          getter interval : Int64?

          def initialize(
            @device_code : String,
            @user_code : String,
            @verification_uri : String,
            @expires_in : Int64? = nil,
            @interval : Int64? = nil,
          )
          end
        end

        struct AccessTokenResponse
          include JSON::Serializable

          getter access_token : String?
          getter token_type : String?
          getter error : String?
          getter error_description : String?
          getter interval : Int64?

          def initialize(
            @access_token : String? = nil,
            @token_type : String? = nil,
            @error : String? = nil,
            @error_description : String? = nil,
            @interval : Int64? = nil,
          )
          end

          def success? : Bool
            !@access_token.nil?
          end
        end

        struct CopilotApiKeyRecord
          include JSON::Serializable

          getter token : String?
          getter expires_at : Int64?
          getter endpoints : Endpoints?

          def initialize(
            @token : String? = nil,
            @expires_at : Int64? = nil,
            @endpoints : Endpoints? = nil,
          )
          end

          struct Endpoints
            include JSON::Serializable

            getter api : String?
            getter gateway : String?

            def initialize(@api : String? = nil, @gateway : String? = nil)
            end
          end
        end

        struct CopilotApiKeyResponse
          include JSON::Serializable

          getter token : String
          getter expires_at : Int64
          getter endpoints : Endpoints?
          getter refresh_in : Int64?

          def initialize(
            @token : String,
            @expires_at : Int64,
            @endpoints : Endpoints? = nil,
            @refresh_in : Int64? = nil,
          )
          end

          struct Endpoints
            include JSON::Serializable

            getter api : String?
            getter gateway : String?

            def initialize(@api : String? = nil, @gateway : String? = nil)
            end
          end
        end

        struct AuthContext
          getter access_token : String
          getter account_id : String?

          def initialize(@access_token : String, @account_id : String? = nil)
          end
        end

        class Authenticator
          def initialize(
            @api_key_file : String? = nil,
            @on_device_code : Proc(DeviceCodePrompt, Nil)? = nil,
          )
          end

          # Get a valid Copilot API key, either from cache or via device code flow.
          def auth_context : AuthContext
            record = read_api_key_record

            # Return cached key if still valid
            if token = record.token
              unless token_expired?(record.expires_at)
                return AuthContext.new(token)
              end
            end

            # Full device code flow
            fresh = login_device_flow
            write_api_key_record(fresh)
            AuthContext.new(fresh.token)
          rescue ex : AuthError
            raise ex
          end

          private def read_api_key_record : CopilotApiKeyRecord
            return CopilotApiKeyRecord.new unless @api_key_file
            File.read(@api_key_file.not_nil!).try { |content| CopilotApiKeyRecord.from_json(content) } || CopilotApiKeyRecord.new
          rescue File::NotFoundError
            CopilotApiKeyRecord.new
          end

          private def write_api_key_record(record : CopilotApiKeyResponse) : Nil
            return unless @api_key_file
            dir = File.dirname(@api_key_file.not_nil!)
            Dir.mkdir_p(dir)
            cache = CopilotApiKeyRecord.new(
              token: record.token,
              expires_at: record.expires_at,
              endpoints: record.endpoints.try { |e| CopilotApiKeyRecord::Endpoints.new(api: e.api, gateway: e.gateway) },
            )
            File.write(@api_key_file.not_nil!, cache.to_json)
          end

          private def token_expired?(expires_at : Int64?) : Bool
            return true unless expires_at
            now = Time.utc.to_unix
            now >= expires_at
          end

          private def login_device_flow : CopilotApiKeyResponse
            # Step 1: Request device code
            code_client = HTTP::Client.new(URI.parse(GITHUB_DEVICE_CODE_URL))
            form = HTTP::Params.encode({"client_id" => GITHUB_CLIENT_ID, "scope" => "read:user"})
            response = code_client.post(
              URI.parse(GITHUB_DEVICE_CODE_URL).path,
              headers: HTTP::Headers{
                "Content-Type" => "application/x-www-form-urlencoded",
                "Accept"       => "application/json",
              },
              body: form,
            )
            raise AuthError.new("Device code request failed: #{response.status_code} #{response.body}") unless response.success?

            device = DeviceCodeResponse.from_json(response.body)

            # Step 2: Show user the code
            prompt = DeviceCodePrompt.new(device.verification_uri, device.user_code)
            if handler = @on_device_code
              handler.call(prompt)
            else
              puts "Sign in with GitHub Copilot:"
              puts "1) Visit #{prompt.verification_uri}"
              puts "2) Enter code: #{prompt.user_code}"
            end

            # Step 3: Poll for access token
            interval = device.interval || DEVICE_CODE_POLL_SLEEP_SECONDS.to_i64
            timeout_seconds = device.expires_in || DEVICE_CODE_TIMEOUT_SECONDS.to_i64
            access_token = nil
            start = Time.monotonic

            loop do
              if (Time.monotonic - start).total_seconds.to_i64 >= timeout_seconds
                raise AuthError.new("Timed out waiting for GitHub device authorization")
              end

              poll_form = HTTP::Params.encode({
                "client_id"   => GITHUB_CLIENT_ID,
                "device_code" => device.device_code,
                "grant_type"  => "urn:ietf:params:oauth:grant-type:device_code",
              })

              token_client = HTTP::Client.new(URI.parse(GITHUB_ACCESS_TOKEN_URL))
              token_response = token_client.post(
                URI.parse(GITHUB_ACCESS_TOKEN_URL).path,
                headers: HTTP::Headers{
                  "Content-Type" => "application/x-www-form-urlencoded",
                  "Accept"       => "application/json",
                },
                body: poll_form,
              )

              token_result = AccessTokenResponse.from_json(token_response.body)

              if token_result.success?
                access_token = token_result.access_token
                break
              end

              case token_result.error
              when "authorization_pending"
                sleep interval.seconds
              when "slow_down"
                interval = DEVICE_CODE_SLOW_DOWN_SECONDS.to_i64
                sleep interval.seconds
              else
                raise AuthError.new("GitHub device authorization failed: #{token_result.error} #{token_result.error_description}")
              end
            end

            raise AuthError.new("Failed to get GitHub access token") unless access_token

            # Step 4: Exchange for Copilot API key
            api_client = HTTP::Client.new(URI.parse(GITHUB_API_KEY_URL))
            api_response = api_client.get(
              URI.parse(GITHUB_API_KEY_URL).path,
              headers: HTTP::Headers{
                "Authorization" => "token #{access_token}",
                "Accept"        => "application/json",
              },
            )
            raise AuthError.new("Copilot API key request failed: #{api_response.status_code} #{api_response.body}") unless api_response.success?

            CopilotApiKeyResponse.from_json(api_response.body)
          end
        end

        class AuthError < Exception
          def initialize(message : String)
            super(message)
          end
        end
      end
    end
  end
end
