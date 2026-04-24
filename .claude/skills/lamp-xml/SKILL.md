---
name: lamp-xml
description: "Use this skill when creating or editing GenieLamp XML definition files in priv/lamps/. Covers the full schema, validation rules, ARIA requirements, SIP (genie-fill) strategy, and field type reference."
---

# GenieLamp XML Authoring

Lamp XML files live in `priv/lamps/<vendor>_<service>_<action>.xml`.
They are parsed by `LampParser` (SAX) into `LampDefinition` structs and validated at parse time.
Any validation failure returns `{:error, reason}` — the lamp will not load.

A lamp is **two files** — an XML definition (this skill) plus an Elixir handler
module at `lib/genie/lamps/<vendor>/<service>_<action>.ex` that serves each
declared endpoint in-process. Use `mix genie.lamp.new vendor.service.action` to
scaffold both. For the handler side, see
`references/docs/LAMP_DEVELOPMENT.md`.

**Runtime choice (in `<meta>`):**

- `inline` (recommended for first-party lamps) — an Elixir module serves the
  endpoints. No HTTP backend, no credentials.
- `remote` (default if `<runtime>` is omitted) — endpoints are HTTP URLs under
  `<base-url>`; the Bridge proxies to them with Vault-issued tokens.

---

## Skeleton

```xml
<?xml version="1.0" encoding="UTF-8"?>
<lamp
  id="{vendor}.{service}.{action}"
  version="1.0"
  category="{storage|compute|ci-cd|monitoring|incident|repository|source-control|incidents}"
  vendor="{vendor-slug}">

  <meta>…</meta>
  <endpoints>…</endpoints>
  <ui>…</ui>
  <actions>…</actions>
  <status-templates>…</status-templates>

</lamp>
```

**`id` format is validated**: must match `{vendor}.{service}.{action}` — exactly three dot-separated segments, no spaces.

---

## `<meta>`

### Inline runtime (recommended)

```xml
<meta>
  <title>Human-readable title</title>
  <description>One to three sentences. Used in agent context and marketplace.</description>
  <icon>vendor-slug</icon>
  <tags>aws,compute,ec2,instances</tags>

  <requires-approval>false</requires-approval>
  <!-- If true, add: -->
  <approval-policy>default</approval-policy>

  <destructive>false</destructive>
  <audit>true</audit>

  <runtime>inline</runtime>
  <handler>Genie.Lamps.AWS.EC2ListInstances</handler>

  <timeout-ms>10000</timeout-ms>
</meta>
```

### Remote runtime (HTTP backend)

```xml
<meta>
  <!-- …same fields as above, except: -->
  <runtime>remote</runtime>
  <base-url>https://api.partner.com/genie</base-url>
  <auth-scheme>bearer</auth-scheme>   <!-- bearer | api-key -->
  <timeout-ms>10000</timeout-ms>
</meta>
```

- `audit` should be `true` for all lamps
- `destructive` should be `true` only if the action mutates/deletes real infrastructure
- `requires-approval` + `approval-policy` go together; omit `approval-policy` when `requires-approval` is false
- **`runtime=inline` requires `<handler>`** — a fully-qualified Elixir module
  name. `<base-url>` and `<auth-scheme>` are unused (omit them).
- **`runtime=remote` (or omitted) requires `<base-url>`** — `<handler>` is unused.

---

## `<endpoints>`

```xml
<endpoints>
  <!-- Populates a select field's options on form load -->
  <endpoint
    id="load_regions"
    method="GET"
    path="/aws/regions"
    trigger="on-load"
    fills-field="region"/>

  <!-- Triggered by a primary action submit -->
  <endpoint
    id="create_thing"
    method="POST"
    path="/service/things"
    trigger="on-submit"
    action-id="submit_create"
    timeout-ms="30000">
    <response-schema>
      <key name="state" type="string" required="true"/>
      <key name="thing_id" type="string"/>
      <key name="error_message" type="string"/>
    </response-schema>
  </endpoint>

  <!-- Polls after submission until condition met -->
  <endpoint
    id="poll_status"
    method="GET"
    path="/service/things/{thing_id}/status"
    trigger="on-complete"
    poll-interval-ms="2000"
    poll-until="status=ready|status=failed"
    timeout-ms="60000">
    <response-schema>
      <key name="state" type="string" required="true"/>
      <key name="status" type="string" required="true"/>
      <key name="thing_id" type="string"/>
      <key name="console_url" type="string"/>
    </response-schema>
  </endpoint>

  <!-- Webhook-driven — no user action needed -->
  <endpoint
    id="list_incidents"
    method="GET"
    path="/pagerduty/incidents"
    trigger="webhook">
    <response-schema>
      <key name="state" type="string"/>
      <key name="incidents" type="array"/>
      <key name="count" type="number"/>
    </response-schema>
  </endpoint>
</endpoints>
```

