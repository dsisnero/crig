require "./internal/buffered"
# openai_chat_completions_compatible is deferred — each provider currently
# has its own streaming implementation; this module will be ported when
# providers are refactored to share the common streaming state machine.
