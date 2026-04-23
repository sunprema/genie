# Genie — Implementation Roadmap

**Version:** 1.0  
**Format:** Each task has a checkbox. The coding agent marks `[ ]` → `[x]` on completion.  
**Principle:** Each slice produces working, testable software. No slice leaves the codebase in a broken state.

---

## How to Use This Roadmap

- Complete slices in order. Later slices depend on earlier ones.
- Mark each task `[x]` when complete and all tests pass.
- Do not start a new slice until the current one is fully checked.
- If a task is explicitly deferred, mark it `[~]` with a note.
- The Definition of Done from `REQUIREMENTS.md §14` applies to every task.

---

## Slice 0 — Project Scaffold

> Establishes the umbrella structure, CI, code quality tooling, and base dependencies. No domain logic yet.

- [x] Create Elixir umbrella project with two apps: `genie` and `genie_web`
- [x] Add dependencies to `mix.exs`: `ash`, `ash_phoenix`, `ash_postgres`, `ash_oban`, `reactor`, `spark`, `saxy`, `jason`, `req`, `oban`, `opentelemetry`, `opentelemetry_api`, `opentelemetry_exporter`
- [x] Configure `Genie.Repo` (Ash PostgreSQL repo) in `genie`
- [x] Configure Phoenix endpoint, router skeleton, and `GenieWeb.Telemetry` in `genie_web`
- [x] Create `docker-compose.yml` with PostgreSQL service and correct port mapping
- [x] Create `.env.example` with all required environment variables documented
- [x] Create initial Ecto migration for the `public` schema
- [x] Configure `mix format`, `credo`, and `dialyxir` with project-appropriate rules
- [x] Set up GitHub Actions CI: `mix deps.get`, `mix compile --warnings-as-errors`, `mix test`, `mix format --check-formatted`, `mix credo`
- [x] Confirm `mix test` passes on a clean checkout with only `docker-compose up -d`

---

## Slice 1 — Ash Domain Foundation

> Core Ash resources, data layer, and policies. No UI, no AI, no lamps yet.

### Accounts domain

- [x] Define `Genie.Accounts.Organisation` Ash resource with attributes: `id`, `name`, `slug`, `inserted_at`
- [x] Define `Genie.Accounts.User` Ash resource with attributes: `id`, `email`, `name`, `role`, `org_id`, `inserted_at`
- [x] Define `Genie.Accounts.ApiKey` Ash resource with attributes: `id`, `name`, `key_hash`, `user_id`, `expires_at`
- [x] Write migrations for all three resources
- [x] Write Ash policy: users may only read resources within their own organisation
- [x] Write unit tests for all policies — including cross-org rejection cases

### Conversation domain

- [x] Define `Genie.Conversation.Session` Ash resource with attributes: `id`, `org_id`, `user_id`, `title`, `inserted_at`, `updated_at`
- [x] Define `Genie.Conversation.Turn` Ash resource with attributes: `id`, `session_id`, `role` (`:user | :agent`), `content`, `inserted_at`
- [x] Write migration for Session and Turn
- [x] Define `Ash.read` action `recent_turns/2` — accepts `session_id` and `limit`, ordered by `inserted_at desc`
- [x] Write unit tests for `recent_turns/2`

### Audit domain

- [x] Define `Genie.Audit.AuditLog` Ash resource with attributes: `id`, `session_id`, `lamp_id`, `intent_name`, `actor_id`, `trace_id`, `oban_job_id`, `result`, `inserted_at`
- [x] Configure `AuditLog` with append-only policy — no update or destroy actions permitted
- [x] Write migration for AuditLog
- [x] Write unit test confirming update and destroy actions are rejected at the policy layer

---

## Slice 2 — GenieLamp XML Parser

> Parses a GenieLamp XML file into a validated `%LampDefinition{}` struct. No rendering yet.

### Data structures

- [x] Define `Genie.Lamp.LampDefinition` struct (all fields per `REQUIREMENTS.md §6.1`)
- [x] Define `Genie.Lamp.MetaDef` struct
- [x] Define `Genie.Lamp.FieldDef` struct with `value: nil` default
- [x] Define `Genie.Lamp.OptionDef` struct
- [x] Define `Genie.Lamp.ActionDef` struct
- [x] Define `Genie.Lamp.EndpointDef` struct
- [x] Define `Genie.Lamp.GroupDef` struct
- [x] Define `Genie.Lamp.StatusTemplate` struct