**Trigger values:** `on-load` | `on-submit` | `on-complete` | `on-change` | `webhook`

- `fills-field` — only for `on-load` endpoints; names the `select` field whose options come from the response
- `action-id` — required when `trigger="on-submit"`; must match an `<action id="…">`
- Path params like `{thing_id}` must resolve to a form field id. For
  `row-click` table endpoints the synthetic `{id}` param is also accepted
  (it's populated from the clicked row's `row-id-key`).

**Critical:** Every endpoint used by an action or `options-from` must be declared here. Undeclared endpoints are rejected.

### `<response-schema>` — declare what the endpoint returns

Each endpoint should declare the shape of its response via child `<key>` elements.

- **Inline runtime** — the Bridge enforces all `required="true"` keys on the
  map your handler returns. Missing required keys surface as
  `{:error, {:missing_required_response_keys, [...]}}`.
- **Both runtimes** — any `<key>` name becomes a valid `{placeholder}` in
  status-template `aria-label`/`value`/`href`. Once any endpoint declares a
  `<response-schema>`, the parser runs strict placeholder validation across
  *all* status templates and rejects unknown placeholders at load time.
- `type` is documentary: `string | number | boolean | array | object`.
- `state`, `error_message`, `error`, and `count` are always accepted as
  placeholders without needing to be declared (conventional keys), but
  declaring them in the schema is still good practice.

---

## `<ui>` — Form and Fields

```xml
<ui>
  <form
    aria-label="Descriptive form label"
    aria-describedby="form-description-id">

    <description id="form-description-id">
      Plain text description of the form's purpose.
    </description>

    <!-- fields and groups here -->

  </form>
</ui>
```

### Field types

| type             | Use for                                            |
| ---------------- | -------------------------------------------------- |
| `text`           | Free-form string input                             |
| `textarea`       | Multi-line text (`rows` attr)                      |
| `select`         | Dropdown, static or dynamic options                |
| `radio`          | Mutually exclusive options (always visible)        |
| `toggle`         | Boolean on/off switch                              |
| `number`         | Numeric input (`min`, `max`, `step`)               |
| `date`           | Date picker (`min-offset-days`, `max-offset-days`) |
| `checkbox-group` | Multiple selections                                |
| `hidden`         | System value, never shown to user                  |

### Common field attributes

```xml
<field
  id="field_id"
  type="text"
  label="Visible Label"
  aria-label="Specific unambiguous description for the agent"
  aria-describedby="hint-field-id"
  genie-fill="from-context|infer|none"
  required="true"
  default="default_value"
  placeholder="placeholder text"/>
<hint id="hint-field-id">Helper text shown below the field.</hint>
```

### Type-specific attributes

```xml
<!-- text -->
pattern="^[a-z0-9\-]+$"
max-length="63"

<!-- number -->
min="0"
max="3650"
step="1"

<!-- date -->
min-offset-days="-30"
max-offset-days="365"

<!-- textarea -->
rows="6"

<!-- select with dynamic options from an endpoint -->
options-from="load_regions"
options-value-key="code"
options-label-key="name"

<!-- select/radio/checkbox-group with static options -->
<option value="running" label="Running" description="Only running instances"/>
```

### Conditional visibility (`depends-on`)

```xml
<field
  id="kms_key_id"
  type="text"
  label="KMS Key ID"
  aria-label="AWS KMS key ARN, required when encryption type is SSE-KMS"
  genie-fill="none"
  depends-on="encryption_type"
  depends-on-value="SSE-KMS"
  depends-on-behavior="show"/>
```

