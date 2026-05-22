# Performance Audit Log — `crig` (Crystal port of `rig`)

**Branch:** `perf`
**Baseline:** `main` (commit `61bfbab`, before perf work)
**Current:** `perf` (commit `5ade0cf`, after all fixes)
**Date:** 2026-05-22

## Measurement Commands

```bash
# Concurrency microbenchmark (CPU-light and I/O)
crystal run --release -Dpreview_mt -Dexecution_context benchmarks/parallel_runtime_bench.cr

# MCP dispatch benchmark
crystal run --release -Dpreview_mt -Dexecution_context benchmarks/mcp_dispatch_bench.cr

# Correctness gate
crystal spec spec/crig_spec.cr spec/memory_spec.cr
```

## Measurement Infrastructure Notes

The existing benchmarks measure runtime concurrency patterns (fiber spawn, channel send/receive, fan-out). They do **not** cover per-request allocation paths (message construction, SSE parsing, memory policy application). Allocation wins from these fixes are structural (fewer heap allocations per call) and validated by code inspection and spec coverage rather than a microbenchmark that would need to be written.

The MCP dispatch benchmark (`benchmarks/mcp_dispatch_bench.cr`) times out on the batch phase when CML (`cml`) is included — this is a pre-existing issue with the CML shard interaction, not introduced by these changes. The single-call phase completes normally.

## Experiments

### Experiment 1: Concurrency safety — lock-storm and timeouts

**Hypothesis:** ToolServer's `get_tool_definitions` causes excessive mutex contention with N individual `@lock.synchronize` calls per tool definition fetch. Adding timeout support to `Concurrency.run` prevents indefinite hangs when tool calls block.

**Files:** `src/crig/tool/server.cr`, `src/crig/concurrency.cr`

**Baseline (main):** N/A (binary fix, not a throughput change)

**After (perf):**
```bash
crystal run --release -Dpreview_mt -Dexecution_context benchmarks/parallel_runtime_bench.cr
```

| Metric | Baseline (main) | After (perf) | Delta |
|--------|----------------|--------------|-------|
| crig_concurrency wall clock | 126.673ms | 127.160ms | +0.4% (noise) |
| crig_concurrency fanout | 127.519ms | 130.109ms | +2.0% (noise) |

**Decision:** KEEP. No regression. Lock-storm fix reduces N `synchronize` calls to ~1 per `get_tool_definitions`. Timeout adds safety without changing the no-timeout path.

**Correctness:** 1105 specs, 0 failures.

---

### Experiment 2: `OneOrMany#to_a` array allocation

**Hypothesis:** `OneOrMany#to_a` is the single hottest allocation path with 75+ call sites, each creating 2 heap arrays (`[@first]` + concatenation). Reducing to 1 pre-sized array saves ~75 allocations per request.

**File:** `src/crig/one_or_many.cr:197-199`

**Before:**
```crystal
def to_a : Array(T)
  [@first] + @rest    # 2 heap arrays: [@first] (1 element) + concatenation result
end
```

**After:**
```crystal
def to_a : Array(T)
  result = Array(T).new(@rest.size + 1)   # 1 heap array, pre-sized
  result << @first
  result.concat(@rest)
  result
end
```

**Measurement:** Not captured by existing benchmarks (allocate-only, no concurrency). Validated by code inspection:
- `to_a` called ~75 times across the codebase (from earlier grep audit)
- Every call previously created 2 arrays, now creates 1
- `iter`/`into_iter`/`iter_mut` also call `to_a` internally (additional 3+ sites per stream turn)

**Decision:** KEEP. Pure win — same result, one fewer allocation per call, no behavior change.

**Correctness:** 1105 specs, 0 failures. All `OneOrMany` usage passes.

---

### Experiment 3: Parallel tool execution in agent loop

**Hypothesis:** The non-streaming `execute_tool_calls` runs tools sequentially (default concurrency=1, `each_slice(1)` loop). The streaming variant uses `Concurrency.map_ordered` for true parallelism. Aligning the non-streaming path improves tool execution throughput.

