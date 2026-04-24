# Developing a GenieLamp

A GenieLamp is a tool integration defined by two files:

1. **An XML definition** at `priv/lamps/<vendor>_<service>_<action>.xml` — the
   declarative contract (form, endpoints, actions, status templates).
2. **An Elixir handler module** at `lib/genie/lamps/<vendor>/<service>_<action>.ex` —
   the in-process implementation that serves each endpoint.

Both files are generated together by `mix genie.lamp.new`, then customised. The
compile-time and parse-time checks described below catch mismatches between the
two before your lamp reaches runtime.

> **Scope:** this guide covers the `runtime=inline` path, which is the default
> for first-party lamps. The `runtime=remote` path (HTTP backend) is documented
> in [REQUIREMENTS.md §7.1](REQUIREMENTS.md).

---

## 1. Quick start

```sh
mix genie.lamp.new aws.lambda.invoke
```

Three files are generated:

```
priv/lamps/aws_lambda_invoke.xml
lib/genie/lamps/aws/lambda_invoke.ex
test/genie/lamps/aws/lambda_invoke_test.exs
```

Edit the XML (form, endpoints, templates), implement the handler callbacks,
then:

```sh
mix compile --warnings-as-errors   # catches missing @endpoint clauses
mix genie.lamp.verify              # full XML + handler contract check
mix test test/genie/lamps/aws/lambda_invoke_test.exs
mix genie.lamps.load               # register into the runtime
iex -S mix phx.server              # poke at it in the cockpit
```

---

## 2. Anatomy of a lamp XML

The full schema lives in [REQUIREMENTS.md §5.1](REQUIREMENTS.md). Here's the
minimal inline-lamp shape the scaffolder generates, annotated:

```xml
<lamp id="aws.lambda.invoke" version="1.0" category="compute" vendor="aws">

  <meta>
    <title>Invoke Lambda Function</title>
    <description>Invoke a named AWS Lambda function with a JSON payload.</description>
    <icon>aws-lambda</icon>
    <tags>aws,compute,lambda</tags>

    <!-- Governance -->
    <requires-approval>false</requires-approval>
    <destructive>false</destructive>
    <audit>true</audit>

    <!-- Runtime: inline means an Elixir module serves this lamp in-process. -->
    <runtime>inline</runtime>
    <handler>Genie.Lamps.AWS.LambdaInvoke</handler>

    <timeout-ms>10000</timeout-ms>
  </meta>

  <endpoints>
    <!-- Every endpoint your lamp uses. Bridge rejects undeclared endpoints. -->
    <endpoint id="invoke" method="POST" path="/aws/lambda/invoke"
              trigger="on-submit" action-id="submit">
      <!-- Declares the shape of the handler's response map. Required keys are
           enforced at runtime. Keys named here are accepted in status-template
           {placeholders}. -->
      <response-schema>
        <key name="state" type="string" required="true"/>
        <key name="function_name" type="string"/>
        <key name="output" type="string"/>
        <key name="error_message" type="string"/>
      </response-schema>
    </endpoint>
  </endpoints>

  <ui>
    <form aria-label="Invoke a Lambda function" aria-describedby="form-description">
      <description id="form-description">Invoke a Lambda by name with a JSON payload.</description>

      <field id="function_name" type="text" label="Function Name"
             aria-label="AWS Lambda function name, e.g. prod-image-thumbnailer"
             genie-fill="from-context" required="true"/>

      <field id="payload" type="textarea" label="Payload (JSON)"
             aria-label="Invocation payload, valid JSON object"
             genie-fill="infer" required="true" rows="6"/>
    </form>
  </ui>

  <actions>
    <action id="submit" label="Invoke"
            aria-label="Invoke the Lambda function with the given payload"
            style="primary" endpoint-id="invoke" behavior="submit"/>
  </actions>

  <status-templates>
    <template state="submitting">
      <field type="spinner" label="Invoking..."
             aria-label="Invoking Lambda function {function_name}" style="info"/>
    </template>

    <template state="ready">
      <field type="banner" label="Done"
             aria-label="Lambda {function_name} returned: {output}"
             style="success" value="{output}"/>
    </template>

    <template state="failed">
      <field type="banner" label="Failed"
             aria-label="Lambda invocation failed: {error_message}"
             style="error" value="{error_message}"/>
    </template>
  </status-templates>
</lamp>
```

**What the parser enforces at registration time** (full list in
[REQUIREMENTS.md §6.2](REQUIREMENTS.md)):

- `aria-label` on every field, action, and status-template field.
- Every endpoint referenced by an action / `options-from` / `row-click-endpoint` exists.
- Every path `{param}` resolves to a form field id (or `id` for row-click endpoints).
- Every status-template `{placeholder}` resolves to a form field id, a declared
  `<response-schema>` key, or a conventional key (`state`, `error_message`,
  `error`, `count`). **Strict** error when any endpoint declares a response
  schema; warn-mode otherwise.
- `runtime=inline` requires `<handler>`; `runtime=remote` requires `<base-url>`.
- At least one positive status state (`ready`, `success`, `ready-*`, `no_*`).

