**Read references/REQUIREMENTS.md to understand this application**
**Read references/ROADMAP.md to implement the application tasks**

## 0. IMPORTANT POINTS

- ASK QUESTIONS IF REQUIREMENTS ARE NOT CLEAR.
- ASK QUESTIONS IF REQUIREMENTS ARE NOT CLEAR.
- KEEP YOUR RESPONSES SHORT.

## 1. Product Vision

Genie is an **agentic UI platform** — not a chatbot. The fundamental thesis is:

> Chat interfaces are probabilistic. Structured UI is deterministic. Genie combines both: natural language to discover and invoke tools, purpose-built UI to interact with them safely.

The agent is treated as a **visually impaired user navigating via screen reader**. It reads the accessibility tree — `role`, `aria-label`, `aria-checked`, `aria-describedby` — not raw HTML, not pixel screenshots, not inferred visual structure. Every architectural decision flows from this model.

The platform solves **tool sprawl** in DevOps and platform engineering. Engineers context-switch across 8–15 tools per incident. Genie provides a single, governed, auditable interface to all of them.

---

## 2. Core Concepts

| Term                   | Definition                                                                                                        |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Cockpit**            | The primary Genie UI. Two panels: chat (left) and canvas (right).                                                 |
| **GenieLamp**          | A self-contained tool integration. Defined by an XML file and a JSON API endpoint.                                |
| **Canvas**             | The right panel of the Cockpit. Renders the active GenieLamp UI.                                                  |
| **LampDefinition**     | The parsed Elixir struct representing a GenieLamp's XML definition.                                               |
| **Application Bridge** | The secure proxy between the Cockpit and all GenieLamp backends. The browser never calls a lamp backend directly. |
| **Conductor**          | The Ash action pipeline that validates, authorises, and executes every lamp action.                               |
| **Orchestrator**       | The Ash Reactor workflow that manages the AI reasoning loop.                                                      |
| **SIP**                | Semantic Interface Protocol. `genie-fill` attributes in the XML that tell the agent how to populate each field.   |
| **ARIA Tree**          | The serialised accessibility tree of the rendered lamp. This is what the agent reads — never raw HTML.            |
| **Approval Workflow**  | An Ash Oban job that suspends execution until a designated approver responds.                                     |

---

## ELIXIR DEPS

- Elixir libs are added as deps in mix.exs
- The libaries are added to /deps/<library_name> folder.
- You can check the documentation of library under /deps/<library_name>/README.md file.
- If you have any question about using a library, you should check the README.md of the library first, then the code inside for deeper look.

<!-- usage-rules-start -->
<!-- usage_rules-start -->

## usage_rules usage

_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should _thoroughly_ consult before taking any
action. These usage rules contain guidelines and rules _directly from the package authors_.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```

## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```

<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->

## usage_rules:elixir usage

# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid

- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->

## usage_rules:otp usage

# OTP Usage Rules

## GenServer Best Practices

- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication

- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance

- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async

- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