### Parser

- [x] Implement `Genie.Lamp.LampParser.parse/1` using Saxy SAX callbacks
- [x] Handle `<lamp>` element — extract `id`, `version`, `category`, `vendor`
- [x] Handle `<meta>` child elements — `<title>`, `<description>`, `<icon>`, `<tags>`, `<requires-approval>`, `<approval-policy>`, `<destructive>`, `<audit>`, `<base-url>`, `<auth-scheme>`, `<timeout-ms>`
- [x] Handle `<endpoint>` elements — all attributes per schema
- [x] Handle `<field>` elements — all types and all attributes per schema
- [x] Handle `<option>` elements — `value`, `label`, `description`
- [x] Handle `<hint>` elements — link to parent field by `aria-describedby`
- [x] Handle `<group>` elements — resolve child fields into `GroupDef`, record `group_id` on each child `FieldDef`
- [x] Handle `<action>` elements
- [x] Handle `<template>` elements and their child `<field>` elements
- [x] Parse `genie-fill` attribute: `"from-context"` → `:from_context`, `"infer"` → `:infer`, `"none"` → `:none`
- [x] Parse `type` attribute into atom: `:text`, `:textarea`, `:select`, `:radio`, `:toggle`, `:number`, `:date`, `:checkbox_group`, `:hidden`

### Validation

- [x] Validate lamp `id` is present and matches pattern `{vendor}.{service}.{action}`
- [x] Validate at least one field is defined
- [x] Validate all `endpoint-id` references in `<action>` exist in `<endpoints>`
- [x] Validate all `options-from` references exist in `<endpoints>`
- [x] Validate all `depends-on` field IDs exist in the same form
- [x] Validate `aria-label` is present on every `<field>` and every `<action>`
- [x] Validate `aria-label` is present on every `<field>` inside `<status-templates>`
- [x] Return `{:error, reason}` with a descriptive message for every validation failure

### Tests

- [x] Test `parse/1` against `priv/lamps/aws_s3_create_bucket.xml` — assert all fields populated correctly
- [x] Test each field type is parsed with correct struct fields
- [x] Test `genie-fill` values map to correct atoms
- [x] Test all validation rules with invalid XML fixtures — one test per rule
- [x] Test that `depends-on` attributes are preserved in `FieldDef`
- [x] Test that `<group>` correctly sets `group_id` on child fields

---

## Slice 3 — GenieLamp Registry

> Stores and serves lamp definitions. Internal lamps loaded from `priv/lamps/`. Third-party lamps registered via Ash action.

- [x] Define `Genie.Lamp.LampRegistry` Ash resource with attributes: `id`, `lamp_id`, `org_id` (nullable — nil means available to all orgs), `xml_source`, `parsed_definition` (`:map` type, stored as JSONB), `enabled`, `inserted_at`, `updated_at`
- [x] Write migration for `LampRegistry`
- [x] Implement `LampRegistry.register/2` Ash create action — parses XML, validates, stores parsed definition
- [x] Implement `LampRegistry.load_active_manifests/1` read action — returns `[%LampDefinition{}]` for a given `org_id`, filtering enabled lamps
- [x] Implement `LampRegistry.fetch_lamp/1` — returns `%LampDefinition{}` by `lamp_id`
- [x] Write Mix task `mix genie.lamps.load` — reads all XML files from `priv/lamps/`, registers each, reports errors
- [x] Run `mix genie.lamps.load` as part of application startup in dev (not prod — use explicit migration step)
- [x] Write unit tests for `register/2` — valid XML succeeds, invalid XML returns error with reason
- [x] Write unit tests for `load_active_manifests/1` — returns only enabled lamps for the correct org
- [x] Write unit test confirming a lamp with an invalid manifest cannot be registered

---

## Slice 4 — GenieLamp Renderer

> Converts a `%LampDefinition{}` into Phoenix.HTML.safe with full ARIA tree. No agent fill yet — renders with default values only.