---

## 3. The handler module

```elixir
defmodule Genie.Lamps.AWS.LambdaInvoke do
  @moduledoc "Inline handler for the `aws.lambda.invoke` lamp."

  use Genie.Lamp.Handler, lamp_id: "aws.lambda.invoke"

  @endpoint "invoke"
  def handle_endpoint("invoke", %{"function_name" => name, "payload" => payload}, ctx) do
    # ctx.actor, ctx.org_id, ctx.trace_id, ctx.session_id all available
    case AWS.Lambda.invoke(name, Jason.decode!(payload)) do
      {:ok, output} ->
        {:ok, %{"state" => "ready", "function_name" => name, "output" => output}}

      {:error, %{message: msg}} ->
        {:ok, %{"state" => "failed", "error_message" => msg}}
    end
  end
end
```

### 3.1 The `use` macro

`use Genie.Lamp.Handler, lamp_id: "..."` does three things:

1. Declares the module implements the `Genie.Lamp.Handler` behaviour.
2. Opens a `@endpoint` accumulator attribute you use to tag each clause.
3. Wires a `@before_compile` hook that reads the lamp XML at compile time and
   diffs the XML's endpoint ids against your `@endpoint` attributes.

### 3.2 Callbacks

| Callback | Required | Purpose |
|---|---|---|
| `handle_endpoint(endpoint_id, params, %Context{})` | yes | Serve every endpoint declared in the lamp XML. |
| `handle_options(endpoint_id, %Context{})` | optional | Shortcut for `fills-field` / `options-from` endpoints that return `[map]` instead of a status map. If not defined, the Bridge calls `handle_endpoint/3` with empty params and expects a list response. |

### 3.3 The Context struct

Every callback receives a `%Genie.Lamp.Handler.Context{}` with:

| Field | Source |
|---|---|
| `:lamp_id`, `:endpoint_id` | XML declarations |
| `:session_id` | Current cockpit session UUID |
| `:trace_id` | OTel trace id for this user action |
| `:actor` | `%Genie.Accounts.User{}` — who triggered the action |
| `:org_id` | The actor's organisation UUID |
| `:lamp`, `:endpoint` | Pre-resolved `%LampDefinition{}` and `%EndpointDef{}` |
| `:started_at` | `System.monotonic_time(:millisecond)` at dispatch |
| `:metadata` | Escape hatch — free-form map, rarely used |

### 3.4 Return contract

- **`{:ok, map}`** — must contain a `state` key that matches a declared
  `<status-template>`. Required keys from the endpoint's `<response-schema>`
  are enforced by the Bridge (behind `:genie, :inline_strict_responses`,
  default `true` in dev/test). Keys used as `{placeholder}` substitutions in
  the matched template are looked up in this map.

- **`{:ok, [map]}`** — only for `handle_options/2` (or `handle_endpoint/3` on
  `fills-field` endpoints when `handle_options/2` is not defined). Each item
  is `%{"value" => "...", "label" => "..."}` by default, or whatever keys the
  field's `options-value-key` / `options-label-key` specify.

- **`{:error, term}`** — surfaced to the cockpit as `push_error`. Known
  error tuples pass through verbatim; unknown errors collapse to
  `{:service_unavailable, trace_id}`.

### 3.5 Crash handling

Handler crashes are rescued by the Bridge and returned as
`{:error, {:handler_crash, msg}}`. Don't build try/rescue into every handler —
unexpected crashes should surface as errors. Use `{:error, reason}` for
expected failures (invalid input, upstream 5xx, etc.).

---

## 4. What the platform does for you

You never write any of this — the scaffold and platform handle it:

- **HTML rendering.** `Genie.Lamp.LampRenderer` converts your response map into
  the status-template's HTML via Phoenix components. You return structured data,
  not markup.
- **Form fill.** Fields marked `genie-fill="from-context"` are filled from the
  conversation context; `infer` fields are filled via one LLM call. You only
  define the XML.
- **Polling.** Endpoints with `trigger="on-complete"` and `poll-until=...` are
  polled by `LampActionWorker.run_poll_loop/4`. Your handler just keeps
  returning states; the worker stops when `poll-until` matches.
- **Approval.** `<requires-approval>true</requires-approval>` automatically
  suspends the action until approved; your handler only runs after approval.
- **Audit + tracing.** Every invocation is wrapped in an OTel span and written
  to the `AuditLog` Ash resource. You get this for free.
- **Authorisation.** `Ash` policies on `LampAction` check actor/org access
  before your handler is called. If you need finer-grained authz inside the
  handler, `ctx.actor` and `ctx.org_id` are the inputs.

---

## 5. Testing

### 5.1 Unit-testing the handler

Handlers are plain modules — call them directly:

```elixir
defmodule Genie.Lamps.AWS.LambdaInvokeTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.AWS.LambdaInvoke

  defp ctx(endpoint_id) do
    %Context{lamp_id: "aws.lambda.invoke", endpoint_id: endpoint_id,
             session_id: "t", trace_id: "trace-1"}
  end

  test "invoke returns ready with output" do
    {:ok, response} = LambdaInvoke.handle_endpoint("invoke",
      %{"function_name" => "noop", "payload" => "{}"}, ctx("invoke"))

    assert response["state"] == "ready"
    assert response["function_name"] == "noop"
  end
end
```

### 5.2 Worker / integration tests — the handler override

When a worker test needs to drive a deterministic response through the whole
worker → Bridge → renderer pipeline, inject a test handler via config:

```elixir
defmodule AlwaysErrorHandler do
  def handle_endpoint(_, _, _), do: {:error, :simulated_backend_failure}
end

setup do
  Application.put_env(:genie, :lamp_handler_overrides,
    %{"Genie.Lamps.AWS.LambdaInvoke" => inspect(AlwaysErrorHandler)})

  on_exit(fn -> Application.delete_env(:genie, :lamp_handler_overrides) end)
end
```

The Bridge's `resolve_handler/1` honours the override map before `Module.concat`,
so the stub runs in place of the real handler for the duration of the test.
Real examples: `test/genie/workers/lamp_action_worker_test.exs` (`AlwaysErrorHandler`),
`test/genie/workers/approval_worker_test.exs` (`CountingS3Handler`).

### 5.3 Renderer snapshot tests

If your lamp renders a distinctive visual element (table, detail panel), add
a snapshot fixture at `test/fixtures/lamp_renderer/<lamp>_snapshot.html` and
exercise it via `test/genie/lamp/lamp_renderer_test.exs`.

---

## 6. The mix tasks

| Task | When to run |
|---|---|
| `mix genie.lamp.new <vendor>.<service>.<action>` | Once, to scaffold a new lamp. Pass `--force` to overwrite existing files. |
| `mix genie.lamp.verify` | Every commit (wire into CI). Parses all lamps, resolves inline handlers, confirms `@endpoint` clauses match XML endpoints. Exits non-zero on any drift. |
| `mix genie.lamps.load` | After editing XML that's already registered, or to seed a new dev database. |

Add `mix genie.lamp.verify` to your `mix.exs` CI alias alongside `mix compile
--warnings-as-errors` and `mix test` so any lamp/handler contract drift fails
the pipeline.

---

## 7. Pre-merge checklist

Before opening a PR that adds or changes a lamp:

- [ ] `mix compile --warnings-as-errors` succeeds (the `@before_compile` check
      is emitted as `IO.warn`, which this promotes to a compile error).
- [ ] `mix genie.lamp.verify` passes.
- [ ] Handler has a unit test file covering each endpoint clause.
- [ ] Worker/integration tests that exercise this lamp use the handler override
      pattern (§5.2), not `Req.Test.stub` (that path is for remote lamps only).
- [ ] The XML's `<response-schema>` lists every key the status templates
      reference via `{placeholder}`. No latent warn-mode warnings.
- [ ] If the lamp is `<destructive>true</destructive>` or
      `<requires-approval>true</requires-approval>`, a policy test in
      `test/genie/conductor/` covers the gating.
- [ ] `aria-label` on every field, action, and status-template field is
      unambiguous without visual context (see
      [REQUIREMENTS.md §5.3](REQUIREMENTS.md)).

---

## 8. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `IO.warn` at compile time: *"missing @endpoint clause for..."* | Your handler is missing a clause for an XML-declared endpoint. Add `@endpoint "..."` + `def handle_endpoint("...", ...)`. |
| `IO.warn`: *"has @endpoint clauses for [...] which are not declared..."* | Your handler has a clause for an endpoint that isn't in the XML. Either add the endpoint to the XML or remove the clause. |
| Parse error: *"status-template references unknown placeholder {x}"* | Either add `{x}` to the endpoint's `<response-schema>` as a `<key>`, or fix the typo. |
| Parse error: *"endpoint X path references unknown param {y}"* | Path `{y}` doesn't match any form field id. Either rename the field, rename the placeholder, or (for row-click endpoints) use `{id}`. |
| Boot-time error: *"inline handler resolution failed: module_not_loaded"* | `<handler>` in XML names a module that doesn't exist / isn't compiled. Check spelling and `lib/genie/lamps/...` path. |
| Runtime error: `{:missing_required_response_keys, [...]}` | Your handler returned a map without all keys declared `required="true"` in the endpoint's `<response-schema>`. |
| Runtime error: `{:handler_crash, msg}` | Unexpected exception in your handler. The Bridge rescued it — check logs with the trace id for the full stacktrace. |

---

## 9. Where to read next

- [REQUIREMENTS.md](REQUIREMENTS.md) — the full platform spec, including the
  XML schema reference, security requirements, approval workflow, and the
  first-party lamp implementation order.
- `priv/lamps/*.xml` — the five shipped lamps are the best examples.
- `lib/genie/lamps/*/*.ex` — their handler implementations.
- `lib/genie/bridge/bridge.ex` — the dispatch seam, if you're debugging how a
  request reaches your handler.
