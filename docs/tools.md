# Tools in crig

A tool is a function an LLM can call. crig supports several authoring patterns,
all of which produce the same runtime view — typed schema, string JSON dispatch,
canonical `ToolResult` output.

## Contents

- [rig_tool macro (recommended)](#rig_tool-macro-recommended)
- [Typed tool via Tool(Args, Output)](#typed-tool-via-toolargs-output)
- [DynamicTool (closure-based)](#dynamic-tool-closure-based)
- [ToolDyn (abstract interface)](#tooldyn-abstract-interface)
- [ToolContext — runtime context](#toolcontext--runtime-context)
- [ToolResult — success and error](#toolresult--success-and-error)
- [ToolSet — registration and dispatch](#toolset--registration-and-dispatch)
- [Tools with agents](#tools-with-agents)

---

## rig_tool macro (recommended)

The `Crig.rig_tool` macro generates a struct with JSON schema from a
plain Crystal method. Parameter names and types become the tool's JSON Schema;
nilable parameters are automatically optional.

```crystal
Crig.rig_tool description: "Add two integers" do
  def add(x : Int32, y : Int32) : Int32
    x + y
  end
end

# Use with an agent:
agent = client
  .agent(Crig::Providers::OpenAI::GPT_5_2)
  .tool(ADD)
  .build

response = agent.prompt("What is 2 + 3?").send
```

The schema is computed once (memoized) and reused.

### Parameter rules

| Parameter type | JSON Schema type | Required by default |
|---|---|---|
| `String` | `"string"` | yes |
| `Int32`, `Int64` | `"integer"` | yes |
| `Float64` | `"number"` | yes |
| `Bool` | `"boolean"` | yes |
| `Array(String)` | `"array"` → `items: {"type":"string"}` | yes |
| enum `Color` | `"string"` → `enum: ["red","green","blue"]` | yes |
| struct `Config` | `"object"` → nested properties | yes |
| `String?`, `Int32?` etc. | `anyOf: [{type: "..."}, {type: "null"}]` | **no** |

### Error handling

Return `Crig::ToolMacro::Result(T, E).ok(value)` or `.err(error)`:

```crystal
Crig.rig_tool description: "Divide two numbers" do
  def divide(x : Int32, y : Int32) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    if y == 0
      Crig::ToolMacro::Result(Int32, Crig::ToolError).err(
        Crig::ToolError.new("Division by zero"))
    else
      Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x // y)
    end
  end
end
```

### Description annotations

```crystal
Crig.rig_tool params: {query: "Search query", limit: "Max results"} do
  def search(query : String, limit : Int32) : Array(String)
    # ...
  end
end
```

Names in `params` and `required` are validated at compile time — mismatches
are caught before the binary is built. Nilable fields in `required` also
produce a compile error.

---

## Typed tool via Tool(Args, Output)

For full control, implement the `Crig::Tool(Args, Output)` module on a
custom struct. `Args` must include `JSON::Serializable` for JSON parsing.

```crystal
struct AddArgs
  include JSON::Serializable
  getter x : Int32
  getter y : Int32
end

struct AddTool
  include Crig::Tool(AddArgs, String)

  NAME = "add"

  def description : String
    "Add two integers"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
  end

  def call_typed(args : AddArgs) : String
    (args.x + args.y).to_s
  end
end
```

The module provides `call(args : String) : String` for string-based dispatch,
which calls `call_typed` under the hood.

---

## DynamicTool (closure-based)

`Crig::DynamicTool` wraps a closure for ad-hoc or dynamically-created tools.
The callback receives raw `String` arguments and a `ToolContext`, and returns
a `Tool::ToolResult`.

```crystal
greet = Crig::DynamicTool.new(
  "greet",
  "Greet someone",
  JSON.parse(%({"type":"string"})),
) do |args, ctx|
  Crig::Tool::ToolResult.success(Crig::Tool::ToolOutput.text("Hello #{args}"))
end

# Execute with context:
result = greet.execute("world", Crig::Tool::ToolContext.new)
result.output.as_text  # => "Hello world"

# Or via the string dispatch (creates an empty context):
greet.call("world")  # => "Hello world"
```

`DynamicTool` implements `Crig::ToolDyn`, so it can be added to any
`ToolSet` or agent.

---

## ToolDyn (abstract interface)

`Crig::ToolDyn` is the abstract erased-tool interface used by `ToolSet`
internally:

```crystal
module Crig::ToolDyn
  def name : String
  def description : String
  def parameters : JSON::Any
  def call(args : String) : String
end
```

Implement it directly for zero-overhead integration, though `Tool(Args, Output)`
or `DynamicTool` are preferred for new code.

---

## ToolContext — runtime context

Every tool execution receives a `Tool::ToolContext`. Callers insert typed
values; tools read them and optionally attach result metadata.

```crystal
struct AuditRecord
  getter value : Int64
  def initialize(@value : Int64)
  end
end

# Caller sets inbound context:
ctx = Crig::Tool::ToolContext.new
ctx.insert("user-123")

# Tool reads context and writes result metadata:
tool = Crig::DynamicTool.new("audit", "Audit", params) do |args, ctx|
  user = ctx.require(String)          # raises MissingToolContext if absent
  ctx.insert_result(AuditRecord.new(42))
  Crig::Tool::ToolResult.success(Crig::Tool::ToolOutput.text("audited"))
end
```

| Method | Purpose |
|---|---|
| `insert(T)` | Store an inbound typed value |
| `get(T.class)` | Read an inbound typed value (returns `nil` if absent) |
| `require(T.class)` | Read or raise `MissingToolContext` |
| `contains?(T.class)` | Check if a type is present |
| `insert_result(T)` | Attach result metadata (not sent to model) |
| `result(T.class)` | Read result metadata |
| `for_dispatch` | Clone inbound values for one tool execution |

---

## ToolResult — success and error

The canonical execution view returned by dispatch methods:

```crystal
result = ts.execute("add", %({"x":2,"y":3}), ctx)

result.success?           # => true
result.error?             # => false
result.skipped?           # => false
result.refused?           # => false
result.output.as_text     # => "5"
result.status_name        # => "success"
result.error              # => nil (only for disposition Error)

# Building results:
Crig::Tool::ToolResult.success(output)
Crig::Tool::ToolResult.failed(error)          # distinguishes Error vs Refused
Crig::Tool::ToolResult.skipped("policy rule")
```

### ToolExecutionError

```crystal
# Per-kind constructors:
Crig::Tool::ToolExecutionError.invalid_args("missing field `x`")
Crig::Tool::ToolExecutionError.timeout("execution exceeded 30s")
Crig::Tool::ToolExecutionError.not_found("tool `calc` not registered")
Crig::Tool::ToolExecutionError.provider("upstream returned 503")
Crig::Tool::ToolExecutionError.refused("cannot divide by zero")  # sets refusal flag

# Builder methods:
err.with_retryable(true)
err.with_model_feedback("tool timed out, try again")
err.code("RATE_42")
err.http_status(429)
```

Errors from unknown sources are wrapped with `ToolExecutionError.from_error`:

```crystal
Crig::Tool::ToolExecutionError.from_error(some_exception)
```

This preserves the original exception for downcasting and defaults to safe
kind-level model feedback.

---

## ToolSet — registration and dispatch

`ToolSet` is the runtime collection. Add tools and execute them:

```crystal
ts = Crig::ToolSet.new
ts.add_tool(AddTool.new)
ts.add_tool(greet_dynamic)

result = ts.execute("add", %({"x":2,"y":3}), ctx)
# => Crig::Tool::ToolResult
```

`ToolSetBuilder` provides a fluent interface:

```crystal
ts = Crig::ToolSetBuilder.new
  .static_tool(AddTool.new)
  .retrieved_tool(EmbeddingTool.new)   # embedding-backed (was dynamic_tool)
  .build
```

---

## Tools with agents

Register one or more tools on the agent builder:

```crystal
agent = client
  .agent(Crig::Providers::OpenAI::GPT_5_2)
  .preamble("You are a helpful assistant with tools.")
  .tool(ADD)              # macro-generated constant
  .tool(AddTool.new)      # typed tool
  .build
```

For tool servers, create a `ToolServer`, add tools, and hand the handle
to the agent:

```crystal
server = Crig::ToolServer.new
  .tool(AddTool.new)
  .tool(SubtractTool.new)
  .run

agent = client
  .agent(Crig::Providers::OpenAI::GPT_5_2)
  .tool_server(server)
  .build
```

The agent runner dispatches tool calls through `ToolServerHandle#execute`,
which returns `Tool::ToolResult`.