`depends-on-behavior` values: `show` | `hide` | `enable` | `disable`

`depends-on-value` supports pipe-separated alternatives: `"value1|value2"`

### Groups (collapsible sections)

```xml
<group
  id="advanced_config"
  label="Advanced Configuration"
  aria-label="Advanced bucket configuration options"
  collapsible="true">

  <field id="…" …/>
</group>
```

Fields inside a `<group>` automatically get `group_id` set to the group's `id`.

---

## `<actions>`

```xml
<actions>
  <action
    id="submit_create"
    label="Create Bucket"
    aria-label="Submit form to create the S3 bucket with the configured settings"
    style="primary"
    endpoint-id="create_bucket"
    destructive="false"
    behavior="submit"/>

  <action
    id="reset"
    label="Reset"
    aria-label="Reset all form fields to their default values"
    style="secondary"
    behavior="reset-form"/>
</actions>
```

- `style`: `primary` | `secondary` | `ghost` | `danger`
- `behavior`: `submit` | `reset-form` | `cancel`
- `endpoint-id` is required when `behavior="submit"`; must reference a declared endpoint
- **Validation rule:** if any field has `required="true"`, at least one action must have `style="primary"`

---

## `<status-templates>`

Status templates render read-only output after an action completes. They replace the form UI.

```xml
<status-templates>

  <template state="submitting">
    <field type="spinner"
      label="Creating bucket..."
      aria-label="Creating S3 bucket {bucket_name}, please wait"
      style="info"/>
  </template>

  <template state="pending-approval">
    <field type="banner"
      label="Pending Approval"
      aria-label="Bucket creation for {bucket_name} is pending approval"
      style="warning"
      value="Waiting for approval to create bucket {bucket_name}"/>
  </template>

  <template state="ready">
    <field type="banner"
      label="Bucket Created"
      aria-label="S3 bucket {bucket_name} was successfully created in {region}"
      style="success"
      value="Bucket {bucket_name} created successfully"/>
    <field type="link"
      label="Open in Console"
      aria-label="Open S3 bucket {bucket_name} in the AWS Management Console"
      href="{console_url}"
      value="View in AWS Console"/>
    <field type="table"
      label="Result"
      aria-label="List of items in {region}"
      value-key="items">
      <column key="id" label="ID"/>
      <column key="name" label="Name"/>
    </field>
  </template>

  <template state="failed">
    <field type="banner"
      label="Failed"
      aria-label="Operation failed: {error_message}"
      style="error"
      value="{error_message}"/>
  </template>

</status-templates>
```

**Built-in states:** `submitting` | `pending-approval` | `ready` | `failed` | `loading` | `no_incidents`
Custom state names are allowed (e.g. `ready-list`, `ready-detail`).

**Template field types:**

- `spinner` — loading indicator
- `banner` — coloured status message (`style`: `info`|`success`|`warning`|`error`)
- `link` — clickable URL (`href` supports `{interpolation}`)
- `table` — data table (`value-key` names the response JSON key; add `<column>` children)
- `detail-panel` — key/value detail view (same structure as table)
- `action` — inline action button (`action-id` references an `<action>`)

`{interpolation}` in `aria-label` and `value` uses submitted form field ids or response JSON keys.

---

## SIP — The `genie-fill` Attribute

This is the most critical attribute. It controls how the AI agent populates each field.

| Value          | Behaviour                                                                              | LLM?  | When to use                                                         |
| -------------- | -------------------------------------------------------------------------------------- | ----- | ------------------------------------------------------------------- |
| `from-context` | Value extracted directly from the conversation context entities map. Deterministic.    | Never | Region, account ID, environment — things the user stated explicitly |
| `infer`        | Field sent to LLM as a typed schema entry. LLM infers value from conversation context. | Yes   | Values implied but not stated — access policy from "private bucket" |
| `none`         | Field left empty. User must fill manually.                                             | Never | Values the system cannot know — KMS key ARNs, custom tags           |

**Rules:**

- Always prefer `from-context` over `infer` when unambiguous
- `hidden` fields must always use `from-context` — they are system values, never inferred
- `genie-fill` is optional; omit it on status-template fields (they are output-only)

---

## ARIA Rules (non-negotiable)

