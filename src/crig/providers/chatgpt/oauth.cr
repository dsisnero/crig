require "http/client"
require "json"
require "base64"

module Crig
  module Providers
    module ChatGPT
      # OAuth device-code authentication for ChatGPT.
      #
      # Flow:
      # 1. Request a device code from OpenAI's auth endpoint
      # 2. Show the user the verification URL and code
      # 3. Poll for authorization (user visits URL, enters code)
      # 4. Exchange the authorization code for access/refresh tokens
      # 5. Cache tokens to disk for reuse
      # 6. Automatically refresh expired tokens
      module OAuth
        AUTH_BASE                      = "https://auth.openai.com"
        DEVICE_CODE_URL                = "https://auth.openai.com/api/accounts/deviceauth/usercode"
        DEVICE_TOKEN_URL               = "https://auth.openai.com/api/accounts/deviceauth/token"
        OAUTH_TOKEN_URL                = "https://auth.openai.com/oauth/token"
        DEVICE_VERIFY_URL              = "https://auth.openai.com/codex/device"
        CLIENT_ID                      = "app_EMoamEEZ73f0CkXaXp7hrann"
        TOKEN_EXPIRY_SKEW_SECONDS      = 60_i64
        DEVICE_CODE_TIMEOUT_SECONDS    = 15 * 60_i64
        DEVICE_CODE_POLL_SLEEP_SECONDS = 5_u64

        struct DeviceCodePrompt
          getter verification_uri : String
          getter user_code : String

          def initialize(@verification_uri : String, @user_code : String)
          end
        end

        struct AuthRecord
          include JSON::Serializable

          getter access_token : String?
          getter refresh_token : String?
          getter id_token : String?
          getter expires_at : Int64?
          getter account_id : String?

          def initialize(
            @access_token : String? = nil,
            @refresh_token : String? = nil,
            @id_token : String? = nil,
            @expires_at : Int64? = nil,
            @account_id : String? = nil,
          )
          end
        end

        struct DeviceCodeResponse
          include JSON::Serializable

          getter device_auth_id : String
          getter user_code : String
          getter interval : Int64?

          def initialize(@device_auth_id : String, @user_code : String, @interval : Int64? = nil)
          end
        end

        struct DeviceTokenResponse
          include JSON::Serializable

          getter authorization_code : String
          getter code_verifier : String

          def initialize(@authorization_code : String, @code_verifier : String)
          end
        end

        struct OAuthTokenResponse
          include JSON::Serializable

          getter access_token : String
          getter refresh_token : String?
          getter id_token : String?

          def initialize(@access_token : String, @refresh_token : String? = nil, @id_token : String? = nil)
          end
        end

        struct AuthContext
          getter access_token : String
          getter account_id : String?

          def initialize(@access_token : String, @account_id : String? = nil)
          end
        end

        class Authenticator
          getter? authorized : Bool = false

          def initialize(
            @auth_file : String? = nil,
            @on_device_code : Proc(DeviceCodePrompt, Nil)? = nil,
          )
          end

          # Get a valid auth context, either from cache or via device code flow.
          def auth_context : AuthContext
            record = read_auth_record

            # Return cached token if still valid
            if access_token = record.access_token
              unless token_expired?(record.expires_at)
                account_id = record.account_id ||
                             extract_account_id(record.id_token) ||
                             extract_account_id_from_token(access_token)
                return AuthContext.new(access_token, account_id)
              end
            end

            # Try refresh
            if refresh_token = record.refresh_token
              refreshed = refresh_tokens(refresh_token)
              if refreshed
                write_auth_record(refreshed)
                return AuthContext.new(
                  refreshed.access_token.not_nil!,
                  refreshed.account_id,
                )
              end
            end

            # Full device code flow
            fresh = login_device_flow
            write_auth_record(fresh)
            AuthContext.new(fresh.access_token.not_nil!, fresh.account_id)
          rescue ex : AuthError
            raise ex
          end

          private def read_auth_record : AuthRecord
            return AuthRecord.new unless @auth_file
            File.read(@auth_file).try { |content| AuthRecord.from_json(content) } || AuthRecord.new
          rescue File::NotFoundError
            AuthRecord.new
          end

          private def write_auth_record(record : AuthRecord) : Nil
            return unless @auth_file
            dir = File.dirname(@auth_file.not_nil!)
            Dir.mkdir_p(dir)
            File.write(@auth_file.not_nil!, record.to_json)
          end

          private def token_expired?(expires_at : Int64?) : Bool
            return true unless expires_at
            now = Time.utc.to_unix
            now >= expires_at - TOKEN_EXPIRY_SKEW_SECONDS
          end

          private def login_device_flow : AuthRecord
            # Step 1: Request device code
            client = HTTP::Client.new(URI.parse(DEVICE_CODE_URL))
            response = client.post(
              URI.parse(DEVICE_CODE_URL).path,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: %({"client_id":"#{CLIENT_ID}"}),
            )
            raise AuthError.new("Device code request failed: #{response.status_code} #{response.body}") unless response.success?

            device = DeviceCodeResponse.from_json(response.body)

            # Step 2: Show user the code
            prompt = DeviceCodePrompt.new(DEVICE_VERIFY_URL, device.user_code)
            if handler = @on_device_code
              handler.call(prompt)
            else
              puts "Sign in with ChatGPT:"
              puts "1) Visit #{prompt.verification_uri}"
              puts "2) Enter code: #{prompt.user_code}"
              puts "Do not share this device code."
            end

            # Step 3: Poll for authorization
            interval = device.interval || DEVICE_CODE_POLL_SLEEP_SECONDS.to_i64
            authorization_code = nil
            code_verifier = nil
            start = Time.monotonic

            loop do
              if (Time.monotonic - start).total_seconds.to_i64 >= DEVICE_CODE_TIMEOUT_SECONDS
                raise AuthError.new("Timed out waiting for ChatGPT device authorization")
              end

              poll_response = client.post(
                URI.parse(DEVICE_TOKEN_URL).path,
                headers: HTTP::Headers{"Content-Type" => "application/json"},
                body: %({"device_auth_id":"#{device.device_auth_id}","user_code":"#{device.user_code}"}),
              )

              if poll_response.success?
                token = DeviceTokenResponse.from_json(poll_response.body)
                authorization_code = token.authorization_code
                code_verifier = token.code_verifier
                break
              end

              if poll_response.status_code == 403 || poll_response.status_code == 404
                sleep interval.seconds
                next
              end

              raise AuthError.new("ChatGPT device authorization failed: #{poll_response.status_code} #{poll_response.body}")
            end

            raise AuthError.new("Failed to get authorization code") unless authorization_code

            # Step 4: Exchange for tokens
            token_client = HTTP::Client.new(URI.parse(OAUTH_TOKEN_URL))
            redirect_uri = "#{AUTH_BASE}/deviceauth/callback"
            form_body = HTTP::Params.encode({
              "grant_type"    => "authorization_code",
              "code"          => authorization_code,
              "redirect_uri"  => redirect_uri,
              "client_id"     => CLIENT_ID,
              "code_verifier" => code_verifier || "",
            })

            token_response = token_client.post(
              URI.parse(OAUTH_TOKEN_URL).path,
              headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"},
              body: form_body,
            )
            raise AuthError.new("Token exchange failed: #{token_response.status_code} #{token_response.body}") unless token_response.success?

            tokens = OAuthTokenResponse.from_json(token_response.body)
            build_auth_record(tokens, nil)
          end

          private def refresh_tokens(refresh_token : String) : AuthRecord?
            client = HTTP::Client.new(URI.parse(OAUTH_TOKEN_URL))
            form_body = HTTP::Params.encode({
              "client_id"     => CLIENT_ID,
              "grant_type"    => "refresh_token",
              "refresh_token" => refresh_token,
              "scope"         => "openid profile email",
            })

            response = client.post(
              URI.parse(OAUTH_TOKEN_URL).path,
              headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"},
              body: form_body,
            )

            return nil unless response.success?

            tokens = OAuthTokenResponse.from_json(response.body)
            build_auth_record(tokens, refresh_token)
          rescue
            nil
          end

          private def build_auth_record(
            tokens : OAuthTokenResponse,
            previous_refresh_token : String?,
          ) : AuthRecord
            expires_at = extract_expiration_timestamp(tokens.access_token)
            account_id = extract_account_id(tokens.id_token) ||
                         extract_account_id_from_token(tokens.access_token)

            AuthRecord.new(
              access_token: tokens.access_token,
              refresh_token: tokens.refresh_token || previous_refresh_token,
              id_token: tokens.id_token,
              expires_at: expires_at,
              account_id: account_id,
            )
          end

          private def extract_expiration_timestamp(token : String) : Int64?
            parts = token.split('.')
            return nil if parts.size < 2

            payload = parts[1]
            decoded = Base64.decode_string(payload)
            claims = JSON.parse(decoded)
            claims["exp"]?.try(&.as_i64)
          rescue
            nil
          end

          private def extract_account_id(id_token : String?) : String?
            return nil unless id_token
            parts = id_token.split('.')
            return nil if parts.size < 2

            payload = parts[1]
            decoded = Base64.decode_string(payload)
            claims = JSON.parse(decoded)
            auth = claims["https://api.openai.com/auth"]?.try(&.as_h?)
            auth.try(&.["chatgpt_account_id"]?.try(&.as_s?))
          rescue
            nil
          end

          private def extract_account_id_from_token(token : String) : String?
            extract_account_id(token)
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