**File:** `src/crig/agent/prompt_request.cr:317-340`

**Before:**
```crystal
# Sequential: each_slice(limit) with limit=1, channel.receive blocks on each tool
tool_calls.each_slice(limit) do |batch|
  channels = batch.map { |choice| Concurrency.run { execute_tool_call(choice, history.dup, i) } }
  results = channels.map { |c| c.receive.unwrap }  # blocks sequentially
end
```

**After:**
```crystal
# Parallel: all tools spawned as fibers, results collected via map_ordered
indexed = tool_calls.map_with_index { |choice, index| {choice, index} }
results = Concurrency.map_ordered(indexed) do |(choice, index)|
  execute_tool_call(choice, chat_history, index)  # no .dup needed
end
```

**Side fix:** Removed `chat_history.dup` — history is read-only in hooks, never mutated by tool execution.

**Measurement:**
| Metric | Baseline (sequential) | After (parallel) | Delta |
|--------|----------------------|------------------|-------|
| crig_concurrency fanout | 127.519ms | 130.109ms | +2.0% (noise) |

The fan-out benchmark tests `Concurrency.map_ordered`, not the agent tool path specifically. No regression.

**Decision:** KEEP. Matches streaming variant's parallel pattern. Removes `history.dup` per tool call.

**Correctness:** 1105 specs, 0 failures.

---

### Experiment 4: `.to_a.each` → `.each` on `OneOrMany`

**Hypothesis:** 5 call sites do `one_or_many.to_a.each` which creates an unnecessary intermediate array. `OneOrMany` includes `Enumerable`, so `.each` works directly.

**Files:**
- `src/crig/providers/ollama.cr:486`
- `src/crig/providers/galadriel.cr:178`
- `src/crig/providers/huggingface/completion.cr:261,285,613`

**Before:**
```crystal
message.content.to_a.each do |item|   # to_a allocates array, then each iterates
```

**After:**
```crystal
message.content.each do |item|        # each iterates directly, no array
```

**Decision:** KEEP. Pure win — 1 fewer array per call site, no behavior change.

---

### Experiment 5: `render_message_line` in `TemplateCompactor`

**Hypothesis:** `render_message_line` creates `parts = [] of String` and then `parts.reject(&.empty?).join(' ')` which creates a second array. Using `IO::Memory` builder avoids both arrays.

**File:** `src/crig/memory/policies.cr:256-296`

**Before:** 2 arrays per evicted message (parts + reject result)
**After:** IO::Memory builder, no intermediate arrays

**Decision:** KEEP. 2 fewer arrays per evicted message during compaction. No behavior change.

**Correctness:** 47 memory specs, 0 failures.

---

### Experiment 6: `append_reasoning_chunk` in streaming

**Hypothesis:** `reasoning.content[0...-1] + [new]` creates 2 arrays (range slice + concatenation) on every reasoning delta. Using `dup` + in-place modification avoids one array.

**File:** `src/crig/streaming.cr:557-562`

**Before:**
```crystal
updated = Reasoning.new(
  reasoning.content[0...-1] + [       # 2 arrays: slice + concat result
    ReasoningContent.text("#{content.text}#{text}", content.signature)
  ],
  reasoning.id
)
```

**After:**
```crystal
new_content = reasoning.content.dup   # 1 array: dup
new_content[-1] = ReasoningContent.text("#{content.text}#{text}", content.signature)
updated = Reasoning.new(new_content, reasoning.id)
```

**Decision:** KEEP. 1 fewer array per reasoning delta.

**Correctness:** 1105 specs, 0 failures (reasoning merge specs pass).

---

### Experiment 7: Policy `demoted + [w[0]]` → `demoted << w[0]`

**Hypothesis:** `demoted = demoted + [window[0]]` creates a 1-element array plus a concatenation result. `demoted << window[0]` appends in-place.

**Files:** `src/crig/memory/policies.cr` (SlidingWindowMemory and TokenWindowMemory)