- [x] Implement `Genie.Lamp.LampRenderer.render/1` as a Phoenix.Component
- [x] Implement `lamp_header/1` component — title, icon placeholder, GenieLamp badge
- [x] Implement `lamp_form/1` component — `role="form"`, `aria-label`, `aria-describedby`, `phx-submit`, `phx-value-lamp-id`
- [x] Implement `render_field/1` dispatcher — pattern matches on `field.type`
- [x] Implement `field_text/1` — `<input type="text">` with `aria-label`, `aria-required`, `aria-describedby`, `pattern`, `maxlength`, fill class
- [x] Implement `field_textarea/1` — `<textarea>` with `rows`, `aria-label`, fill class
- [x] Implement `field_select/1` — `<select>` with `<option selected={...}>` for each option, dynamic options placeholder when `options_from` present, fill class
- [x] Implement `field_radio/1` — `role="radiogroup"` wrapping `role="radio"` buttons with `aria-checked`
- [x] Implement `field_toggle/1` — `role="switch"`, `aria-checked`, `phx-click="lamp_toggle"`, `phx-value-field`, fill class
- [x] Implement `field_number/1` — `<input type="number">` with `min`, `max`, `step`, `aria-label`
- [x] Implement `field_date/1` — `<input type="date">` with computed `min`/`max` from offset days
- [x] Implement `field_checkbox_group/1` — `role="group"` wrapping `role="checkbox"` items with `aria-checked`
- [x] Implement `field_hidden/1` — `aria-hidden="true"`, `aria-label` preserved for agent
- [x] Implement `render_group/1` — `role="group"`, `aria-labelledby`, collapsible with `phx-click="lamp_group_toggle"`
- [x] Implement `fill_badge/1` — renders "context" badge for `:from_context`, "infer" badge for `:infer`, nothing for `:none`
- [x] Implement `lamp_actions/1` — `role="group"` `aria-label="Form actions"`, renders each `%ActionDef{}`
- [x] Implement `render_action/1` — `<button type="submit|button">` with `aria-label`, correct style class
- [x] Implement `depends_on` visibility logic — sets `aria-hidden="true"` and CSS `hidden` class when condition not met
- [x] Implement `fill_class/1` helper — maps genie_fill atom to CSS class string
- [x] Implement status template renderer — `render_status/2` takes `%LampDefinition{}` and JSON result map, finds matching template, interpolates `{variables}` from result map, renders template fields
- [x] Write snapshot test: parse `aws_s3_create_bucket.xml`, render with defaults, assert full HTML output matches saved snapshot
- [x] Write test: all required ARIA attributes present on every rendered field type
- [x] Write test: `depends-on` field is `aria-hidden="true"` when condition not met, visible when met
- [x] Write test: `render_status/2` correctly interpolates `{bucket_name}` in status template aria-label

---

## Slice 5 — Application Bridge

> Secure proxy between Cockpit and lamp backends. No lamp actions wired to UI yet.

- [x] Implement `Genie.Bridge.execute/1` — validates endpoint declaration, retrieves scoped token, interpolates path params, POSTs JSON to lamp backend via `Req`, returns rendered status template HTML
- [x] Implement `Genie.Bridge.fetch_options/2` — GETs options endpoint, maps response using `options_value_key` and `options_label_key`
- [x] Implement `Genie.Bridge.execute_tool/1` — executes Tool call (LLM data gathering), returns raw JSON result
- [x] Implement `Genie.Bridge.Sanitizer.sanitize/1` — strict HTML allowlist (see `REQUIREMENTS.md §6.6`), strips all disallowed elements and attributes, HTML-entity-encodes attribute values
- [x] Implement `Genie.Bridge.VaultClient.get_scoped_token/1` — retrieves temporary scoped credential for the lamp's auth scheme
- [x] Implement endpoint declaration enforcement — reject with `{:error, :undeclared_endpoint}` if `{lamp_id, endpoint_id}` not in registry
- [x] Add `X-Genie-Trace-Id` header to all outbound requests using current OTel trace ID
- [x] Add `X-Genie-Session` header to all outbound requests
- [x] Enforce `timeout_ms` from lamp meta on every Req call
- [x] Write unit test: `execute/1` with a valid declared endpoint succeeds
- [x] Write unit test: `execute/1` with an undeclared endpoint returns `{:error, :undeclared_endpoint}`
- [x] Write unit test: `Sanitizer.sanitize/1` strips `<script>` tags
- [x] Write unit test: `Sanitizer.sanitize/1` strips `javascript:` href values
- [x] Write unit test: `Sanitizer.sanitize/1` strips `on*` event handler attributes
- [x] Write unit test: `Sanitizer.sanitize/1` allows `aria-*` attributes through
- [x] Write unit test: `fetch_options/2` maps response correctly using configured keys

