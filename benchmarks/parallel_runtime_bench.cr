require "benchmark"
require "../src/crig"
require "cml"

module Crig::Benchmarks
  module ParallelRuntime
    extend self

    ITERATIONS     = 2_000
    IO_ITERATIONS  =   100
    IO_DELAY       = 1.millisecond
    CPU_SPIN_STEPS = 2_500
    FANOUT_WIDTH   =     8

    record Sample, label : String, total : Time::Span, average : Time::Span

    private def with_cml(&block : -> Nil) : Nil
      if CML.running?
        block.call
      else
        CML.run { block.call }
      end
    end

    private def cpu_work(seed : Int32) : Int32
      value = seed
      CPU_SPIN_STEPS.times do |index|
        value = (value &* 1_664_525 &+ 1_013_904_223 &+ index) ^ (value >> 13)
      end
      value
    end

    private def io_work(value : Int32) : Int32
      sleep(IO_DELAY)
      value + 1
    end

    private def serial_pair(value : Int32, &block : Int32 -> Int32) : Int32
      first = block.call(value)
      second = block.call(value + 1)
      first &+ second
    end

    private def raw_spawn_pair(value : Int32, &block : Int32 -> Int32) : Int32
      channel = Channel(Int32).new(2)
      spawn { channel.send(block.call(value)) }
      spawn { channel.send(block.call(value + 1)) }
      channel.receive &+ channel.receive
    end

    private def crig_concurrency_pair(value : Int32, &block : Int32 -> Int32) : Int32
      first = Crig::Concurrency.run { block.call(value) }
      second = Crig::Concurrency.run { block.call(value + 1) }
      first.receive.unwrap &+ second.receive.unwrap
    end

    private def cml_ivar_pair(value : Int32, &block : Int32 -> Int32) : Int32
      first = CML::IVar(Int32).new
      second = CML::IVar(Int32).new

      CML.spawn { first.i_put(block.call(value)) }
      CML.spawn { second.i_put(block.call(value + 1)) }

      first.i_get &+ second.i_get
    end

    private def cml_chan_pair(value : Int32, &block : Int32 -> Int32) : Int32
      channel = CML::Chan(Int32).new

      CML.spawn { CML.sync(channel.send_evt(block.call(value))) }
      CML.spawn { CML.sync(channel.send_evt(block.call(value + 1))) }

      CML.sync(channel.recv_evt) &+ CML.sync(channel.recv_evt)
    end

    private def serial_fanout(width : Int32, value : Int32, &block : Int32 -> Int32) : Int32
      total = 0
      width.times do |offset|
        total &+= block.call(value + offset)
      end
      total
    end

    private def raw_spawn_fanout(width : Int32, value : Int32, &block : Int32 -> Int32) : Int32
      channel = Channel(Int32).new(width)

      width.times do |offset|
        spawn { channel.send(block.call(value + offset)) }
      end

      total = 0
      width.times do
        total &+= channel.receive
      end
      total
    end

    private def crig_concurrency_fanout(width : Int32, value : Int32, &block : Int32 -> Int32) : Int32
      channels = Array(Channel(Crig::Concurrency::Result(Int32))).new(width) do |offset|
        Crig::Concurrency.run { block.call(value + offset) }
      end

      channels.sum(&.receive.unwrap)
    end

    private def cml_ivar_fanout(width : Int32, value : Int32, &block : Int32 -> Int32) : Int32
      ivars = Array(CML::IVar(Int32)).new(width) do |offset|
        ivar = CML::IVar(Int32).new
        CML.spawn { ivar.i_put(block.call(value + offset)) }
        ivar
      end

      ivars.sum(&.i_get)
    end

    private def cml_chan_fanout(width : Int32, value : Int32, &block : Int32 -> Int32) : Int32
      channel = CML::Chan(Int32).new

      width.times do |offset|
        CML.spawn { CML.sync(channel.send_evt(block.call(value + offset))) }
      end

      total = 0
      width.times do
        total &+= CML.sync(channel.recv_evt)
      end
      total
    end

    private def benchmark_fixed(
      label : String,
      iterations : Int32,
      &block : Int32 -> Int32
    ) : Sample
      checksum = 0
      started = Time.instant
      iterations.times do |index|
        checksum &+= yield index
      end
      elapsed = Time.instant - started
      average = elapsed / iterations
      puts "#{label.ljust(22)} total=#{elapsed.total_milliseconds.round(3)}ms avg=#{average.total_microseconds.round(3)}us checksum=#{checksum}"
      Sample.new(label, elapsed, average)
    end

    private def run_microbenchmarks : Nil
      puts "== Parallel Runtime Microbenchmark (CPU-light) =="
      puts "iterations=#{ITERATIONS} cpu_spin_steps=#{CPU_SPIN_STEPS}"

      with_cml do
        Benchmark.ips do |x|
          x.report("serial") do
            serial_pair(1) { |value| cpu_work(value) }
          end

          x.report("raw_spawn_channel") do
            raw_spawn_pair(1) { |value| cpu_work(value) }
          end

          x.report("crig_concurrency") do
            crig_concurrency_pair(1) { |value| cpu_work(value) }
          end

          x.report("cml_ivar") do
            cml_ivar_pair(1) { |value| cpu_work(value) }
          end

          x.report("cml_chan") do
            cml_chan_pair(1) { |value| cpu_work(value) }
          end
        end
      end
    end

    private def run_io_benchmarks : Nil
      puts
      puts "== Parallel Runtime Wall Clock Benchmark (simulated I/O) =="
      puts "iterations=#{IO_ITERATIONS} per_task_delay=#{IO_DELAY.total_milliseconds}ms"

      samples = [] of Sample
      samples << benchmark_fixed("serial", IO_ITERATIONS) do |index|
        serial_pair(index) { |value| io_work(value) }
      end
      samples << benchmark_fixed("raw_spawn_channel", IO_ITERATIONS) do |index|
        raw_spawn_pair(index) { |value| io_work(value) }
      end
      samples << benchmark_fixed("crig_concurrency", IO_ITERATIONS) do |index|
        crig_concurrency_pair(index) { |value| io_work(value) }
      end

      with_cml do
        samples << benchmark_fixed("cml_ivar", IO_ITERATIONS) do |index|
          cml_ivar_pair(index) { |value| io_work(value) }
        end
        samples << benchmark_fixed("cml_chan", IO_ITERATIONS) do |index|
          cml_chan_pair(index) { |value| io_work(value) }
        end
      end

      fastest = samples.min_by(&.total)
      puts
      puts "fastest_wall_clock=#{fastest.label} total=#{fastest.total.total_milliseconds.round(3)}ms"
    end

    private def run_fanout_benchmarks : Nil
      puts
      puts "== Fan-Out Benchmark (simulated I/O) =="
      puts "iterations=#{IO_ITERATIONS} width=#{FANOUT_WIDTH} per_task_delay=#{IO_DELAY.total_milliseconds}ms"

      samples = [] of Sample
      samples << benchmark_fixed("serial_fanout", IO_ITERATIONS) do |index|
        serial_fanout(FANOUT_WIDTH, index) { |value| io_work(value) }
      end
      samples << benchmark_fixed("raw_spawn_fanout", IO_ITERATIONS) do |index|
        raw_spawn_fanout(FANOUT_WIDTH, index) { |value| io_work(value) }
      end
      samples << benchmark_fixed("crig_concurrency_fanout", IO_ITERATIONS) do |index|
        crig_concurrency_fanout(FANOUT_WIDTH, index) { |value| io_work(value) }
      end

      with_cml do
        samples << benchmark_fixed("cml_ivar_fanout", IO_ITERATIONS) do |index|
          cml_ivar_fanout(FANOUT_WIDTH, index) { |value| io_work(value) }
        end
        samples << benchmark_fixed("cml_chan_fanout", IO_ITERATIONS) do |index|
          cml_chan_fanout(FANOUT_WIDTH, index) { |value| io_work(value) }
        end
      end

      fastest = samples.min_by(&.total)
      puts
      puts "fastest_fanout=#{fastest.label} total=#{fastest.total.total_milliseconds.round(3)}ms"
    end

    def run : Nil
      run_microbenchmarks
      run_io_benchmarks
      run_fanout_benchmarks
    end
  end
end

Crig::Benchmarks::ParallelRuntime.run
