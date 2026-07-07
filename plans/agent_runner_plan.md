# Porting AgentRunner: Rust async → Crystal concurrency

## Architecture Overview

The upstream v0.39.0 separates agent execution into two layers:

```
┌──────────────────────────────────────────────┐
│  PromptRequest / StreamingPromptRequest      │  ← public API
│  (thin builder wrappers)                     │
├──────────────────────────────────────────────┤
│  AgentRunner<M>                              │  ← IO + hooks + concurrency
│  - model calls, tool execution, hook dispatch│
│  - tool_concurrency, memory, streaming       │
├──────────────────────────────────────────────┤
│  AgentRun                                    │  ← pure state machine (sans-IO)
│  - next_step, model_response, tool_results   │
│  - serializable, no async, no IO            │
└──────────────────────────────────────────────┘
```

## Phase 1: AgentRun state machine (pure logic, no concurrency)

**Source**: `agent/run/mod.rs` (2300 lines)

This is a pure state machine. No async, no IO, no hooks. The driver calls
`next_step()` → acts on the returned `AgentRunStep` → feeds results back.

**Crystal approach**: Direct port. Struct with methods. No concurrency needed.

Key methods to port:
- `AgentRun.new(prompt)` — initialize with prompt
- `AgentRun#next_step` → `AgentRunStep::CallModel | CallTools | Done`
- `AgentRun#model_response(turn)` → `ModelTurnOutcome`
- `AgentRun#resolve_invalid_tool_call(action)` — hook resolution
- `AgentRun#tool_results(results)` — feed tool results
- `AgentRun#record_streamed_completion_call(...)` — streaming
- Helper: `missing_required_output_fields`, `text_satisfies_output_schema`,
  `can_reprompt_for_output`

**Tests**: Port the blocking agent tests from `agent/run/mod.rs` (text_only_run,
tool_roundtrip, max_turns_exhaustion, output_tool_call_finalizes_run, etc.).

## Phase 2: AgentRunner — sequential execution

**Source**: `agent/runner.rs` (6101 lines) + `agent/prompt_request/streaming.rs` drive loop

The `AgentRunner` wraps `AgentRun` with IO concerns. For Phase 2, implement
sequential execution (tool_concurrency = 1, no streaming).

### 2a: drive_agent loop (sequential)

Rust pseudocode:
```rust
loop {
    match run.next_step()? {
        CallModel { prompt, history, turn } => {
            dispatch CompletionCall hook → patch
            build prepared request (with patch applied)
            model.completion(request).await → response
            dispatch CompletionResponse hook
            run.model_response(ModelTurn { choice, usage, ... })
            handle ModelTurnOutcome (Continue / NeedsResolution / TurnRetried)
        }
        CallTools { calls } => {
            for call in calls {
                dispatch ToolCall hook → args rewrite
                tool.call_structured(args).await → ToolExecutionResult
                dispatch ToolResult hook → result rewrite
                collect result
            }
            run.tool_results(results)
        }
        Done(response) => break
    }
}
```

**Crystal approach**: Direct sequential loop. No channels needed for the
blocking path.

```crystal
class AgentRunner(M)
  def run(prompt : Message) : PromptResponse
    ctx = HookContext.new(is_streaming: false, agent_name: @agent_name)
    run = AgentRun.new(prompt)
      .max_turns(@max_turns)
      .with_tool_choice(@tool_choice)
      # ...

    loop do
      step = run.next_step
      case step
      in AgentRunStep::CallModel
        # 1. Dispatch CompletionCall hook
        patch = resolve_completion_call_hook(ctx, step.prompt, step.history, step.turn)
        # 2. Build prepared request with patch
        prepared = build_prepared_request(step, patch)
        # 3. Call model (fiber yields on IO)
        response = @model.completion(prepared.builder.build)
        # 4. Dispatch CompletionResponse hook
        dispatch_hook(ctx, StepEvent::CompletionResponse { ... })
        # 5. Feed to state machine
        outcome = run.model_response(ModelTurn.new(choice: response.choice, ...))
        # 6. Handle outcome
        case outcome
        in ModelTurnOutcome::Continue       then next
        in ModelTurnOutcome::NeedsResolution then resolve_invalid_tool_call(...)
        in ModelTurnOutcome::TurnRetried     then next
        end
      in AgentRunStep::CallTools
        results = calls.map do |call|
          # Hook dispatch: ToolCall → rewrite args
          effective_args = dispatch_tool_call_hook(ctx, call)
          # Execute tool
          result = @tool_server.call_tool_structured(call.name, effective_args, @tool_extensions)
          # Hook dispatch: ToolResult → rewrite result
          effective_result = dispatch_tool_result_hook(ctx, call, result)
          effective_result
        end
        run.tool_results(results)
      in AgentRunStep::Done
        return step.response
      end
    end
  end
end
```