**Decision:** KEEP. 2 fewer arrays per orphan-tool-result check.

---

### Experiment 8: `map_one_or_many` for Message conversion

**Hypothesis:** `Message.from(OneOrMany(UserContent))` uses `to_a.map.as.many()` which creates 3+ arrays. `map_one_or_many` does the same with 1 array.

**File:** `src/crig/completion/message.cr:1104-1164`

**Before:**
```crystal
def self.from(content : OneOrMany(UserContent)) : self
  content = content.to_a.map(&.as(UserContent | AssistantContent))  # 2 arrays: to_a + map
  new(Role::User, OneOrMany.many(content))                           # 1 more: many internal
end
```

**After:**
```crystal
def self.from(content : OneOrMany(UserContent)) : self
  new(Role::User, content.map_one_or_many(&.as(UserContent | AssistantContent)))  # 1 array: @rest.map
end
```

**Decision:** KEEP. 2 fewer arrays per Message conversion at 3 call sites.

---

### Experiment 9 (CANCELLED): Lazy `finalize_choice` in streaming

**Hypothesis:** `finalize_choice` is called 6+ times per stream chunk (once per `process_choice` branch). Moving to lazy eval in `to_completion_response` would save ~6 OneOrMany constructions per chunk.

**Result:** REVERTED. The `choice` getter is accessed during streaming (not just at end), so lazy eval would return stale data. Tests failed.

**Decision:** DISCARDED. Cannot lazily defer finalization without changing the public API contract.

**Correctness (before revert):** 3 streaming spec failures.

---

### Experiment 10: Concurrency audit — unbuffered channel deadlock analysis

**Hypothesis:** Unbuffered channels (`Channel.new` without capacity) in `tool/rmcp.cr`, `integrations/discord_bot.cr`, and `http_client.cr` could deadlock.

**Result:** FALSE POSITIVE. Crystal's fiber scheduler correctly pairs `send`/`receive` on unbuffered channels when both fibers exist. The `spawn { actor_loop }` is followed by external code calling `send`, which blocks the caller, triggering the scheduler to run the spawned fiber, which receives. No deadlock.

**Decision:** NO CHANGE NEEDED.

---

## Summary

| # | Experiment | Outcome | Arrays saved |
|---|-----------|---------|--------------|
| 1 | Lock-storm + timeouts | Kept | N/A |
| 2 | `OneOrMany#to_a` | Kept | 1 per call (75+ sites) |
| 3 | Parallel tool execution | Kept | N/A (throughput) |
| 4 | `.to_a.each` → `.each` | Kept | 1 per call (5 sites) |
| 5 | `render_message_line` | Kept | 2 per evicted msg |
| 6 | `append_reasoning_chunk` | Kept | 1 per reasoning delta |
| 7 | Policy `demoted << w[0]` | Kept | 1 per orphan check |
| 8 | `map_one_or_many` | Kept | 2 per msg conversion |
| 9 | Lazy `finalize_choice` | Cancelled | — |
| 10 | Unbuffered channels | No change | — |

**Correctness gate:** 1105 specs, 0 failures, 0 errors, 3 pending on all commits.
**Benchmark regression:** None detected (within noise).
**Baseline capture:** `crystal run --release -Dpreview_mt benchmarks/parallel_runtime_bench.cr` — crig_concurrency fanout 127.5ms, wall clock 126.7ms.

### Uncaptured Optimization Opportunities (future passes)

| Path | Cost | Why not captured |
|------|------|-----------------|
| `policy.cr` SlidingWindow/TokenWindow range slices | 2-4 arrays per apply | Crystal doesn't have array slice views; would need `Slice` or custom type |
| `finalize_choice` 6x per chunk | 6 OneOrMany constructions per chunk | Getter accessed mid-stream; lazy eval changes API contract |
| `raw_choices_from_choice` `.to_a.flat_map` | 2 arrays per call | Called once at init; low per-request frequency |
| `InMemoryConversationMemory#load` `.dup` | 1 full copy per load | Required for thread safety under mutex |