---

## Slice 6 — Conductor — Action Validation

> Ash action pipeline that validates and authorises every lamp action before execution.

- [x] Define `Genie.Conductor.LampAction` Ash resource with attributes: `id`, `lamp_id`, `endpoint_id`, `params` (`:map`), `actor_id`, `session_id`, `requires_approval`, `status`, `oban_job_id`, `inserted_at`
- [x] Write migration for `LampAction`
- [x] Implement `Genie.Conductor.build_action/3` — casts `lamp_id`, `endpoint_id`, `params` through Ash changeset, validates required fields, checks RBAC policy via `Ash.run_action`
- [x] Implement Ash policy on `LampAction`: actor must belong to the lamp's enabled org, actor must have the required role for the lamp's declared permission level
- [x] Implement `Genie.Conductor.execute/1` — calls `AppBridge.execute/1` with validated `%LampAction{}`
- [x] Write unit test: `build_action/3` with valid params and authorised actor returns `{:ok, %LampAction{}}`
- [x] Write unit test: `build_action/3` with unauthorised actor returns `{:error, %Ash.Error.Forbidden{}}`
- [x] Write unit test: `build_action/3` with missing required param returns `{:error, %Ash.Error.Invalid{}}`
- [x] Write unit test: `execute/1` calls Bridge with the correct endpoint

---

## Slice 7 — Oban Workers

> Background job workers. Orchestrator and lamp action execution are decoupled from the LiveView process.

- [x] Configure Oban in `config.exs` with queues: `orchestrator: 5`, `lamp_actions: 10`, `approvals: 5`, `notifications: 5`
- [x] Implement `Genie.Workers.OrchestratorWorker` — Oban worker stub that accepts `session_id`, `user_message`, `actor_id`; logs receipt; returns `:ok`. Full Reactor wiring in Slice 9.
- [x] Implement `Genie.Workers.LampActionWorker` — calls `LampRegistry.fetch_lamp/1`, calls `Conductor.build_action/3`, calls `Bridge.execute/1`, calls `CockpitLive.push_canvas/2` with result HTML or error
- [x] Implement `Genie.Workers.ApprovalWorker` — stub that accepts `action_id`, `approver_id`; on approval re-inserts `OrchestratorWorker` job with approval result; on denial writes to `AuditLog` and calls `CockpitLive.push_error/2`
- [x] Write unit test: `LampActionWorker.perform/1` with a mock Bridge returns `:ok` and calls `push_canvas`
- [x] Write unit test: `LampActionWorker.perform/1` with a Bridge error calls `push_error`
- [x] Write unit test: `ApprovalWorker.perform/1` on denial writes a denied `AuditLog` entry

---

## Slice 8 — Phoenix LiveView Cockpit

> The Cockpit UI wired to the Oban workers. Agent AI not yet connected — interactions work end-to-end with stubbed agent responses.

### LiveView

- [x] Implement `GenieWeb.CockpitLive` with `mount/3` — subscribe to `"canvas:{session_id}"` and `"chat:{session_id}"` PubSub topics, load pinned lamps, assign initial state
- [x] Implement `render/1` — two-panel layout, `role="application"`, left chat panel, right canvas panel with `phx-update="ignore"`, `phx-hook="CanvasHook"`, `aria-live="polite"`
- [x] Implement `handle_event "send_message"` — insert `OrchestratorWorker` Oban job, append user message to chat assigns
- [x] Implement `handle_event "lamp_submit"` — insert `LampActionWorker` Oban job, push `"lamp_loading"` event to canvas
- [x] Implement `handle_event "lamp_toggle"` — update field value in session state, push updated field fragment
- [x] Implement `handle_event "lamp_field_change"` — evaluate `depends-on` conditions, push visibility updates
- [x] Implement `handle_event "lamp_group_toggle"` — toggle group collapsed state, push updated group fragment
- [x] Implement `handle_info {:push_canvas, html}` — `push_event "update_canvas"`
- [x] Implement `handle_info {:push_chat, message}` — append to chat assigns
- [x] Implement `handle_info {:push_error, reason}` — append error message to chat, push error state to canvas
- [x] Implement public `push_canvas/2`, `push_chat/2`, `push_error/2` — `Phoenix.PubSub.broadcast` to session topics