Every `<field>` in `<ui>` and every `<action>` and every `<field>` in `<status-templates>` **must** have `aria-label`. The validator will reject the lamp if any are missing.

**Good `aria-label`:**

- Unique within the form
- Specific enough to be unambiguous without visual context
- Includes constraints: `"S3 bucket name, must be globally unique, lowercase letters and hyphens only, 3-63 characters"`
- Status template fields include interpolated context: `"S3 bucket {bucket_name} created in {region}"`

**Bad `aria-label`:**

- `"Name"` — too generic
- `"Region"` — ambiguous
- Duplicated across fields

---

## Validation Checklist

The parser runs these checks and returns `{:error, reason}` on failure:

- [ ] `id` matches `{vendor}.{service}.{action}` pattern
- [ ] At least one `<field>` exists in `<ui>`
- [ ] Every action's `endpoint-id` references a declared endpoint
- [ ] Every field's `options-from` references a declared endpoint
- [ ] Every field's `depends-on` references another declared field id
- [ ] Every `<field>` and `<action>` has `aria-label`
- [ ] Every `<field>` in every `<template>` has `aria-label`
- [ ] `genie-fill` is one of `from-context`, `infer`, `none` (or absent)
- [ ] If any field is `required="true"`, at least one action has `style="primary"`
- [ ] Every endpoint `path` `{param}` resolves to a form field id (or `id` for
      row-click endpoints)
- [ ] Every status-template `{placeholder}` resolves to a form field id, a
      declared `<response-schema>` key, or a conventional key (`state`,
      `error_message`, `error`, `count`) — strict when any endpoint declares
      `<response-schema>`; warn otherwise
- [ ] Status-template state names are slug-safe (`[a-z0-9][a-z0-9_-]*`) and at
      least one positive state exists (`ready`, `success`, `ready-*`, or `no_*`)
- [ ] `options-value-key` and `options-label-key` are set together (both or neither)
- [ ] `runtime=inline` declares `<handler>`; `runtime=remote` (or unset)
      declares `<base-url>`

---

## Companion handler (inline lamps)

Every `runtime=inline` lamp has a paired Elixir module at
`lib/genie/lamps/<vendor>/<service>_<action>.ex` that implements the
`Genie.Lamp.Handler` behaviour. The `@before_compile` hook reads this XML
at compile time and diffs the XML's endpoint ids against the handler's
`@endpoint` attributes — missing or extra clauses emit `IO.warn/2`
(promoted to a compile error under `--warnings-as-errors`).

Skeleton — one `@endpoint`-tagged clause per declared endpoint:

```elixir
defmodule Genie.Lamps.AWS.EC2ListInstances do
  use Genie.Lamp.Handler, lamp_id: "aws.ec2.list-instances"

  @endpoint "load_regions"
  def handle_endpoint("load_regions", _params, _ctx),
    do: {:ok, [%{"code" => "us-east-1", "name" => "US East"}]}

  @endpoint "list_instances"
  def handle_endpoint("list_instances", params, _ctx),
    do: {:ok, %{"state" => "ready", "region" => params["region"], "instances" => [...]}}
end
```

`mix genie.lamp.new <vendor>.<service>.<action>` scaffolds both files together.
For the full handler contract (Context struct, response-shape enforcement,
testing patterns), see `references/docs/LAMP_DEVELOPMENT.md`.

---

## Examples

Five reference lamps ship in `priv/lamps/`:

| File                         | Pattern illustrated                                                                 |
| ---------------------------- | ----------------------------------------------------------------------------------- |
| `aws_ec2_list_instances.xml` | `on-load` endpoint populates a select, `on-submit` list action, table result        |
| `aws_s3_create_bucket.xml`   | Requires-approval, collapsible group, `depends-on`, polling, multiple status states |
| `elixir_process_list.xml`    | Introspection-only lamp, `ready-list` + `ready-detail` states, detail-panel         |
| `github_pull_requests.xml`   | Two submit actions, `ready-list` + `ready-detail` states, `row-click` table         |
| `pagerduty_incidents.xml`    | Webhook-driven, no user action, hidden field                                        |

All five are `runtime=inline` — their handler modules live under
`lib/genie/lamps/<vendor>/`.