## Phase 3: Concurrent tool execution

**Source**: `agent/prompt_request/streaming.rs` lines 828-940

Uses **Errgroup pattern** (cancel on first error) + **bounded parallelism**.

### Crystal pattern: errgroup with WaitGroup + done channel

```crystal
# Concurrent tool execution with bounded parallelism
# Equivalent to: stream::iter(calls).buffer_unordered(concurrency)

def execute_tools_concurrently(calls, concurrency, &block)
  results = Array(CollectedToolResult?).new(calls.size, nil)
  first_error = Atomic(PromptError?).new(nil)
  terminating = Atomic(Bool).new(false)

  # Bounded concurrency via semaphore channel
  sem = Channel(Bool).new(concurrency)

  wg = WaitGroup.new(calls.size)
  calls.each_with_index do |call, index|
    spawn do
      sem.send(true)  # acquire slot

      if terminating.get
        sem.receive    # release slot
        wg.done
        next
      end

      begin
        result = block.call(call)
        results[index] = result
      rescue ex : PromptError
        first_error.compare_and_set(nil, ex)
        terminating.set(true)
      rescue ex
        first_error.compare_and_set(nil, PromptError.new(ex.message))
        terminating.set(true)
      end

      sem.receive     # release slot
      wg.done
    end
  end

  wg.wait

  # Check for errors
  if err = first_error.get
    raise err
  end

  results.compact_map(&.itself)
end
```