### Canvas JS Hook

- [x] Implement `CanvasHook` in `assets/js/hooks/canvas_hook.js` — `handleEvent "update_canvas"` sets `innerHTML`, `handleEvent "lamp_loading"` sets spinner HTML with correct `role="status"` and `aria-label`
- [x] Register `CanvasHook` in `app.js` LiveView hooks

### Router

- [x] Add authenticated route `GET /cockpit` → `CockpitLive`
- [x] Add webhook route `POST /webhooks/:lamp_id` → `WebhookController` (stub handler for now)
- [x] Add authentication plug — reject unauthenticated requests to `/cockpit`

### Integration test

- [x] Write LiveView integration test: mount Cockpit, send `"send_message"` event, assert `OrchestratorWorker` job inserted
- [x] Write LiveView integration test: broadcast `{:push_canvas, html}` to session topic, assert `push_event "update_canvas"` fired with correct HTML
- [x] Write LiveView integration test: send `"lamp_submit"` event, assert `LampActionWorker` job inserted

---

## Slice 9 — Ash Reactor — Reasoning Loop

> Wires the AI reasoning loop. Requires a configured LLM provider.

### LLM Client

- [ ] Implement `Genie.Orchestrator.LlmClient.call/1` — POST to LLM provider, parse response into `{:ok, {:tool_call | :intent_call | :message, result}}` or `{:error, reason}`
- [ ] Implement `Genie.Orchestrator.LlmClient.fill/1` — POST constrained fill prompt, parse JSON response
- [ ] Configure LLM provider base URL and API key via environment variables
- [ ] Write unit test: `LlmClient.call/1` with a mock HTTP response correctly parses `tool_call` response
- [ ] Write unit test: `LlmClient.call/1` with a mock HTTP response correctly parses `intent_call` response
- [ ] Write unit test: `LlmClient.fill/1` returns a parsed map of field values

### Reactor steps

- [ ] Implement `Steps.ValidateInputStep` — Ash action cast, session load, manifest load, compensate returns auth error
- [ ] Implement `Steps.BuildContextStep` — system prompt from registry, manifest injection, token budget enforcement, compensate retries with trimmed history
- [ ] Implement `Steps.LlmCallStep` — `LlmClient.call/1` with exponential backoff compensate (3 retries)
- [ ] Implement `Steps.ToolExecutionLoopStep` — recursive tool call loop, max 6 iterations guard, compensate injects error into context
- [ ] Implement `Steps.ValidateActionStep` — `Conductor.build_action/3`, Ash policy check, approval job insertion on `requires_approval: true`
- [ ] Implement `Steps.FillUiStep` — partition fields by `genie_fill`, `from-context` deterministic fill, `infer` LLM schema fill, render to HTML string, compensate renders with nil infer values
- [ ] Implement `Steps.PushCockpitStep` — `CockpitLive.push_canvas/2`, `AuditLog` write, undo stores pending UI in session cache
- [ ] Assemble `Genie.Orchestrator.ReasoningLoop` Ash Reactor with all seven steps in order

### Wire OrchestratorWorker

- [ ] Replace `OrchestratorWorker` stub with full Reactor invocation: `Genie.Orchestrator.ReasoningLoop.run(%{session_id:, user_message:, actor:})`

### Tests

- [ ] Write unit test for each Reactor step's `run/3` with mocked dependencies
- [ ] Write unit test for each Reactor step's `compensate/4` or `undo/4`
- [ ] Write unit test: `ToolExecutionLoopStep` fires error after 6 iterations
- [ ] Write unit test: `ValidateActionStep` inserts `ApprovalWorker` job when `requires_approval: true`
- [ ] Write unit test: `FillUiStep` calls LLM only for `:infer` fields, not `:from_context` fields
- [ ] Write integration test: full Reactor run with mocked LLM returns rendered HTML to canvas

---

## Slice 10 — Lamp 1: AWS EC2 Instance Viewer

> First production lamp. Read-only. Proves Bridge HTTP GET, table renderer, dynamic options, on-load trigger.

