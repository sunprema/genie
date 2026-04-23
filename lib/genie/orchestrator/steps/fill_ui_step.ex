defmodule Genie.Orchestrator.Steps.FillUiStep do
  @moduledoc """
  Step 6: Fills lamp form fields using genie-fill strategies, then renders HTML.

  - :from_context fields: extracted directly from conversation context entities
  - :infer fields: sent to LLM as a typed schema (single call for all infer fields)
  - :none fields: left empty for the user to fill
  - :message results: passed through as chat messages
  """
  use Reactor.Step

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Lamp.{LampDefinition, LampRegistry, LampRenderer}
  alias Genie.Orchestrator.LlmClient

  @impl Reactor.Step
  def run(%{validated_action: {:action, action}, manifests: manifests, build_context: build_context}, _context, _options) do
    with {:ok, lamp} <- find_lamp(action.lamp_id, manifests),
         {:ok, filled} <- fill_definition(lamp, action.params || %{}, build_context) do
      {context_count, infer_count} = count_fill_fields(lamp.fields)
      field_count = length(lamp.fields)

      Tracer.with_span "Genie.renderer.render", %{
        attributes: [
          {"lamp_id", action.lamp_id},
          {"field_count", field_count},
          {"infer_count", infer_count},
          {"context_count", context_count}
        ]
      } do
        html = lamp_to_html(filled)
        {:ok, %{html: html, lamp_id: action.lamp_id, type: :canvas}}
      end
    end
  end

def run(%{validated_action: {:message, %{text: text}}}, _context, _options) do
    {:ok, %{html: nil, message: text, lamp_id: nil, type: :chat}}
  end

  @impl Reactor.Step
  def compensate(_reason, %{validated_action: {:action, action}, manifests: manifests} = _args, _context, _options) do
    case find_lamp(action.lamp_id, manifests) do
      {:ok, lamp} ->
        filled = fill_none_strategy(lamp)
        html = lamp_to_html(filled)
        {:continue, %{html: html, lamp_id: action.lamp_id, type: :canvas}}

      _ ->
        :ok
    end
  end

  def compensate(_reason, _arguments, _context, _options), do: :ok

  defp find_lamp(lamp_id, manifests) do
    case Enum.find(manifests, &(&1.id == lamp_id)) do
      nil -> LampRegistry.fetch_lamp(lamp_id)
      lamp -> {:ok, lamp}
    end
  end

  defp fill_definition(%LampDefinition{fields: fields} = lamp, params, build_context) do
    {context_fields, infer_fields, none_fields} = partition_fields(fields)

    filled_context = fill_from_context(context_fields, params, lamp)

    case fill_infer(infer_fields, build_context) do
      {:ok, infer_values} ->
        filled_infer = apply_values(infer_fields, infer_values)
        filled_none = apply_values(none_fields, %{})
        all_filled = filled_context ++ filled_infer ++ filled_none
        sorted = sort_fields(all_filled, fields)
        {:ok, %{lamp | fields: sorted}}

      {:error, _} ->
        filled_infer = apply_values(infer_fields, %{})
        filled_none = apply_values(none_fields, %{})
        all_filled = filled_context ++ filled_infer ++ filled_none
        sorted = sort_fields(all_filled, fields)
        {:ok, %{lamp | fields: sorted}}
    end
  end

  defp partition_fields(fields) do
    context_fields = Enum.filter(fields, &(&1.genie_fill == :from_context))
    infer_fields = Enum.filter(fields, &(&1.genie_fill == :infer))
    none_fields = Enum.reject(fields, &(&1.genie_fill in [:from_context, :infer]))
    {context_fields, infer_fields, none_fields}
  end

  defp fill_from_context(fields, params, _lamp) do
    Enum.map(fields, fn field ->
      value = Map.get(params, field.id) || Map.get(params, String.to_atom(field.id))
      %{field | value: value}
    end)
  end

  defp fill_infer([], _build_context), do: {:ok, %{}}

  defp fill_infer(fields, build_context) do
    messages = build_context.llm_context && build_context.llm_context.messages || []

    conversation =
      messages
      |> Enum.filter(&(&1.role in [:user, :assistant]))
      |> Enum.map_join("\n", fn msg ->
        role = if msg.role == :user, do: "User", else: "Assistant"
        text = msg.content |> Enum.filter(&(&1.type == :text)) |> Enum.map_join("", & &1.text)
        "#{role}: #{text}"
      end)

    LlmClient.fill(%{fields: fields, conversation: conversation})
  end

  defp apply_values(fields, values) do
    Enum.map(fields, fn field ->
      value = Map.get(values, field.id) || Map.get(values, String.to_atom(field.id))
      %{field | value: value}
    end)
  end

  defp sort_fields(filled_fields, original_order) do
    index = original_order |> Enum.with_index() |> Map.new(fn {f, i} -> {f.id, i} end)
    Enum.sort_by(filled_fields, fn f -> Map.get(index, f.id, 999) end)
  end

  defp count_fill_fields(fields) do
    context_count = Enum.count(fields, &(&1.genie_fill == :from_context))
    infer_count = Enum.count(fields, &(&1.genie_fill == :infer))
    {context_count, infer_count}
  end

  defp fill_none_strategy(%LampDefinition{fields: fields} = lamp) do
    %{lamp | fields: Enum.map(fields, fn f -> %{f | value: f.value || f.default} end)}
  end

  defp lamp_to_html(lamp) do
    {:safe, html_data} = LampRenderer.render(lamp)
    IO.iodata_to_binary(html_data)
  end
end