**Key design decisions**:
- `Channel(Bool).new(concurrency)` as bounded semaphore (not `Channel(Nil)`
  per rule #1)
- `Atomic(Bool)` for termination flag (lock-free, visible to all fibers)
- `Atomic(PromptError?)` for first-error capture (CAS ensures first wins)
- `WaitGroup` ensures all fibers complete before collecting results
- Results collected by call index (preserves order)

## Phase 4: Streaming

**Source**: `agent/prompt_request/streaming.rs` `drive_agent` function

Rust uses `async_stream::stream!` to yield items. Crystal equivalent: **channel-based generator**.

### Crystal pattern: Channel generator for DriveItem stream

```crystal
# The drive_agent loop as a Crystal generator (fiber writes to channel)
def drive_agent(runner, run, is_streaming) : Channel(DriveItem | StreamingError)
  ch = Channel(DriveItem | StreamingError).new(16)  # buffered

  spawn do
    ctx = HookContext.new(is_streaming: is_streaming, agent_name: runner.agent_name)

    loop do
      step = run.next_step
      case step
      in AgentRunStep::CallModel
        # ... same as blocking path ...
        # But model call uses streaming API:
        model.stream(request).each do |delta|
          ch.send(DriveItem::TextDelta.new(delta))
        end
      in AgentRunStep::CallTools
        # Concurrent tool execution
        execute_tools_concurrently(calls, runner.concurrency) do |call|
          # ... same as blocking ...
        end
        results.each { |r| ch.send(DriveItem::ToolResult.new(r)) }
      in AgentRunStep::Done
        ch.send(DriveItem::Done.new(step.response))
        break
      end
    end
  rescue ex
    ch.send(StreamingError.new(ex))
  ensure
    ch.close
  end

  ch
end
```

**Consumer pattern** (matching upstream's `while let Some(item) = stream.next()`):
```crystal
while item = ch.receive?
  case item
  in DriveItem::TextDelta
    yield item  # or collect
  in DriveItem::ToolResult
    yield item
  in DriveItem::Done
    response = item.response
    break
  in StreamingError
    raise item.error
  end
end
```

## Phase 5: Hook dispatch patterns

### 5a: Mergeable hooks (CompletionCall)

All hooks run, patches accumulate and merge in registration order. Terminate
short-circuits.

```crystal
def resolve_completion_call_hook(ctx, prompt, history, turn) : RequestPatch?
  merged : RequestPatch? = nil
  @hooks.each do |hook|
    flow = hook.on_event(ctx, StepEvent::CompletionCall.new(prompt, history, turn))
    case flow.kind
    in Flow::Kind::Continue       then next
    in Flow::Kind::PatchRequest   then merged = merged ? merged.merge(flow.patch) : flow.patch
    in Flow::Kind::Terminate      then raise PromptError.prompt_cancelled(flow.reason)
    else raise "unexpected flow for CompletionCall: #{flow.kind}"
    end
  end
  merged
end
```

### 5b: Chained hooks (ToolCall/ToolResult)

Rewrites thread through each hook: hook N sees hook 1..N-1's rewrite.

```crystal
def dispatch_tool_call_hook(ctx, tool_name, call_id, internal_id, args) : String
  effective = args
  @hooks.each do |hook|
    flow = hook.on_event(ctx, StepEvent::ToolCall.new(
      tool_name: tool_name, args: effective, ...))
    case flow.kind
    in Flow::Kind::Continue       then next
    in Flow::Kind::RewriteArgs    then effective = flow.args.to_json
    in Flow::Kind::Skip           then return flow.reason  # caller checks
    in Flow::Kind::Terminate      then raise PromptError.prompt_cancelled(flow.reason)
    else raise "unexpected flow for ToolCall: #{flow.kind}"
    end
  end
  effective
end
```

### 5c: Tool hooks under concurrency (shared Scratchpad)

At `tool_concurrency > 1`, tool hooks for different tools run concurrently,
all sharing one `Scratchpad` via `HookContext`. The Crystal `Scratchpad`
must be Mutex-protected (currently it directly delegates to `ToolCallExtensions`
which is NOT thread-safe).

**Required change**: Scratchpad needs a `Mutex` wrapper for `-Dpreview_mt`.

```crystal
class Scratchpad
  @inner : Tool::ToolCallExtensions = Tool::ToolCallExtensions.new
  @mutex : Mutex = Mutex.new(:reentrant)  # reentrant for nested hook calls

  def update(type : T.class, & : T -> _) : T forall T
    @mutex.synchronize do
      val = @inner.get(T) || T.from_json("{}")
      yield val
      @inner.insert(val)
      val
    end
  end
  # ... similarly for insert, get, remove, contains?
end
```

## Phase 6: Integration — wire AgentRunner into existing code

1. **AgentBuilder**: Update to use new `AgentRunner` internally
2. **PromptRequest**: Thin wrapper over `AgentRunner#run`
3. **StreamingPromptRequest**: Thin wrapper over `AgentRunner#stream`
4. **Old hooks**: Remove `PromptHook`, `HookAction`, `ToolCallHookAction` from
   prompt_request.cr; migrate all hook specs to `AgentHook`
5. **Provider updates**: Incremental updates to provider files as needed

## Implementation order (red-green TDD)

| Step | What | Est. size | Depends on |
|------|------|-----------|------------|
| 1 | AgentRun state machine (blocking) | ~2K lines | — |
| 2 | AgentRun spec tests | ~30 tests | Step 1 |
| 3 | AgentRunner sequential (.run) | ~1K lines | Steps 1-2 |
| 4 | AgentRunner sequential spec tests | ~15 tests | Step 3 |
| 5 | Concurrent tool execution (errgroup) | ~200 lines | Steps 3-4 |
| 6 | Concurrent tool execution spec | ~10 tests | Step 5 |
| 7 | Streaming drive_agent (channel gen) | ~500 lines | Steps 5-6 |
| 8 | Streaming spec tests | ~10 tests | Step 7 |
| 9 | Scratchpad Mutex safety | ~50 lines | Step 5 |
| 10 | Integration: wire Agent into new runner | ~500 lines | Steps 3-8 |
| 11 | Cleanup: remove old PromptHook et al. | ~200 lines removed | Step 10 |

## Key Crystal concurrency primitives used

| Upstream (Rust) | Crystal | Why |
|-----------------|---------|-----|
| `tokio::spawn` / join | `spawn { }` + `WaitGroup` | Lightweight fibers |
| `stream::iter().buffer_unordered(N)` | `Channel(Bool).new(N)` semaphore + spawn | Bounded parallelism |
| `Arc<AtomicBool>` termination flag | `Atomic(Bool)` | Lock-free cancel signal |
| `stream! { yield item }` | `spawn { ch.send(item); ...; ch.close }` | Channel generator |
| `async fn on_event() -> Flow` | `def on_event() : Flow` | Sync hooks (simpler) |
| `Arc<Mutex<Extensions>>` | `Mutex` on `Scratchpad` | Thread-safe shared state |
| `while let Some(item) = stream.next().await` | `while item = ch.receive?` | Channel iteration |
| `.buffer_unordered(N)` (drain remaining) | `wg.wait` after setting termination flag | Drain in-flight |

## Risk assessment

| Risk | Mitigation |
|------|-----------|
| AgentRun state machine is 2300 lines of complex logic | Port incrementally, spec-by-spec |
| Async hook dispatch → sync loses parallelism | Crystal fibers yield on IO anyway; hooks don't do IO |
| Streaming under `tool_concurrency > 1` has subtle ordering | Port existing Rust tests as characterization specs |
| Moving from old PromptHook to new AgentHook breaks existing users | Keep both during transition, remove old in final cleanup |
| Scratchpad thread safety | Wrap in Mutex, test with -Dpreview_mt |
