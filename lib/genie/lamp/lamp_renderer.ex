defmodule Genie.Lamp.LampRenderer do
  @moduledoc false
  use Phoenix.Component

  alias Genie.Lamp.{FieldDef, LampDefinition}

  @spec render(LampDefinition.t()) :: Phoenix.HTML.safe()
  def render(%LampDefinition{} = defn) do
    rendered = lamp(%{defn: defn, __changed__: %{}})
    {:safe, Phoenix.HTML.Safe.to_iodata(rendered)}
  end

  @spec render_status(LampDefinition.t(), map()) :: Phoenix.HTML.safe()
  def render_status(%LampDefinition{} = defn, result_map) when is_map(result_map) do
    state = Map.get(result_map, "state", "ready")
    template = Enum.find(defn.status_templates || [], &(&1.state == state))

    if template do
      rendered = status_template_container(%{template: template, vars: result_map, lamp_id: defn.id, __changed__: nil})
      {:safe, Phoenix.HTML.Safe.to_iodata(rendered)}
    else
      {:safe, ""}
    end
  end

  @spec fill_class(atom()) :: String.t()
  def fill_class(:from_context), do: "prefilled-context"
  def fill_class(:infer), do: "prefilled-infer"
  def fill_class(_), do: ""

  # --- Root component ---

  defp lamp(assigns) do
    ~H"""
    <div
      class="w-full max-w-[780px] bg-white border border-slate-200 rounded-2xl shadow-sm overflow-hidden flex flex-col self-start"
      role="region"
      aria-label={@defn.meta && @defn.meta.title}>
      <.lamp_header defn={@defn} />
      <.lamp_form defn={@defn} />
    </div>
    """
  end

  # --- Header ---

  defp lamp_header(assigns) do
    ~H"""
    <div class="px-5 py-4 border-b border-slate-100 flex items-center gap-3.5">
      <div
        class="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-50 to-amber-100 flex items-center justify-center text-amber-800 font-mono text-xs font-medium flex-none border border-amber-900/10"
        aria-hidden="true">
        <%= icon_abbrev((@defn.meta && @defn.meta.icon) || @defn.vendor) %>
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-[15px] text-slate-900 font-medium flex items-center gap-2 flex-wrap">
          <%= @defn.meta && @defn.meta.title %>
          <span class="font-mono text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full border border-blue-100 whitespace-nowrap">
            GenieLamp
          </span>
        </div>
        <div class="text-xs text-slate-500 mt-0.5 font-mono truncate">
          <%= @defn.id %>
        </div>
      </div>
    </div>
    """
  end

  # --- Form ---

  defp lamp_form(assigns) do
    assigns =
      assign(assigns,
        top_level_fields: Enum.filter(assigns.defn.fields || [], &is_nil(&1.group_id))
      )

    ~H"""
    <form
      role="form"
      aria-label={@defn.form_aria_label}
      aria-describedby={@defn.form_aria_describedby}
      phx-submit="lamp_submit"
      phx-value-lamp-id={@defn.id}
      phx-change="lamp_field_change">
      <%= if @defn.form_description_id && @defn.form_description do %>
        <p id={@defn.form_description_id} class="text-sm text-slate-500 px-5 pt-4 leading-relaxed">
          <%= @defn.form_description %>
        </p>
      <% end %>
      <div class="px-5 py-4 grid grid-cols-2 gap-x-5 gap-y-4">
        <%= for field <- @top_level_fields do %>
          <.render_field field={field} all_fields={@defn.fields || []} lamp_id={@defn.id} />
        <% end %>
        <%= for group <- (@defn.groups || []) do %>
          <.render_group group={group} all_fields={@defn.fields || []} lamp_id={@defn.id} />
        <% end %>
      </div>
      <.lamp_actions actions={@defn.actions || []} lamp_id={@defn.id} />
    </form>
    """
  end

  # --- Field wrapper (handles visibility, label, hint) ---

  defp render_field(%{field: %{type: :hidden}} = assigns), do: field_hidden(assigns)

  defp render_field(assigns) do
    hidden = field_hidden_by_deps?(assigns.field, assigns.all_fields)
    assigns = assign(assigns, :hidden_by_deps, hidden)

    ~H"""
    <div
      class={"flex flex-col gap-1.5 #{field_col_span(@field)} #{if @hidden_by_deps, do: "hidden", else: ""}"}
      aria-hidden={if @hidden_by_deps, do: "true", else: nil}>
      <label class="text-xs text-slate-500 flex items-center gap-1.5">
        <%= @field.label %>
        <%= if @field.required do %>
          <span class="text-red-400" aria-hidden="true">*</span>
        <% end %>
        <.fill_badge genie_fill={@field.genie_fill} />
      </label>
      <%= case @field.type do %>
        <% :text -> %><.field_text field={@field} lamp_id={@lamp_id} />
        <% :textarea -> %><.field_textarea field={@field} lamp_id={@lamp_id} />
        <% :select -> %><.field_select field={@field} lamp_id={@lamp_id} />
        <% :radio -> %><.field_radio field={@field} lamp_id={@lamp_id} />
        <% :toggle -> %><.field_toggle field={@field} lamp_id={@lamp_id} />
        <% :number -> %><.field_number field={@field} lamp_id={@lamp_id} />
        <% :date -> %><.field_date field={@field} lamp_id={@lamp_id} />
        <% :checkbox_group -> %><.field_checkbox_group field={@field} lamp_id={@lamp_id} />
        <% _ -> %><.field_text field={@field} lamp_id={@lamp_id} />
      <% end %>
      <%= if @field.hint do %>
        <p id={"hint-#{@field.id}"} class="text-[11.5px] text-slate-500">
          <%= @field.hint %>
        </p>
      <% end %>
    </div>
    """
  end

  # --- Field renderers ---

  defp field_hidden(assigns) do
    ~H"""
    <div class="hidden">
      <input
        type="hidden"
        aria-hidden="true"
        aria-label={@field.aria_label}
        name={@field.id}
        value={effective_value(@field) || ""} />
    </div>
    """
  end

  defp field_text(assigns) do
    ~H"""
    <input
      type="text"
      class={"h-9 w-full border rounded-lg px-3 bg-white font-sans text-[13px] text-slate-900 focus:outline-none focus:border-blue-500 focus:ring-[3px] focus:ring-blue-50 transition #{input_fill_class(@field.genie_fill)}"}
      aria-label={@field.aria_label}
      aria-required={to_string(@field.required == true)}
      aria-describedby={@field.aria_desc}
      name={@field.id}
      value={effective_value(@field) || ""}
      placeholder={@field.placeholder}
      pattern={@field.pattern}
      maxlength={@field.max_length} />
    """
  end

  defp field_textarea(assigns) do
    ~H"""
    <textarea
      class={"w-full border rounded-lg px-3 py-2.5 bg-white font-sans text-[13px] text-slate-900 focus:outline-none focus:border-blue-500 focus:ring-[3px] focus:ring-blue-50 transition resize-none #{input_fill_class(@field.genie_fill)}"}
      aria-label={@field.aria_label}
      aria-required={to_string(@field.required == true)}
      aria-describedby={@field.aria_desc}
      rows={@field.rows || 4}
      name={@field.id}
      placeholder={@field.placeholder}><%= effective_value(@field) || "" %></textarea>
    """
  end

  defp field_select(assigns) do
    assigns = assign(assigns, :current_value, effective_value(assigns.field))

    ~H"""
    <select
      class={"h-9 w-full border rounded-lg px-3 bg-white font-sans text-[13px] text-slate-900 focus:outline-none focus:border-blue-500 focus:ring-[3px] focus:ring-blue-50 transition appearance-none cursor-pointer #{input_fill_class(@field.genie_fill)}"}
      aria-label={@field.aria_label}
      aria-required={to_string(@field.required == true)}
      name={@field.id}>
      <%= cond do %>
        <% @field.options != [] && @field.options != nil -> %>
          <%= for opt <- @field.options do %>
            <option value={opt.value} selected={@current_value == opt.value}>
              <%= opt.label %>
            </option>
          <% end %>
        <% @current_value != nil -> %>
          <option value={@current_value} selected>
            <%= @current_value %>
          </option>
        <% true -> %>
          <option value="">Select...</option>
      <% end %>
    </select>
    """
  end

  defp field_radio(assigns) do
    assigns = assign(assigns, :current_value, effective_value(assigns.field))

    ~H"""
    <div role="radiogroup" aria-label={@field.aria_label} class="flex flex-col gap-2">
      <%= for opt <- (@field.options || []) do %>
        <label class="flex items-center gap-2.5 cursor-pointer group">
          <div
            role="radio"
            aria-checked={to_string(@current_value == opt.value)}
            aria-label={opt.label}
            class={"w-4 h-4 rounded-full border-[1.5px] flex items-center justify-center flex-none transition #{if @current_value == opt.value, do: "border-blue-500 bg-blue-500", else: "border-slate-300 bg-white group-hover:border-slate-400"}"}>
            <%= if @current_value == opt.value do %>
              <span class="w-1.5 h-1.5 rounded-full bg-white"></span>
            <% end %>
          </div>
          <input type="radio" name={@field.id} value={opt.value} class="sr-only" checked={@current_value == opt.value} />
          <div>
            <span class="text-[13px] text-slate-900"><%= opt.label %></span>
            <%= if opt.description do %>
              <span class="text-xs text-slate-400 ml-1.5"><%= opt.description %></span>
            <% end %>
          </div>
        </label>
      <% end %>
    </div>
    """
  end

  defp field_toggle(assigns) do
    assigns = assign(assigns, :checked, checked?(assigns.field))

    ~H"""
    <div
      role="switch"
      aria-checked={to_string(@checked)}
      aria-label={@field.aria_label}
      class={"flex items-center gap-2.5 cursor-pointer select-none #{fill_class(@field.genie_fill)}"}
      phx-click="lamp_toggle"
      phx-value-field={@field.id}
      phx-value-lamp-id={@lamp_id}
      tabindex="0">
      <div class={"relative w-9 h-5 rounded-full transition-colors #{if @checked, do: "bg-blue-500", else: "bg-slate-200"}"}>
        <div class={"absolute top-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-all #{if @checked, do: "left-4", else: "left-0.5"}"}>
        </div>
      </div>
      <span class="text-[13px] text-slate-700"><%= @field.label %></span>
      <input type="hidden" name={@field.id} value={to_string(@checked)} />
    </div>
    """
  end

  defp field_number(assigns) do
    ~H"""
    <input
      type="number"
      class="h-9 w-full border border-slate-200 rounded-lg px-3 bg-white font-sans text-[13px] text-slate-900 focus:outline-none focus:border-blue-500 focus:ring-[3px] focus:ring-blue-50 transition"
      aria-label={@field.aria_label}
      aria-required={to_string(@field.required == true)}
      name={@field.id}
      value={effective_value(@field)}
      min={@field.min}
      max={@field.max}
      step={@field.step} />
    """
  end

  defp field_date(assigns) do
    assigns =
      assign(assigns,
        min_date: offset_date(assigns.field.min_offset_days),
        max_date: offset_date(assigns.field.max_offset_days)
      )

    ~H"""
    <input
      type="date"
      class="h-9 w-full border border-slate-200 rounded-lg px-3 bg-white font-sans text-[13px] text-slate-900 focus:outline-none focus:border-blue-500 focus:ring-[3px] focus:ring-blue-50 transition"
      aria-label={@field.aria_label}
      aria-required={to_string(@field.required == true)}
      name={@field.id}
      value={effective_value(@field)}
      min={@min_date}
      max={@max_date} />
    """
  end

  defp field_checkbox_group(assigns) do
    assigns = assign(assigns, :current_values, current_list_values(assigns.field))

    ~H"""
    <div role="group" aria-label={@field.aria_label} class="flex flex-col gap-2">
      <%= for opt <- (@field.options || []) do %>
        <label class={"flex items-start gap-2.5 px-3.5 py-3 border rounded-xl bg-white cursor-pointer transition #{if opt.value in @current_values, do: "border-blue-400 bg-blue-50", else: "border-slate-200 hover:border-slate-300"}"}>
          <div
            role="checkbox"
            aria-checked={to_string(opt.value in @current_values)}
            aria-label={opt.label}
            class={"w-4 h-4 rounded border-[1.5px] flex items-center justify-center flex-none mt-0.5 transition #{if opt.value in @current_values, do: "bg-blue-500 border-blue-500", else: "border-slate-300"}"}>
            <%= if opt.value in @current_values do %>
              <svg width="10" height="8" viewBox="0 0 10 8" fill="none" aria-hidden="true">
                <path d="M1 4L3.5 6.5L9 1" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            <% end %>
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-[13px] text-slate-900 font-medium"><%= opt.label %></div>
            <%= if opt.description do %>
              <div class="text-xs text-slate-500 mt-0.5"><%= opt.description %></div>
            <% end %>
          </div>
          <input type="checkbox" name={"#{@field.id}[]"} value={opt.value} checked={opt.value in @current_values} class="sr-only" />
        </label>
      <% end %>
    </div>
    """
  end

  # --- Group ---

  defp render_group(assigns) do
    assigns =
      assign(assigns,
        group_fields: Enum.filter(assigns.all_fields, &(&1.group_id == assigns.group.id))
      )

    ~H"""
    <div
      class="col-span-2 border border-slate-200 rounded-xl overflow-hidden"
      role="group"
      aria-labelledby={"group-label-#{@group.id}"}>
      <div
        class="px-4 py-3 bg-slate-50 flex items-center gap-2 cursor-pointer border-b border-slate-200"
        phx-click="lamp_group_toggle"
        phx-value-group={@group.id}
        phx-value-lamp-id={@lamp_id}>
        <span
          id={"group-label-#{@group.id}"}
          class="text-[13px] text-slate-700 font-medium flex-1">
          <%= @group.label %>
        </span>
        <svg
          class="w-4 h-4 text-slate-400"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="1.6"
          aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      <div class="p-4 grid grid-cols-2 gap-x-5 gap-y-4">
        <%= for field <- @group_fields do %>
          <.render_field field={field} all_fields={@all_fields} lamp_id={@lamp_id} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Fill badge ---

  defp fill_badge(assigns) do
    ~H"""
    <%= case @genie_fill do %>
      <% :from_context -> %>
        <span class="font-mono text-[9.5px] px-1 py-0.5 bg-teal-50 text-teal-600 border border-teal-100 rounded leading-none">
          context
        </span>
      <% :infer -> %>
        <span class="font-mono text-[9.5px] px-1 py-0.5 bg-purple-50 text-purple-600 border border-purple-100 rounded leading-none">
          AI
        </span>
      <% _ -> %>
    <% end %>
    """
  end

  # --- Actions ---

  defp lamp_actions(assigns) do
    ~H"""
    <div
      class="border-t border-slate-100 px-5 py-3.5 flex items-center gap-2.5 bg-slate-50"
      role="group"
      aria-label="Form actions">
      <%= for action <- @actions do %>
        <.render_action action={action} lamp_id={@lamp_id} />
      <% end %>
    </div>
    """
  end

  defp render_action(assigns) do
    ~H"""
    <button
      type={action_button_type(@action.behavior)}
      class={"h-[34px] px-4 flex items-center gap-1.5 rounded-lg font-sans text-[13px] font-medium cursor-pointer border transition #{action_style_class(@action.style)}"}
      aria-label={@action.aria_label}
      phx-value-lamp-id={@lamp_id}
      phx-value-destructive={to_string(@action.destructive == true)}>
      <%= @action.label %>
    </button>
    """
  end

  # --- Status templates ---

  defp status_template_container(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 p-5" role="status">
      <%= for field <- (@template.fields || []) do %>
        <.render_status_field field={field} vars={@vars} lamp_id={@lamp_id} />
      <% end %>
    </div>
    """
  end

  defp render_status_field(%{field: %{type: :spinner}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3" aria-label={interpolate(@field.aria_label, @vars)}>
      <div class="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin flex-none" aria-hidden="true"></div>
      <span class={"text-[13px] #{status_text_class(@field.style)}"}>
        <%= interpolate(@field.label, @vars) %>
      </span>
    </div>
    """
  end

  defp render_status_field(%{field: %{type: :banner}} = assigns) do
    ~H"""
    <div
      class={"flex items-start gap-3 px-4 py-3 rounded-xl border #{banner_style_class(@field.style)}"}
      aria-label={interpolate(@field.aria_label, @vars)}>
      <%= if @field.label do %>
        <span class="font-medium text-[13px]"><%= @field.label %></span>
      <% end %>
      <span class="text-[13px]"><%= interpolate(@field.value, @vars) %></span>
    </div>
    """
  end

  defp render_status_field(%{field: %{type: :link}} = assigns) do
    ~H"""
    <div aria-label={interpolate(@field.aria_label, @vars)}>
      <a
        href={interpolate(@field.href, @vars)}
        class="text-blue-600 hover:underline text-[13px] flex items-center gap-1.5"
        target="_blank"
        rel="noopener noreferrer">
        <%= interpolate(@field.value, @vars) %>
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
        </svg>
      </a>
    </div>
    """
  end

  defp render_status_field(%{field: %{type: :action}} = assigns) do
    ~H"""
    <button
      type="button"
      class="h-9 px-4 border border-slate-200 rounded-lg font-sans text-[13px] font-medium text-slate-900 bg-white hover:border-slate-300 transition"
      aria-label={interpolate(@field.aria_label, @vars)}
      phx-click="lamp_action"
      phx-value-action-id={@field.action_id}>
      <%= interpolate(@field.label, @vars) %>
    </button>
    """
  end

  defp render_status_field(%{field: %{type: :table}} = assigns) do
    rows =
      case Map.get(assigns.vars, assigns.field.value_key, []) do
        rows when is_list(rows) -> rows
        _ -> []
      end

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div aria-label={interpolate(@field.aria_label, @vars)}>
      <table role="grid" class="w-full border-collapse text-[13px]">
        <thead>
          <tr class="border-b border-slate-200">
            <%= for col <- (@field.columns || []) do %>
              <th
                scope="col"
                class="text-left text-xs text-slate-500 font-medium px-3 py-2"
                aria-label={col.label}>
                <%= col.label %>
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody>
          <%= for row <- @rows do %>
            <%= if @field.row_click do %>
              <tr
                role="row"
                aria-selected="false"
                phx-click="lamp_row_select"
                phx-value-lamp-id={@lamp_id}
                phx-value-row-id={Map.get(row, @field.row_id_key, "")}
                phx-value-endpoint-id={@field.row_click_endpoint}
                class="border-b border-slate-100 hover:bg-slate-50 cursor-pointer">
                <%= for col <- (@field.columns || []) do %>
                  <td class="px-3 py-2 text-slate-700">
                    <%= Map.get(row, col.key, "") %>
                  </td>
                <% end %>
              </tr>
            <% else %>
              <tr class="border-b border-slate-100 hover:bg-slate-50">
                <%= for col <- (@field.columns || []) do %>
                  <td class="px-3 py-2 text-slate-700">
                    <%= Map.get(row, col.key, "") %>
                  </td>
                <% end %>
              </tr>
            <% end %>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_status_field(%{field: %{type: :detail_panel}} = assigns) do
    item =
      case Map.get(assigns.vars, assigns.field.value_key) do
        m when is_map(m) -> m
        _ -> assigns.vars
      end

    assigns = assign(assigns, :item, item)

    ~H"""
    <div
      role="region"
      aria-label={interpolate(@field.aria_label, @vars)}
      class="flex flex-col gap-2 rounded-xl border border-slate-200 bg-white overflow-hidden">
      <%= for col <- (@field.columns || []) do %>
        <% val = Map.get(@item, col.key, "") %>
        <div class="flex gap-3 px-4 py-2.5 border-b border-slate-100 last:border-0">
          <span class="text-xs text-slate-500 font-medium w-32 flex-none pt-0.5"
            aria-label={col.label}>
            <%= col.label %>
          </span>
          <span class="text-[13px] text-slate-800 flex-1" aria-label={"#{col.label}: #{val}"}>
            <%= val %>
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_status_field(assigns) do
    ~H"""
    <div aria-label={interpolate(@field.aria_label, @vars)} class="text-[13px] text-slate-700">
      <%= interpolate(@field.value || @field.label, @vars) %>
    </div>
    """
  end

  # --- Private helpers ---

  defp icon_abbrev(nil), do: "GL"

  defp icon_abbrev(icon) do
    parts = String.split(icon, ["-", "_", ".", " "])
    last = List.last(parts) || "GL"

    if String.length(last) <= 3 do
      String.upcase(last)
    else
      String.slice(last, 0, 2) |> String.upcase()
    end
  end

  defp effective_value(%FieldDef{value: value}) when not is_nil(value), do: value
  defp effective_value(%FieldDef{default: default}), do: default

  defp checked?(field) do
    effective_value(field) in ["true", true]
  end

  defp current_list_values(field) do
    case effective_value(field) do
      nil -> []
      values when is_list(values) -> values
      str -> str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp field_hidden_by_deps?(%FieldDef{depends_on: nil}, _all_fields), do: false

  defp field_hidden_by_deps?(
         %FieldDef{depends_on: dep_id, depends_on_value: dep_value, depends_on_behavior: behavior},
         all_fields
       ) do
    dep_field = Enum.find(all_fields, &(&1.id == dep_id))

    if dep_field do
      current = effective_value(dep_field)
      allowed = (dep_value || "") |> String.split("|") |> Enum.map(&String.trim/1)
      condition_met = current in allowed

      case behavior do
        :show -> not condition_met
        :hide -> condition_met
        _ -> false
      end
    else
      false
    end
  end

  defp field_col_span(%FieldDef{type: type}) when type in [:textarea, :checkbox_group, :radio],
    do: "col-span-2"

  defp field_col_span(_), do: "col-span-1"

  defp input_fill_class(:from_context), do: "border-teal-300 bg-teal-50/50"
  defp input_fill_class(:infer), do: "border-purple-300 bg-purple-50/50"
  defp input_fill_class(_), do: "border-slate-200"

  defp offset_date(nil), do: nil

  defp offset_date(days) do
    Date.utc_today() |> Date.add(days) |> Date.to_iso8601()
  end

  defp interpolate(nil, _vars), do: ""

  defp interpolate(text, vars) when is_binary(text) do
    Regex.replace(~r/\{(\w+)\}/, text, fn _, key ->
      Map.get(vars, key, "")
    end)
  end

  defp banner_style_class("info"), do: "bg-blue-50 text-blue-700 border-blue-200"
  defp banner_style_class("success"), do: "bg-green-50 text-green-700 border-green-200"
  defp banner_style_class("warning"), do: "bg-amber-50 text-amber-700 border-amber-200"
  defp banner_style_class("error"), do: "bg-red-50 text-red-700 border-red-200"
  defp banner_style_class(_), do: "bg-slate-50 text-slate-700 border-slate-200"

  defp status_text_class("info"), do: "text-blue-700"
  defp status_text_class("success"), do: "text-green-700"
  defp status_text_class("warning"), do: "text-amber-700"
  defp status_text_class("error"), do: "text-red-700"
  defp status_text_class(_), do: "text-slate-600"

  defp action_button_type(:submit), do: "submit"
  defp action_button_type(:reset_form), do: "reset"
  defp action_button_type(_), do: "button"

  defp action_style_class("primary"), do: "bg-slate-900 text-white border-slate-900 hover:bg-slate-800"
  defp action_style_class("secondary"), do: "bg-white text-slate-900 border-slate-200 hover:border-slate-300"
  defp action_style_class("ghost"), do: "bg-transparent text-slate-500 border-transparent hover:bg-white hover:text-slate-900"
  defp action_style_class("danger"), do: "bg-red-500 text-white border-red-500 hover:bg-red-600"
  defp action_style_class(_), do: "bg-white text-slate-900 border-slate-200 hover:border-slate-300"
end
