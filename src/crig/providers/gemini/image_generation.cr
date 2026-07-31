module Crig
  module Providers
    module Gemini
      # Gemini image generation model.
      struct ImageGenerationModel
        include Crig::ImageGenerationModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String = GEMINI_2_5_FLASH_IMAGE)
        end

        def image_generation(request : Crig::ImageGenerationRequest)
          body = build_request_body(request)
          response = @client.post_json(generate_content_path, body)
          text = response.body

          if response.status_code >= 400
            raise Crig::ImageGenerationError.from_http_response(response.status_code, text)
          end

          parsed = JSON.parse(text)
          if parsed["error"]?
            raise Crig::ImageGenerationError.from_http_response(response.status_code, text)
          end

          gen_response = GenerateContentResponse.from_json(text)
          image_bytes = extract_first_image(gen_response)
          Crig::ImageGenerationResponse(Bytes).new(image_bytes, Bytes.new(0))
        end

        def image_generation_request : Crig::ImageGenerationRequestBuilder
          Crig::ImageGenerationRequestBuilder.new(self)
        end

        private def generate_content_path : String
          "/v1beta/models/#{@model}:generateContent"
        end

        private def build_request_body(request : Crig::ImageGenerationRequest) : String
          aspect = compute_aspect_ratio(request.width, request.height)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "contents" do
                json.array do
                  json.object do
                    json.field "role", "user"
                    json.field "parts" do
                      json.array do
                        json.object do
                          json.field "text", request.prompt
                        end
                      end
                    end
                  end
                end
              end
              json.field "generationConfig" do
                json.object do
                  json.field "responseModalities", ["IMAGE"]
                  if aspect
                    json.field "imageConfig" do
                      json.object do
                        json.field "aspectRatio", aspect
                      end
                    end
                  end
                end
              end
            end
          end

          if additional_params = request.additional_params
            JSON.parse(merge_json_deep(payload, additional_params).to_json)
          else
            payload
          end.to_json
        end

        private def merge_json_deep(target : JSON::Any, source : JSON::Any) : JSON::Any
          target_hash = target.as_h?
          source_hash = source.as_h?
          return source unless target_hash && source_hash

          merged = target_hash.dup
          source_hash.each do |key, value|
            merged[key] = if existing = merged[key]?
                            merge_json_deep(existing, value)
                          else
                            value
                          end
          end
          JSON.parse(merged.to_json)
        end

        def compute_aspect_ratio(width : Int32, height : Int32) : String?
          if width == 0 || height == 0
            nil
          elsif width == height
            "1:1"
          elsif width * 3 == height * 4
            "3:4"
          elsif width * 4 == height * 3
            "4:3"
          elsif width * 9 == height * 16
            "16:9"
          elsif width * 16 == height * 9
            "9:16"
          end
        end

        private def extract_first_image(response : GenerateContentResponse) : Bytes
          response.candidates.each do |candidate|
            content = candidate.content
            next unless content

            content.parts.each do |part|
              next if part.thought == true

              if inline = part.part.inline_data
                next unless inline.mime_type.starts_with?("image/")
                return Base64.decode(inline.data)
              end
            end
          end

          raise Crig::ImageGenerationError.response_error("Gemini image generation response did not include image data")
        end
      end
    end
  end
end
