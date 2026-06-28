# mcp_1: Missing `MCP::Client::StreamableHttpClientTransport`

- **Shard:** `mcp` (github.com/dsisnero/mcp.cr)
- **Version observed:** `0.5.4` (`lib/mcp/shard.yml`, pinned in crig `shard.lock`)
- **Severity:** medium — blocks the Streamable HTTP client path; server side already exists
- **Status:** resolved (fixed upstream in mcp `0.5.4` working copy)
- **Reported by:** crig (downstream consumer)

## Resolution

`MCP::Client::StreamableHttpClientTransport` is now implemented in the shard at
`src/mcp/client/streamable_http_client_transport.cr`
(`class StreamableHttpClientTransport < MCP::Shared::AbstractTransport`,
`self.from_uri(url : String)`). The undefined-constant repro now compiles clean.

Downstream re-enabled in crig:
- `spec/crig_spec.cr` — `require "../examples/rmcp"` uncommented
- `spec/crig_spec.cr` — `Crig::Examples::RMCP::StructRequest` spec re-enabled (passes)

Still open as a follow-up (not shard-blocked): live round-trip integration tests
for `Crig::Examples::RMCP::Counter` / `::StreamableServer`.

## Summary

The shard ships a server-side Streamable HTTP transport
(`MCP::Server::StreamableHttpServerTransport`) but **no matching client
transport**. `MCP::Client::StreamableHttpClientTransport` is referenced by
downstream code and by the MCP spec's "Streamable HTTP" transport, but the
constant does not exist anywhere in `src/`.

Client transports currently present:

| Transport | File |
|---|---|
| `MCP::Client::HttpClientTransport` | `src/mcp/client/http_client_transport.cr` |
| `MCP::Client::SseClientTransport` | `src/mcp/client/sse_client_transport.cr` |
| `MCP::Client::StdioClientTransport` | `src/mcp/client/stdio_client_transport.cr` |
| `MCP::Client::StreamableHttpClientTransport` | **missing** |

There is a client/server asymmetry: a server can speak Streamable HTTP, but a
client built with this shard cannot connect to one.

## Reproduction

```crystal
require "mcp"

transport = MCP::Client::StreamableHttpClientTransport.from_uri("http://127.0.0.1:8080/mcp")
puts transport.class
```

```
Error: undefined constant MCP::Client::StreamableHttpClientTransport
```

### Note for maintainers (why this slips past a plain compile)

Crystal does not semantically analyze method bodies that are never
instantiated. `examples/rmcp.cr` references the constant only inside
`self.build_client`, which nothing calls at top level, so
`crystal build --no-codegen examples/rmcp.cr` returns `0` and hides the gap.
The error only surfaces when the constant is actually referenced from
type-checked code (as in the snippet above).

## Downstream impact (crig)

- `examples/rmcp.cr:13`

  ```crystal
  client.connect(MCP::Client::StreamableHttpClientTransport.from_uri(uri))
  ```

- `spec/crig_spec.cr:55` — the example is disabled to keep the suite green:

  ```crystal
  # require "../examples/rmcp" # FIXME: mcp shard missing StreamableHttpClientTransport
  ```

Until the transport exists, the `rmcp` example cannot be compiled or exercised,
and the spec `require` stays commented out.

## Expected API

```crystal
module MCP::Client
  class StreamableHttpClientTransport < MCP::Shared::AbstractTransport
    def self.from_uri(uri : String) : self
    def initialize(url : String)
    def start
    def send(message : MCP::Protocol::JSONRPCMessage)
    def close
  end
end
```

It must satisfy the `MCP::Shared::Transport` contract
(`src/mcp/shared/transport.cr`): implement `start` / `send` / `close`, and
dispatch inbound JSON-RPC messages through the inherited `_on_message` callback
(register order is handled by `AbstractTransport`).

## Expected behavior (MCP Streamable HTTP)

Must interoperate with the existing `MCP::Server::StreamableHttpServerTransport`
(`src/mcp/server/streamable_server_transport.cr`) in **both** modes
(`enable_json_response: true` and SSE). Concretely, on `send`:

1. `POST` the JSON-RPC body to the single endpoint URL with:
   - `Content-Type: application/json`
   - `Accept: application/json, text/event-stream`
     (the server's `validate_headers` requires **both** media types)
   - `Mcp-Session-Id` header when a session id is known
2. Capture the `Mcp-Session-Id` response header (constant on the server is
   `MCP_SESSION_ID = "Mcp-Session-Id"`) and replay it on subsequent requests.
3. Handle the response by status / content type:
   - `202 Accepted` / empty body (notifications/responses only) → return, no dispatch
   - `application/json` → parse a single JSON-RPC message **or** a JSON array;
     dispatch each via `_on_message`
   - `text/event-stream` → parse with `MCP::Shared.parse_sse_events`
     (see `src/mcp/client/sse_client_transport.cr`) and dispatch each `message`
     frame's JSON-RPC payload
   - non-success (4xx/5xx) → raise with status + body
4. `close` → invoke `_on_close`.

(Optional, follow-up) a standalone `GET` SSE stream for server-initiated
messages and `DELETE` for session termination, mirroring the server's
`handle_get_request` / `handle_delete_request`.

## Suggested implementation

Model on the two existing client transports:

- `HttpClientTransport` — single-shot POST + inline `_on_message` dispatch
- `SseClientTransport` — `MCP::Shared.parse_sse_events` parsing of an
  `text/event-stream` body

Add `src/mcp/client/streamable_http_client_transport.cr` (auto-required by the
existing `require "./mcp/client/**"` in `src/mcp.cr`).

## Acceptance criteria

- [ ] `MCP::Client::StreamableHttpClientTransport.from_uri(url)` returns a
      `MCP::Shared::AbstractTransport`.
- [ ] A `MCP::Client::Client` connected over the new transport completes
      `initialize`, `list_tools`, and a `call_tool` round-trip against a live
      `MCP::Server::StreamableHttpServerTransport` (json-response mode at minimum).
- [ ] `Mcp-Session-Id` is captured from the init response and sent on
      subsequent requests.
- [ ] Spec added under `spec/client/streamable_http_client_transport_spec.cr`,
      following the existing client-transport spec style.
- [ ] Downstream: `examples/rmcp.cr` compiles and `spec/crig_spec.cr:55` can be
      re-enabled.

## References

- `src/mcp/server/streamable_server_transport.cr` (server counterpart, wire protocol)
- `src/mcp/client/http_client_transport.cr`, `src/mcp/client/sse_client_transport.cr`
- `src/mcp/shared/transport.cr` (`AbstractTransport` contract)
- MCP spec — Transports / Streamable HTTP
