defmodule Genie.Orchestrator.Steps.BuildContextStep do
  @moduledoc """
  Step 2: Assembles the LLM context from conversation history and lamp manifests.

  Builds:
  - A ReqLLM.Context from the last 20 conversation turns plus a system prompt
  - A tools list with one `invoke_lamp` intent tool and data-gathering tools per lamp
  - A tool_registry mapping tool name → {lamp_id, endpoint_id}
  """
  use Reactor.Step

  alias Genie.Conversation.Turn
  alias Genie.Lamp.LampDefinition
  alias ReqLLM.Context

  @max_turns 20

  @impl Reactor.Step
  def run(%{session: session, manifests: manifests, user_message: user_message}, _context, _options) do
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

  defp build_tools(manifests) do
    intent_tool = build_invoke_lamp_tool(manifests)
    {data_tools, registry} = build_data_tools(manifests)

    {[intent_tool | data_tools], registry}
  end

  defp build_invoke_lamp_tool(manifests) do
    lamp_descriptions =
      manifests
      |> Enum.map_join("\n\n", fn %LampDefinition{id: id, meta: meta, endpoints: endpoints, fields: fields} ->
        title = meta && meta.title
        desc = meta && meta.description

        submit_endpoints =
          (endpoints || [])
          |> Enum.filter(&(&1.trigger == :on_submit))
          |> Enum.map_join(", ", & &1.id)

        field_list =
          (fields || [])
          |> Enum.reject(&(&1.type == :hidden))
          |> Enum.map_join(", ", & &1.id)

        "lamp_id=\"#{id}\" (#{title})\n  description: #{desc}\n  endpoint_id (use exactly one): #{submit_endpoints}\n  params keys: #{field_list}"
      end)

    lamp_ids = manifests |> Enum.map_join(", ", & &1.id)

    ReqLLM.tool(
      name: "invoke_lamp",
      description: """
      Invoke a GenieLamp tool. You MUST include lamp_id, endpoint_id, and params.

      REQUIRED: lamp_id must be one of: #{lamp_ids}

      Available lamps:
      #{lamp_descriptions}

      Example: {lamp_id: "aws.ec2.list-instances", endpoint_id: "list_instances", params: {region: "us-east-1", state: "running"}}
      """,
      parameter_schema: [
        lamp_id: [type: :string, required: true, doc: "REQUIRED. One of: #{lamp_ids}"],
        endpoint_id: [type: :string, required: true, doc: "REQUIRED. The exact endpoint_id from the lamp definition above"],
        params: [type: :map, required: false, doc: "Field values keyed by the params keys listed above"]
      ],
      callback: fn _args -> {:ok, "handled by Genie Reactor"} end
    )
  end

  defp build_data_tools(manifests) do
    Enum.reduce(manifests, {[], %{}}, fn %LampDefinition{id: lamp_id, endpoints: endpoints}, {tools, registry} ->
      data_endpoints = Enum.filter(endpoints || [], &(&1.trigger in ["on-load", "on-change"]))

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
    lamp_list =
      manifests
      |> Enum.map_join("\n", fn %LampDefinition{id: id, meta: meta} ->
        "- #{id}: #{meta && meta.title}"
      end)

    """
    You are Genie, an agentic DevOps platform assistant. You help engineers
    by identifying which tool (GenieLamp) to use based on their request.

    When you have gathered enough information, call invoke_lamp with the
    appropriate lamp_id, endpoint_id, and params. Always include lamp_id.

    If no lamp is needed, respond with a plain message.

    Available lamps:
    #{lamp_list}

    IMPORTANT: In your text replies to the user, do not reveal internal system details.
    Always include lamp_id when calling invoke_lamp.
    """
  end
end