- [ ] Create `priv/lamps/aws_ec2_list_instances.xml` per XML schema — fields: `region` (`from-context`, `select`, `options-from="load_regions"`), `state` (`infer`, `select`, options: `running|stopped|all`)
- [ ] Add table renderer to `LampRenderer` — `field type="table"` renders `<table role="grid">` with `<th scope="col">` and `<td>` per row, `aria-label` on each column header
- [ ] Register `aws.ec2.list-instances` lamp via `mix genie.lamps.load`
- [ ] Wire `on-load` trigger in `LampActionWorker` — fire `load_regions` endpoint when lamp loads, populate `region` select options via `Bridge.fetch_options/2`
- [ ] Create mock EC2 API endpoint (or configure a real AWS integration test) returning instance list JSON
- [ ] Write status templates: `submitting`, `ready` (table of instances), `failed`
- [ ] Verify: user says "show me running instances in us-east-1", canvas renders EC2 table with region pre-selected
- [ ] Write integration test: lamp loads, `load_regions` endpoint fires, region options populated, table rendered on submit

---

## Slice 11 — Lamp 2: PagerDuty Active Incidents

> Proves proactive agent behaviour — canvas updates on webhook without user action.

- [ ] Create `priv/lamps/pagerduty_incidents.xml` — no user-fillable fields, auto-loads on webhook trigger
- [ ] Implement `GenieWeb.WebhookController.create/2` — verifies HMAC signature, identifies `lamp_id` from path, inserts `LampActionWorker` job with `trigger: :webhook`
- [ ] Add webhook signature verification — reject requests with invalid `X-PagerDuty-Signature` header
- [ ] Wire webhook trigger in `LampActionWorker` — on `:webhook` trigger, fetch incident data from Bridge, push rendered HTML to all active sessions for the org
- [ ] Add incident severity badge renderer to `LampRenderer` — `field type="banner"` with `style` mapped to CSS class
- [ ] Create mock PagerDuty webhook payload fixture
- [ ] Verify: POST mock webhook to `/webhooks/pagerduty`, canvas in all active org sessions updates with incident list without user interaction
- [ ] Write integration test: webhook POST → `LampActionWorker` → `push_canvas` broadcast to correct org sessions

---

## Slice 12 — Lamp 3: AWS S3 Bucket Creator

> The centrepiece demo lamp. Full write path, from-context fill, approval workflow, poll-status.

- [ ] Create `priv/lamps/aws_s3_create_bucket.xml` — full schema per `REQUIREMENTS.md §5` with all field types, `requires-approval: true`, three endpoints: `load_regions`, `create_bucket`, `poll_status`
- [ ] Implement poll-status loop in `LampActionWorker` — after submit, poll `poll_status` endpoint at `poll_interval_ms`, stop when `poll_until` condition met or timeout reached, push status template update on each poll result
- [ ] Implement approval UI — when `ValidateActionStep` returns `{:pending_approval, job_id}`, push `pending-approval` status template to canvas, push "Waiting for approval from @{approver}" to chat
- [ ] Implement approver notification — `push_chat` with approval request to approver's active session
- [ ] Implement approval accept/deny LiveView events — `handle_event "approve_action"` and `handle_event "deny_action"` trigger `ApprovalWorker` with decision
- [ ] Wire `from-context` fill: `region` and `org_id` extracted from conversation context entities map without LLM call
- [ ] Wire `infer` fill: `bucket_name`, `access`, `versioning` sent to LLM as typed schema
- [ ] Verify demo sequence: user types "Create a private versioned bucket called acme-prod-assets in us-east-1" → form pre-filled → approval → bucket created → console link shown
- [ ] Write integration test: full demo sequence with mocked LLM and Bridge — assert each status template rendered in correct order
- [ ] Write integration test: `from-context` fields populated without LLM call
- [ ] Write integration test: poll-status loop terminates on `status=ready`
- [ ] Write integration test: approval denial writes denied `AuditLog` entry and notifies requester

---

## Slice 13 — Lamp 4: GitHub Pull Request Viewer

> Proves list→detail navigation within a single lamp.

