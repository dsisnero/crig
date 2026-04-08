require "benchmark"
require "cml"

module Crig::Benchmarks
  module McpDispatch
    extend self

    ITERATIONS         = 1_000
    BATCH_ITERATIONS   =    25
    CONCURRENT_CALLERS =    16
    IO_DELAY           = 1.millisecond

    record Sample, label : String, total : Time::Span, average : Time::Span

    record Request,
      name : String,
      args : String,
      reply : Channel(String | Exception)

    record CmlRequest,
      name : String,
      args : String,
      reply : CML::IVar(String | Exception)

    private def with_cml(&block : -> Nil) : Nil
      if CML.running?
        block.call
      else
        CML.run { block.call }
      end
    end

    private def handle(name : String, args : String) : String
      _ = name
      _ = args
      sleep(IO_DELAY)
      "ok"
    end

    private def direct_call : String
      handle("sum", %({"x":1,"y":2}))
    end

    private def raw_actor_client : Proc(String, String, String)
      inbox = Channel(Request).new

      spawn do
        loop do
          request = inbox.receive
          begin
            request.reply.send(handle(request.name, request.args))
          rescue ex : Exception
            request.reply.send(ex)
          end
        end
      end

      ->(name : String, args : String) do
        reply = Channel(String | Exception).new(1)
        inbox.send(Request.new(name, args, reply))
        result = reply.receive
        raise result if result.is_a?(Exception)
        result.as(String)
      end
    end

    private def cml_mailbox_client : Proc(String, String, String)
      mailbox = CML::Mailbox(CmlRequest).new

      CML.spawn do
        loop do
          request = mailbox.recv
          begin
            request.reply.i_put(handle(request.name, request.args))
          rescue ex : Exception
            request.reply.i_put(ex)
          end
        end
      end

      ->(name : String, args : String) do
        reply = CML::IVar(String | Exception).new
        mailbox.send(CmlRequest.new(name, args, reply))
        result = reply.i_get
        raise result if result.is_a?(Exception)
        result.as(String)
      end
    end

    private def cml_rpc_client : Proc(String, String, String)
      rpc = CML.rpc_service(Tuple(String, String), String) do |request|
        handle(request[0], request[1])
      end

      ->(name : String, args : String) do
        rpc.call({name, args})
      end
    end

    private def benchmark_fixed(
      label : String,
      iterations : Int32,
      &block : Int32 -> String
    ) : Sample
      checksum = 0
      started = Time.instant
      iterations.times do |index|
        checksum &+= yield(index).bytesize
      end
      elapsed = Time.instant - started
      average = elapsed / iterations
      puts "#{label.ljust(22)} total=#{elapsed.total_milliseconds.round(3)}ms avg=#{average.total_microseconds.round(3)}us checksum=#{checksum}"
      Sample.new(label, elapsed, average)
    end

    private def batch_benchmark(
      label : String,
      iterations : Int32,
      client : Proc(String, String, String),
    ) : Sample
      checksum = 0
      started = Time.instant

      iterations.times do
        results = Channel(String).new(CONCURRENT_CALLERS)
        CONCURRENT_CALLERS.times do |index|
          spawn do
            results.send(client.call("sum", %({"x":#{index},"y":1})))
          end
        end

        CONCURRENT_CALLERS.times do
          checksum &+= results.receive.bytesize
        end
      end

      elapsed = Time.instant - started
      average = elapsed / iterations
      puts "#{label.ljust(22)} total=#{elapsed.total_milliseconds.round(3)}ms avg=#{average.total_microseconds.round(3)}us checksum=#{checksum}"
      Sample.new(label, elapsed, average)
    end

    private def batch_benchmark_cml(
      label : String,
      iterations : Int32,
      client : Proc(String, String, String),
    ) : Sample
      checksum = 0
      started = Time.instant

      iterations.times do
        replies = Array(CML::IVar(String)).new(CONCURRENT_CALLERS) do
          CML::IVar(String).new
        end

        CONCURRENT_CALLERS.times do |index|
          reply = replies[index]
          CML.spawn do
            reply.i_put(client.call("sum", %({"x":#{index},"y":1})))
          end
        end

        replies.each do |reply|
          checksum &+= reply.i_get.bytesize
        end
      end

      elapsed = Time.instant - started
      average = elapsed / iterations
      puts "#{label.ljust(22)} total=#{elapsed.total_milliseconds.round(3)}ms avg=#{average.total_microseconds.round(3)}us checksum=#{checksum}"
      Sample.new(label, elapsed, average)
    end

    private def run_microbenchmarks : Nil
      puts "== MCP Dispatch Benchmark (single call) =="
      puts "iterations=#{ITERATIONS} per_call_delay=#{IO_DELAY.total_milliseconds}ms"

      raw_client = raw_actor_client

      samples = [] of Sample
      samples << benchmark_fixed("direct", ITERATIONS) { |_| direct_call }
      samples << benchmark_fixed("raw_channel_actor", ITERATIONS) { |_| raw_client.call("sum", %({"x":1,"y":2})) }

      with_cml do
        mailbox_client = cml_mailbox_client
        rpc_client = cml_rpc_client
        samples << benchmark_fixed("cml_mailbox_actor", ITERATIONS) { |_| mailbox_client.call("sum", %({"x":1,"y":2})) }
        samples << benchmark_fixed("cml_rpc_actor", ITERATIONS) { |_| rpc_client.call("sum", %({"x":1,"y":2})) }
      end

      fastest = samples.min_by(&.total)
      puts
      puts "fastest_single=#{fastest.label} total=#{fastest.total.total_milliseconds.round(3)}ms"
    end

    private def run_batch_benchmarks : Nil
      puts
      puts "== MCP Dispatch Benchmark (#{CONCURRENT_CALLERS} concurrent callers) =="
      puts "iterations=#{BATCH_ITERATIONS} per_call_delay=#{IO_DELAY.total_milliseconds}ms"

      raw_client = raw_actor_client

      samples = [] of Sample
      samples << batch_benchmark("direct_spawned", BATCH_ITERATIONS, ->(name : String, args : String) { handle(name, args) })
      samples << batch_benchmark("raw_channel_actor", BATCH_ITERATIONS, raw_client)

      with_cml do
        mailbox_client = cml_mailbox_client
        samples << batch_benchmark_cml("cml_mailbox_actor", BATCH_ITERATIONS, mailbox_client)
      end

      fastest = samples.min_by(&.total)
      puts
      puts "fastest_batch=#{fastest.label} total=#{fastest.total.total_milliseconds.round(3)}ms"
    end

    def run : Nil
      run_microbenchmarks
      run_batch_benchmarks
    end
  end
end

Crig::Benchmarks::McpDispatch.run
