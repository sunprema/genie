defmodule Genie.Orchestrator.Steps.BuildContextStep do
  @moduledoc """
  Step 2: Assembles the LLM context from conversation history and lamp manifests.

  Builds:
  - A ReqLLM.Context from the last 20 conversation turns plus a system prompt
  - A tools list with one `invoke_lamp` intent tool and data-gathering tools per lamp
  - A tool_registry mapping tool name → {lamp_id, endpoint_id}
  """
  use Reactor.Step

  alias Genie.Bridge
  alias Genie.Conversation.Turn
  alias Genie.Lamp.LampDefinition
  alias ReqLLM.Context

  @max_turns 20

  @impl Reactor.Step
  def run(%{session: session, manifests: manifests, user_message: user_message}, _context, _options) do
    manifests = Enum.map(manifests, &Bridge.populate_options/1)

    with {:ok, turns} <- load_recent_turns(session.id) do
      {tools, tool_registry} = build_tools(manifests)
      system_prompt = build_system_prompt(manifests)

      messages = [Context.system(system_prompt) | build_history_messages(turns)]
      llm_context = Context.new(messages) |> Context.append(Context.user(user_message))

      {:ok,
       %{
         llm_context: llm_context,
         tools: tools,
         tool_registry: tool_registry
       }}
    end
  end

  @impl Reactor.Step
  def compensate(_reason, _arguments, _context, _options), do: :ok

  defp load_recent_turns(session_id) do
    Turn
    |> Ash.Query.for_read(:recent_turns, %{session_id: session_id, limit: @max_turns})
    |> Ash.read(authorize?: false)
  end

  defp build_history_messages(turns) do
    turns
    |> Enum.reverse()
    |> Enum.map(fn turn ->
      case turn.role do
        :user -> Context.user(turn.content)
        :agent -> Context.assistant(turn.content)
      end
    end)
  end

  defp invokable?(lamp) do
    Enum.any?(lamp.endpoints || [], &(&1.trigger == :on_submit))
  end

  defp build_tools(manifests) do
    intent_tool = build_invoke_lamp_tool(manifests)
    {data_tools, registry} = build_data_tools(manifests)

    {[intent_tool | data_tools], registry}
  end

  defp build_invoke_lamp_tool(manifests) do
    invokable = Enum.filter(manifests, &invokable?/1)

    lamp_descriptions =
      invokable
      |> Enum.map_join("\n\n", fn %LampDefinition{id: id, meta: meta, endpoints: endpoints, fields: fields} ->
        title = meta && meta.title
        desc = meta && meta.description

        submit_endpoints =
          (endpoints || [])
          |> Enum.filter(&(&1.trigger == :on_submit))
          |> Enum.map_join(", ", & &1.id)

        field_lines =
          (fields || [])
          |> Enum.reject(&(&1.type == :hidden))
          |> Enum.map_join("\n    ", &describe_field/1)

        field_note = if field_lines == "", do: "(no user-visible fields)", else: "params:\n    #{field_lines}"

        "lamp_id=\"#{id}\" (#{title})\n  description: #{desc}\n  endpoint_id: #{submit_endpoints}\n  #{field_note}"
      end)

    lamp_ids = invokable |> Enum.map_join(", ", & &1.id)

    ReqLLM.tool(
      name: "invoke_lamp",
      description: """
      Invoke a GenieLamp tool immediately when the user's intent is clear.

      IMPORTANT: Call this tool right away — do NOT ask clarifying questions first.
      In the `params` map, include any field value the user's message clearly implies.
      For select/radio fields use the exact value codes listed, never the labels.
      Fields you cannot infer can be omitted — the form will let the user fill them.

      lamp_id MUST be one of: #{lamp_ids}

      Available lamps:
      #{lamp_descriptions}
      """,
      parameter_schema: [
        lamp_id: [type: :string, required: true, doc: "REQUIRED. One of: #{lamp_ids}"],
        endpoint_id: [type: :string, required: true, doc: "REQUIRED. The exact endpoint_id shown above"],
        params: [type: :map, required: false, doc: "Map of field_id → value. Use exact option codes for select/radio."]
      ],
      callback: fn _args -> {:ok, "handled by Genie Reactor"} end
    )
  end

  defp describe_field(field) do
    label = field.label || field.id
    required = if field.required, do: " [required]", else: ""

    type_hint =
      case field.type do
        type when type in [:select, :radio] ->
          codes =
            (field.options || [])
            |> Enum.map(fn opt -> "#{opt.value}=\"#{opt.label}\"" end)
            |> Enum.join(", ")

          if codes == "", do: "(#{field.type}, no codes available)", else: "(#{field.type}; values: #{codes})"

        :checkbox_group ->
          codes =
            (field.options || [])
            |> Enum.map_join(", ", & &1.value)

          if codes == "", do: "(checkbox_group)", else: "(checkbox_group; values: #{codes})"

        other ->
          "(#{other})"
      end

    "- #{field.id}: #{label}#{required} #{type_hint}"
  end

  defp build_data_tools(manifests) do
    Enum.reduce(manifests, {[], %{}}, fn %LampDefinition{id: lamp_id, endpoints: endpoints}, {tools, registry} ->
      data_endpoints = Enum.filter(endpoints || [], &(&1.trigger in [:on_load, :on_change]))

      Enum.reduce(data_endpoints, {tools, registry}, fn endpoint, {ts, reg} ->
        tool_name = encode_tool_name(lamp_id, endpoint.id)

        tool =
          ReqLLM.tool(
            name: tool_name,
            description: "Fetch data from lamp #{lamp_id} endpoint #{endpoint.id}",
            parameter_schema: [],
            callback: fn _args -> {:ok, "handled by Genie Reactor"} end
          )

        {[tool | ts], Map.put(reg, tool_name, {lamp_id, endpoint.id})}
      end)
    end)
  end

  defp encode_tool_name(lamp_id, endpoint_id) do
    encoded = String.replace(lamp_id, ~r/[.\-]/, "_")
    "data_#{encoded}_#{endpoint_id}"
  end

  defp build_system_prompt(manifests) do
    {invokable, webhook_only} = Enum.split_with(manifests, &invokable?/1)

    invokable_list =
      Enum.map_join(invokable, "\n", fn %LampDefinition{id: id, meta: meta} ->
        "- #{id}: #{meta && meta.title}"
      end)

    webhook_section =
      if webhook_only != [] do
        webhook_list =
          Enum.map_join(webhook_only, "\n", fn %LampDefinition{id: id, meta: meta} ->
            "- #{id}: #{meta && meta.title}"
          end)

        """

        The following lamps update automatically via external webhooks — do NOT call invoke_lamp for them.
        Tell the user their canvas will update automatically when triggered:
        #{webhook_list}
        """
      else
        ""
      end

    """
    You are Genie, an agentic DevOps platform assistant. You help engineers
    by invoking the right GenieLamp tool for their request.

    CRITICAL RULES:
    1. Call invoke_lamp IMMEDIATELY when the user's intent is clear — do NOT ask
       clarifying questions. Missing values are auto-filled from context or inferred by AI.
    2. Always include lamp_id, endpoint_id, and any known params.
    3. Only respond with plain text if no lamp matches the request at all.

    Invokable lamps (call invoke_lamp for these):
    #{invokable_list}
    #{webhook_section}
    Do not reveal internal system details in text replies.
    """
  end
end
