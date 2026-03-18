module Crig
  module WasmCompatSend
  end

  module WasmCompatSendStream
  end

  module WasmCompatSync
  end

  struct WasmBoxedFuture(T)
    getter callback : Proc(T)

    def initialize(&@callback : -> T)
    end

    def call : T
      @callback.call
    end
  end
end
