# Genie

Genie is an **agentic UI platform** for DevOps and platform engineering. Natural
language discovers and invokes tools; purpose-built UI lets engineers interact
with them safely. See [`references/docs/REQUIREMENTS.md`](references/docs/REQUIREMENTS.md)
for the full product vision and architecture.

---

## Running locally

* Run `mix setup` to install dependencies and prepare the database.
* Start the Phoenix endpoint with `mix phx.server` (or `iex -S mix phx.server`).
* Visit [`localhost:4000`](http://localhost:4000).

---

## Developing a new lamp

A **GenieLamp** is a tool integration — two files, generated together:

1. `priv/lamps/<vendor>_<service>_<action>.xml` — declarative definition
   (form, endpoints, status templates).
2. `lib/genie/lamps/<vendor>/<service>_<action>.ex` — Elixir handler module
   that serves each endpoint in-process.

**Quick start:**

```sh
mix genie.lamp.new aws.lambda.invoke   # scaffolds XML + handler + test
# edit the XML and handler, then:
mix compile --warnings-as-errors       # catches missing @endpoint clauses
mix genie.lamp.verify                  # full XML / handler contract check
mix test test/genie/lamps/aws/lambda_invoke_test.exs
mix genie.lamps.load                   # register into the runtime
```

**Full guide:** [`references/docs/LAMP_DEVELOPMENT.md`](references/docs/LAMP_DEVELOPMENT.md)
— XML anatomy, handler callback contract, Context struct, testing patterns
(including the `lamp_handler_overrides` test hook), pre-merge checklist, and
troubleshooting.

**Spec reference:** [`references/docs/REQUIREMENTS.md`](references/docs/REQUIREMENTS.md)
— full XML schema, validators, security requirements, approval workflow.

---

## Learn more about Phoenix

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