- [ ] Create `priv/lamps/github_pull_requests.xml` — fields: `repo` (`from-context`), `state` (`infer`, options: `open|closed|all`), results table with clickable rows
- [ ] Add `row-click` action type to `LampRenderer` — renders `<tr>` with `phx-click="lamp_row_select"`, `phx-value-row-id`, `role="row"`, `aria-selected`
- [ ] Implement `handle_event "lamp_row_select"` in `CockpitLive` — inserts `LampActionWorker` job for `fetch_pr_detail` endpoint with selected row ID
- [ ] Add detail panel renderer to `LampRenderer` — `field type="detail-panel"` renders key-value pairs with correct ARIA labelling
- [ ] Create `priv/lamps/github_pull_requests.xml` status templates: `submitting`, `ready-list` (PR table), `ready-detail` (PR detail panel), `failed`
- [ ] Verify: user says "show me open PRs for the platform team", PR list renders, user clicks a row, detail panel renders
- [ ] Write integration test: row click → detail fetch → detail panel rendered in canvas

---

## Slice 14 — Lamp 5: Kubernetes Pod Restarter

> Final demo lamp. Proves checkbox-group infer pre-selection, live poll status, write with approval.

- [ ] Create `priv/lamps/kubernetes_restart_pods.xml` — fields: `namespace` (`from-context`), `selected_pods` (`infer`, `checkbox-group`, `options-from="list_pods"`), `requires-approval: true`
- [ ] Implement `infer` fill for `checkbox-group` — LLM schema includes available options, LLM returns array of selected values, renderer sets `aria-checked="true"` on matching options
- [ ] Implement multi-select checkbox interaction in `CockpitLive` — `handle_event "lamp_checkbox_toggle"` updates selection state server-side, re-renders affected checkboxes
- [ ] Wire `on-load` trigger for `list_pods` endpoint — populates `selected_pods` options with pods from the namespace, pre-selects crashed pods via `infer`
- [ ] Add restart status poll — polls pod restart status after action, updates canvas with pod state per pod (pending → running)
- [ ] Verify: user says "restart the crashed pods in the payments namespace", pods listed, crashed pods pre-checked, approval requested, restart confirmed, status updates per pod
- [ ] Write integration test: `infer` fill for `checkbox-group` correctly pre-selects crashed pods
- [ ] Write integration test: poll-status updates canvas for each pod transition individually

---

## Slice 15 — Demo Hardening

> Makes the demo reliable, repeatable, and failure-proof for a live audience.

- [ ] Create demo seed script `mix genie.demo.seed` — creates demo org, demo user, demo session with pre-loaded conversation context containing `region=us-east-1`, `org_id`, `env=prod`
- [ ] Pre-approve all lamp actions for the demo actor — insert bypass rule in `ApprovalWorker` for `actor_id=demo_user`
- [ ] Fix `bucket_name` inference for demo context — seed conversation with explicit "acme-prod-assets" mention so `infer` always resolves identically
- [ ] Suppress stack traces in all Bridge error responses — return friendly `"Service temporarily unavailable"` with trace ID only
- [ ] Add Bridge request/response logging in dev mode — log full request and response for every Bridge call
- [ ] Add a health check endpoint `GET /health` returning `200 OK` with Oban queue depths and DB connectivity status
- [ ] Verify the full demo sequence runs five times consecutively without failure or variation
- [ ] Document exact demo script in `priv/demo/DEMO_SCRIPT.md` — precise user sentences that produce correct fills for each lamp

---

## Slice 16 — Observability and Audit

> Full OpenTelemetry instrumentation and audit trail completeness verification.

- [ ] Add OTel span `"Genie.message.received"` in `CockpitLive.handle_event "send_message"`
- [ ] Add OTel span `"Genie.reactor.start"` at Reactor entry with `session_id` and `actor_id` attributes
- [ ] Add OTel span `"Genie.llm.call"` in `LlmCallStep` with `token_count_input`, `token_count_output` attributes
- [ ] Add OTel span `"Genie.tool.execute"` in `ToolExecutionLoopStep` with `tool_name`, `iteration` attributes
- [ ] Add OTel span `"Genie.bridge.request"` in `AppBridge.execute/1` with `lamp_id`, `endpoint_id`, `status_code`, `duration_ms` attributes
- [ ] Add OTel span `"Genie.renderer.render"` in `FillUiStep` with `lamp_id`, `field_count`, `infer_count`, `context_count` attributes
- [ ] Add OTel span `"Genie.canvas.push"` in `PushCockpitStep` with `session_id`, `lamp_id` attributes
- [ ] Propagate `X-Genie-Trace-Id` header on all Bridge outbound requests using current span's trace ID
- [ ] Verify `AuditLog` entry is written for every completed lamp action across all five lamps
- [ ] Verify `AuditLog` entry is written for every denied lamp action
- [ ] Write test: a single user message produces a single trace ID that appears in the `AuditLog` entry, the `LampAction` record, and the OTel span attributes
- [ ] Configure OTel exporter for development — print spans to stdout in dev environment

