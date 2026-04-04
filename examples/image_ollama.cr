require "../src/crig"

module Crig::Examples::ImageOllama
  IMAGE_FILE_PATH = "vendor/rig/rig/rig-core/examples/images/camponotus_flavomarginatus_ant.jpg"

  def self.run
    begin
      puts "Setting up image analysis with Ollama example:"
      puts "  - Model: llava (vision model)"
      puts "  - Task: Describe image content"
      puts "  - Image: camponotus_flavomarginatus_ant.jpg"
      puts "  - Cost: Free/local (Ollama)"
      puts ""

      # Create Ollama client
      puts "1. Setting up Ollama client..."
      ollama_client = Crig::Providers::Ollama::Client.new
      puts "   ✓ Ollama client ready"

      # Create agent with a single context prompt
      puts "2. Creating vision agent..."
      agent = ollama_client.agent("llava")
        .preamble("describe this image and make sure to include anything notable about it (include text you see in the image)")
        .temperature(0.5)
        .build
      puts "   ✓ Vision agent ready"
      puts "   - Model: llava"
      puts "   - Temperature: 0.5"

      # Read image and convert to base64
      puts "3. Loading image..."
      unless File.exists?(IMAGE_FILE_PATH)
        STDERR.puts "Error: Image file not found at #{IMAGE_FILE_PATH}"
        STDERR.puts "Please ensure the vendor submodule is initialized and the file exists."
        exit 1
      end

      image_bytes = File.read(IMAGE_FILE_PATH)
      image_base64 = Base64.strict_encode(image_bytes)
      puts "   ✓ Image loaded and encoded (size: #{image_bytes.size} bytes)"

      # Create Image for prompt
      image = Crig::Completion::Image.new(
        data: Crig::Completion::DocumentSourceKind.base64(image_base64),
        media_type: Crig::Completion::ImageMediaType::JPEG
      )

      # Prompt the agent and print the response
      puts ""
      puts "4. Analyzing image with Ollama llava model..."
      puts "=" * 60

      response = agent.prompt(image)
      puts response

      puts "=" * 60
      puts ""
      puts "Summary: This example shows image analysis with Ollama's vision model."
      puts "Key components:"
      puts "1. Base64-encoded image input"
      puts "2. Ollama llava model for vision"
      puts "3. Image description with notable features"
      puts ""
      puts "Note: This example requires Ollama with the llava model:"
      puts "  ollama pull llava"
    rescue ex : Socket::ConnectError
      STDERR.puts "Error: Cannot connect to Ollama at http://localhost:11434"
      STDERR.puts "Please ensure Ollama is running: ollama serve"
      STDERR.puts "And pull the llava model: ollama pull llava"
      exit 1
    rescue ex : File::NotFoundError
      STDERR.puts "Error: Image file not found at #{IMAGE_FILE_PATH}"
      STDERR.puts "Please ensure the vendor submodule is initialized:"
      STDERR.puts "  git submodule update --init"
      exit 1
    rescue ex : Crig::Completion::CompletionError
      STDERR.puts "Completion error: #{ex.message}"
      STDERR.puts "This could be due to:"
      STDERR.puts "1. Model not available (run: ollama pull llava)"
      STDERR.puts "2. Ollama service issues"
      exit 1
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
      exit 1
    end
  end

  # Main executable code - only run when file is executed directly
  if PROGRAM_NAME == __FILE__
    Crig::Examples::ImageOllama.run
  end
end
