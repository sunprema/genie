defmodule Genie.Lamp.LampSerializer do
  @moduledoc false
  alias Genie.Lamp.{
    ActionDef,
    ColumnDef,
    EndpointDef,
    FieldDef,
    GroupDef,
    LampDefinition,
    MetaDef,
    OptionDef,
    StatusTemplate
  }

  @spec to_map(LampDefinition.t()) :: map()
  def to_map(%LampDefinition{} = defn) do
    %{
      id: defn.id,
      version: defn.version,
      category: defn.category,
      vendor: defn.vendor,
      form_aria_label: defn.form_aria_label,
      form_aria_describedby: defn.form_aria_describedby,
      form_description_id: defn.form_description_id,
      form_description: defn.form_description,
      meta: meta_to_map(defn.meta),
      endpoints: Enum.map(defn.endpoints || [], &endpoint_to_map/1),
      fields: Enum.map(defn.fields || [], &field_to_map/1),
      groups: Enum.map(defn.groups || [], &group_to_map/1),
      actions: Enum.map(defn.actions || [], &action_to_map/1),
      status_templates: Enum.map(defn.status_templates || [], &template_to_map/1)
    }
  end

  @spec from_map(map() | nil) :: LampDefinition.t() | nil
  def from_map(nil), do: nil

  def from_map(m) when is_map(m) do
    %LampDefinition{
      id: get(m, "id"),
      version: get(m, "version"),
      category: get(m, "category"),
      vendor: get(m, "vendor"),
      form_aria_label: get(m, "form_aria_label"),
      form_aria_describedby: get(m, "form_aria_describedby"),
      form_description_id: get(m, "form_description_id"),
      form_description: get(m, "form_description"),
      meta: meta_from_map(get(m, "meta")),
      endpoints: Enum.map(get(m, "endpoints") || [], &endpoint_from_map/1),
      fields: Enum.map(get(m, "fields") || [], &field_from_map/1),
      groups: Enum.map(get(m, "groups") || [], &group_from_map/1),
      actions: Enum.map(get(m, "actions") || [], &action_from_map/1),
      status_templates: Enum.map(get(m, "status_templates") || [], &template_from_map/1)
    }
  end

  defp meta_to_map(nil), do: nil

  defp meta_to_map(%MetaDef{} = m) do
    %{
      title: m.title,
      description: m.description,
      icon: m.icon,
      tags: m.tags,
      requires_approval: m.requires_approval,
      approval_policy: m.approval_policy,
      destructive: m.destructive,
      audit: m.audit,
      base_url: m.base_url,
      auth_scheme: m.auth_scheme,
      timeout_ms: m.timeout_ms
    }
  end

  defp field_to_map(%FieldDef{} = f) do
    %{
      id: f.id,
      type: atom_to_str(f.type),
      label: f.label,
      aria_label: f.aria_label,
      aria_desc: f.aria_desc,
      genie_fill: atom_to_str(f.genie_fill),
      required: f.required,
      default: f.default,
      placeholder: f.placeholder,
      pattern: f.pattern,
      max_length: f.max_length,
      min: f.min,
      max: f.max,
      step: f.step,
      min_offset_days: f.min_offset_days,
      max_offset_days: f.max_offset_days,
      rows: f.rows,
      options: Enum.map(f.options || [], &option_to_map/1),
      options_from: f.options_from,
      options_value_key: f.options_value_key,
      options_label_key: f.options_label_key,
      depends_on: f.depends_on,
      depends_on_value: f.depends_on_value,
      depends_on_behavior: atom_to_str(f.depends_on_behavior),
      group_id: f.group_id,
      hint: f.hint,
      style: f.style,
      href: f.href,
      action_id: f.action_id,
      value: f.value,
      value_key: f.value_key,
      columns: Enum.map(f.columns || [], &column_to_map/1),
      row_click: f.row_click,
      row_id_key: f.row_id_key,
      row_click_endpoint: f.row_click_endpoint
    }
  end

  defp column_to_map(%ColumnDef{} = c) do
    %{key: c.key, label: c.label}
  end

  defp option_to_map(%OptionDef{} = o) do
    %{value: o.value, label: o.label, description: o.description}
  end

  defp action_to_map(%ActionDef{} = a) do
    %{
      id: a.id,
      label: a.label,
      aria_label: a.aria_label,
      style: a.style,
      endpoint_id: a.endpoint_id,
      destructive: a.destructive,
      behavior: atom_to_str(a.behavior)
    }
  end

  defp endpoint_to_map(%EndpointDef{} = e) do
    %{
      id: e.id,
      method: e.method,
      path: e.path,
      trigger: atom_to_str(e.trigger),
      fills_field: e.fills_field,
      action_id: e.action_id,
      poll_interval_ms: e.poll_interval_ms,
      poll_until: e.poll_until,
      timeout_ms: e.timeout_ms
    }
  end

  defp group_to_map(%GroupDef{} = g) do
    %{id: g.id, label: g.label, aria_label: g.aria_label, collapsible: g.collapsible}
  end

  defp template_to_map(%StatusTemplate{} = t) do
    %{state: t.state, fields: Enum.map(t.fields || [], &field_to_map/1)}
  end

  defp meta_from_map(nil), do: nil

  defp meta_from_map(m) do
    %MetaDef{
      title: get(m, "title"),
      description: get(m, "description"),
      icon: get(m, "icon"),
      tags: get(m, "tags"),
      requires_approval: get(m, "requires_approval"),
      approval_policy: get(m, "approval_policy"),
      destructive: get(m, "destructive"),
      audit: get(m, "audit"),
      base_url: get(m, "base_url"),
      auth_scheme: get(m, "auth_scheme"),
      timeout_ms: get(m, "timeout_ms")
    }
  end

  defp field_from_map(m) do
    %FieldDef{
      id: get(m, "id"),
      type: str_to_atom(get(m, "type")),
      label: get(m, "label"),
      aria_label: get(m, "aria_label"),
      aria_desc: get(m, "aria_desc"),
      genie_fill: str_to_atom(get(m, "genie_fill")),
      required: get(m, "required"),
      default: get(m, "default"),
      placeholder: get(m, "placeholder"),
      pattern: get(m, "pattern"),
      max_length: get(m, "max_length"),
      min: get(m, "min"),
      max: get(m, "max"),
      step: get(m, "step"),
      min_offset_days: get(m, "min_offset_days"),
      max_offset_days: get(m, "max_offset_days"),
      rows: get(m, "rows"),
      options: Enum.map(get(m, "options") || [], &option_from_map/1),
      options_from: get(m, "options_from"),
      options_value_key: get(m, "options_value_key"),
      options_label_key: get(m, "options_label_key"),
      depends_on: get(m, "depends_on"),
      depends_on_value: get(m, "depends_on_value"),
      depends_on_behavior: str_to_atom(get(m, "depends_on_behavior")),
      group_id: get(m, "group_id"),
      hint: get(m, "hint"),
      style: get(m, "style"),
      href: get(m, "href"),
      action_id: get(m, "action_id"),
      value: get(m, "value"),
      value_key: get(m, "value_key"),
      columns: Enum.map(get(m, "columns") || [], &column_from_map/1),
      row_click: get(m, "row_click"),
      row_id_key: get(m, "row_id_key"),
      row_click_endpoint: get(m, "row_click_endpoint")
    }
  end

  defp column_from_map(m) do
    %ColumnDef{key: get(m, "key"), label: get(m, "label")}
  end

  defp option_from_map(m) do
    %OptionDef{value: get(m, "value"), label: get(m, "label"), description: get(m, "description")}
  end

  defp action_from_map(m) do
    %ActionDef{
      id: get(m, "id"),
      label: get(m, "label"),
      aria_label: get(m, "aria_label"),
      style: get(m, "style"),
      endpoint_id: get(m, "endpoint_id"),
      destructive: get(m, "destructive"),
      behavior: str_to_atom(get(m, "behavior"))
    }
  end

  defp endpoint_from_map(m) do
    %EndpointDef{
      id: get(m, "id"),
      method: get(m, "method"),
      path: get(m, "path"),
      trigger: str_to_atom(get(m, "trigger")),
      fills_field: get(m, "fills_field"),
      action_id: get(m, "action_id"),
      poll_interval_ms: get(m, "poll_interval_ms"),
      poll_until: get(m, "poll_until"),
      timeout_ms: get(m, "timeout_ms")
    }
  end

  defp group_from_map(m) do
    %GroupDef{
      id: get(m, "id"),
      label: get(m, "label"),
      aria_label: get(m, "aria_label"),
      collapsible: get(m, "collapsible")
    }
  end

  defp template_from_map(m) do
    %StatusTemplate{
      state: get(m, "state"),
      fields: Enum.map(get(m, "fields") || [], &field_from_map/1)
    }
  end

  defp get(m, key), do: Map.get(m, key)

  defp atom_to_str(nil), do: nil
  defp atom_to_str(a) when is_atom(a), do: Atom.to_string(a)
  defp atom_to_str(s) when is_binary(s), do: s

  defp str_to_atom(nil), do: nil
  defp str_to_atom(a) when is_atom(a), do: a

  defp str_to_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> s
  end
end