---

## Slice 17 — Security Hardening

> Systematic verification of all security requirements from `REQUIREMENTS.md §8`.

- [ ] Write security test: browser cannot directly call a lamp backend URL — all paths route through Bridge
- [ ] Write security test: Bridge rejects a call to an endpoint not declared in the lamp's XML manifest
- [ ] Write security test: `Sanitizer` rejects HTML containing `<script>` in all positions (element, attribute, data URI)
- [ ] Write security test: `Sanitizer` rejects HTML containing `javascript:` in `href` attributes
- [ ] Write security test: `Sanitizer` rejects HTML containing `onerror`, `onclick`, and all `on*` attributes
- [ ] Write security test: `FillUiStep` LLM fill prompt receives typed JSON schema only — no HTML, no XML, no raw ARIA attributes
- [ ] Write security test: LLM fill with a poisoned `aria-label` value containing an instruction does not execute that instruction
- [ ] Write security test: actor from Org A cannot trigger a lamp action on behalf of Org B
- [ ] Write security test: `AuditLog` Ash resource rejects update and destroy actions at the policy layer
- [ ] Write security test: a lamp with `destructive="true"` action triggers a confirmation dialog before `LampActionWorker` is inserted
- [ ] Run `mix credo --strict` and resolve all warnings
- [ ] Run `mix dialyzer` and resolve all type errors

---

## Slice 18 — Definition of Done Verification

> Final check that every requirement in `REQUIREMENTS.md §14` is satisfied across the whole codebase.

- [ ] `mix compile --warnings-as-errors` passes with zero warnings
- [ ] All Ash actions have at least one policy test covering authorised and unauthorised actors
- [ ] All Reactor steps have unit tests for both `run/3` and `compensate/4` or `undo/4`
- [ ] Rendered HTML for all five lamps validates against WCAG 2.1 AA using an automated checker (axe-core or equivalent)
- [ ] ARIA tree produced by `LampRenderer` for each lamp matches saved test fixture exactly
- [ ] Bridge rejects all calls to undeclared endpoints — verified by security tests in Slice 17
- [ ] `AuditLog` entry written for every completed lamp action — verified by Slice 16 tests
- [ ] OTel trace spans present and linked for the full action chain — verified by Slice 16 tests
- [ ] `mix test` passes with zero failures and zero skipped tests
- [ ] Test coverage above 80% across the `genie` app (measured by `excoveralls`)
- [ ] Demo sequence from `DEMO_SCRIPT.md` runs without failure

---

## Progress Summary

| Slice | Name                             | Status |
| ----- | -------------------------------- | ------ |
| 0     | Project Scaffold                 | `[ ]`  |
| 1     | Ash Domain Foundation            | `[x]`  |
| 2     | GenieLamp XML Parser             | `[x]`  |
| 3     | GenieLamp Registry               | `[x]`  |
| 4     | GenieLamp Renderer               | `[x]`  |
| 5     | Application Bridge               | `[x]`  |
| 6     | Conductor — Action Validation    | `[x]`  |
| 7     | Oban Workers                     | `[x]`  |
| 8     | Phoenix LiveView Cockpit         | `[x]`  |
| 9     | Ash Reactor — Reasoning Loop     | `[ ]`  |
| 10    | Lamp 1: EC2 Instance Viewer      | `[ ]`  |
| 11    | Lamp 2: PagerDuty Incidents      | `[ ]`  |
| 12    | Lamp 3: S3 Bucket Creator        | `[ ]`  |
| 13    | Lamp 4: GitHub PR Viewer         | `[ ]`  |
| 14    | Lamp 5: Kubernetes Pod Restarter | `[ ]`  |
| 15    | Demo Hardening                   | `[ ]`  |
| 16    | Observability and Audit          | `[ ]`  |
| 17    | Security Hardening               | `[ ]`  |
| 18    | Definition of Done Verification  | `[ ]`  |
