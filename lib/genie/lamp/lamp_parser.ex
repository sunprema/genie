defmodule Genie.Lamp.LampParser do
  @behaviour Saxy.Handler

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

  @meta_text_elements ~w(title icon tags requires-approval approval-policy destructive audit base-url auth-scheme timeout-ms)

  @spec parse(String.t()) :: {:ok, LampDefinition.t()} | {:error, String.t()}
  def parse(xml_string) when is_binary(xml_string) do
    with {:ok, state} <- Saxy.parse_string(xml_string, __MODULE__, initial_state()),
         {:ok, defn} <- assemble(state),
         :ok <- validate(defn) do
      {:ok, defn}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "XML parse failed: #{inspect(reason)}"}
    end
  end

  defp initial_state do
    %{
      stack: [],
      lamp_id: nil,
      lamp_version: nil,
      lamp_category: nil,
      lamp_vendor: nil,
      meta: %{},
      endpoints: [],
      fields: [],
      groups: [],
      actions: [],
      status_templates: [],
      current_field: nil,
      current_endpoint: nil,
      current_action: nil,
      current_group: nil,
      current_template: nil,
      current_template_fields: [],
      current_description_id: nil,
      form_aria_label: nil,
      form_aria_describedby: nil,
      form_description_id: nil,
      form_description: nil,
      text: "",
      current_hint_id: nil,
      hints: %{}
    }
  end

  # --- SAX event handlers ---

  def handle_event(:start_document, _prolog, state), do: {:ok, state}
  def handle_event(:end_document, _data, state), do: {:ok, state}
  def handle_event(:cdata, _cdata, state), do: {:ok, state}

  def handle_event(:start_element, {"lamp", attrs}, state) do
    {:ok,
     %{
       state
       | stack: ["lamp" | state.stack],
         lamp_id: attr(attrs, "id"),
         lamp_version: attr(attrs, "version"),
         lamp_category: attr(attrs, "category"),
         lamp_vendor: attr(attrs, "vendor")
     }}
  end

  def handle_event(:start_element, {"form", attrs}, state) do
    {:ok,
     %{
       state
       | stack: ["form" | state.stack],
         form_aria_label: attr(attrs, "aria-label"),
         form_aria_describedby: attr(attrs, "aria-describedby")
     }}
  end

  def handle_event(:start_element, {"description", attrs}, state) do
    {:ok,
     %{
       state
       | stack: ["description" | state.stack],
         text: "",
         current_description_id: attr(attrs, "id")
     }}
  end

  def handle_event(:start_element, {"endpoint", attrs}, state) do
    endpoint = %EndpointDef{
      id: attr(attrs, "id"),
      method: attr(attrs, "method"),
      path: attr(attrs, "path"),
      trigger: parse_trigger(attr(attrs, "trigger")),
      fills_field: attr(attrs, "fills-field"),
      action_id: attr(attrs, "action-id"),
      poll_interval_ms: parse_int(attr(attrs, "poll-interval-ms")),
      poll_until: attr(attrs, "poll-until"),
      timeout_ms: parse_int(attr(attrs, "timeout-ms"))
    }

    {:ok, %{state | stack: ["endpoint" | state.stack], current_endpoint: endpoint}}
  end

  def handle_event(:start_element, {"field", attrs}, state) do
    field = %FieldDef{
      id: attr(attrs, "id"),
      type: parse_field_type(attr(attrs, "type")),
      label: attr(attrs, "label"),
      aria_label: attr(attrs, "aria-label"),
      aria_desc: attr(attrs, "aria-describedby"),
      genie_fill: parse_genie_fill(attr(attrs, "genie-fill")),
      required: parse_bool(attr(attrs, "required")),
      default: attr(attrs, "default"),
      placeholder: attr(attrs, "placeholder"),
      pattern: attr(attrs, "pattern"),
      max_length: parse_int(attr(attrs, "max-length")),
      min: parse_number(attr(attrs, "min")),
      max: parse_number(attr(attrs, "max")),
      step: parse_number(attr(attrs, "step")),
      min_offset_days: parse_int(attr(attrs, "min-offset-days")),
      max_offset_days: parse_int(attr(attrs, "max-offset-days")),
      rows: parse_int(attr(attrs, "rows")),
      options_from: attr(attrs, "options-from"),
      options_value_key: attr(attrs, "options-value-key"),
      options_label_key: attr(attrs, "options-label-key"),
      depends_on: attr(attrs, "depends-on"),
      depends_on_value: attr(attrs, "depends-on-value"),
      depends_on_behavior: parse_depends_behavior(attr(attrs, "depends-on-behavior")),
      options: [],
      columns: [],
      value: attr(attrs, "value"),
      value_key: attr(attrs, "value-key"),
      style: attr(attrs, "style"),
      href: attr(attrs, "href"),
      action_id: attr(attrs, "action-id")
    }

    {:ok, %{state | stack: ["field" | state.stack], current_field: field}}
  end

  def handle_event(:start_element, {"option", attrs}, state) do
    option = %OptionDef{
      value: attr(attrs, "value"),
      label: attr(attrs, "label"),
      description: attr(attrs, "description")
    }

    field = %{state.current_field | options: [option | state.current_field.options]}
    {:ok, %{state | stack: ["option" | state.stack], current_field: field}}
  end

  def handle_event(:start_element, {"column", attrs}, state) do
    col = %ColumnDef{key: attr(attrs, "key"), label: attr(attrs, "label")}
    field = %{state.current_field | columns: [col | state.current_field.columns]}
    {:ok, %{state | stack: ["column" | state.stack], current_field: field}}
  end

  def handle_event(:start_element, {"hint", attrs}, state) do
    {:ok,
     %{state | stack: ["hint" | state.stack], current_hint_id: attr(attrs, "id"), text: ""}}
  end

  def handle_event(:start_element, {"group", attrs}, state) do
    group = %GroupDef{
      id: attr(attrs, "id"),
      label: attr(attrs, "label"),
      aria_label: attr(attrs, "aria-label"),
      collapsible: parse_bool(attr(attrs, "collapsible"))
    }

    {:ok, %{state | stack: ["group" | state.stack], current_group: group}}
  end

  def handle_event(:start_element, {"action", attrs}, state) do
    action = %ActionDef{
      id: attr(attrs, "id"),
      label: attr(attrs, "label"),
      aria_label: attr(attrs, "aria-label"),
      style: attr(attrs, "style"),
      endpoint_id: attr(attrs, "endpoint-id"),
      destructive: parse_bool(attr(attrs, "destructive")),
      behavior: parse_behavior(attr(attrs, "behavior"))
    }

    {:ok, %{state | stack: ["action" | state.stack], current_action: action}}
  end

  def handle_event(:start_element, {"template", attrs}, state) do
    {:ok,
     %{
       state
       | stack: ["template" | state.stack],
         current_template: attr(attrs, "state"),
         current_template_fields: []
     }}
  end

  def handle_event(:start_element, {name, _attrs}, state) when name in @meta_text_elements do
    {:ok, %{state | stack: [name | state.stack], text: ""}}
  end

  def handle_event(:start_element, {name, _attrs}, state) do
    {:ok, %{state | stack: [name | state.stack]}}
  end

  # --- End element handlers ---

  def handle_event(:end_element, "endpoint", state) do
    {:ok,
     %{
       state
       | stack: tl(state.stack),
         endpoints: [state.current_endpoint | state.endpoints],
         current_endpoint: nil
     }}
  end

  def handle_event(:end_element, "field", state) do
    field = state.current_field
    rest = tl(state.stack)
    field = if "group" in rest, do: %{field | group_id: state.current_group.id}, else: field
    field = %{field | options: Enum.reverse(field.options || []), columns: Enum.reverse(field.columns || [])}

    if "template" in rest do
      {:ok,
       %{
         state
         | stack: rest,
           current_field: nil,
           current_template_fields: [field | state.current_template_fields]
       }}
    else
      {:ok, %{state | stack: rest, fields: [field | state.fields], current_field: nil}}
    end
  end

  def handle_event(:end_element, "hint", state) do
    hints = Map.put(state.hints, state.current_hint_id, String.trim(state.text))

    {:ok,
     %{state | stack: tl(state.stack), hints: hints, current_hint_id: nil, text: ""}}
  end

  def handle_event(:end_element, "group", state) do
    {:ok,
     %{
       state
       | stack: tl(state.stack),
         groups: [state.current_group | state.groups],
         current_group: nil
     }}
  end

  def handle_event(:end_element, "action", state) do
    {:ok,
     %{
       state
       | stack: tl(state.stack),
         actions: [state.current_action | state.actions],
         current_action: nil
     }}
  end

  def handle_event(:end_element, "template", state) do
    template = %StatusTemplate{
      state: state.current_template,
      fields: Enum.reverse(state.current_template_fields)
    }

    {:ok,
     %{
       state
       | stack: tl(state.stack),
         status_templates: [template | state.status_templates],
         current_template: nil,
         current_template_fields: []
     }}
  end

  def handle_event(:end_element, "description", state) do
    text = String.trim(state.text)
    rest = tl(state.stack)

    if "meta" in rest do
      {:ok,
       %{
         state
         | stack: rest,
           meta: Map.put(state.meta, :description, text),
           current_description_id: nil,
           text: ""
       }}
    else
      {:ok,
       %{
         state
         | stack: rest,
           form_description_id: state.current_description_id,
           form_description: text,
           current_description_id: nil,
           text: ""
       }}
    end
  end

  def handle_event(:end_element, name, state) when name in @meta_text_elements do
    key = meta_key(name)

    {:ok,
     %{
       state
       | stack: tl(state.stack),
         meta: Map.put(state.meta, key, String.trim(state.text)),
         text: ""
     }}
  end

  def handle_event(:end_element, _name, state) do
    {:ok, %{state | stack: tl(state.stack), text: ""}}
  end

  def handle_event(:characters, chars, state) do
    {:ok, %{state | text: state.text <> chars}}
  end

  # --- Assembly ---

  defp assemble(state) do
    meta =
      state.meta
      |> Map.update(:requires_approval, nil, &parse_bool/1)
      |> Map.update(:destructive, nil, &parse_bool/1)
      |> Map.update(:audit, nil, &parse_bool/1)
      |> Map.update(:timeout_ms, nil, &parse_int/1)
      |> then(&struct(MetaDef, &1))

    fields =
      state.fields
      |> Enum.reverse()
      |> Enum.map(fn field ->
        hint = if field.aria_desc, do: Map.get(state.hints, field.aria_desc), else: nil
        %{field | hint: hint}
      end)

    defn = %LampDefinition{
      id: state.lamp_id,
      version: state.lamp_version,
      category: state.lamp_category,
      vendor: state.lamp_vendor,
      meta: meta,
      endpoints: Enum.reverse(state.endpoints),
      fields: fields,
      groups: Enum.reverse(state.groups),
      actions: Enum.reverse(state.actions),
      status_templates: Enum.reverse(state.status_templates),
      form_aria_label: state.form_aria_label,
      form_aria_describedby: state.form_aria_describedby,
      form_description_id: state.form_description_id,
      form_description: state.form_description
    }

    {:ok, defn}
  end

  # --- Validation ---

  defp validate(defn) do
    with :ok <- validate_id(defn),
         :ok <- validate_fields_present(defn),
         :ok <- validate_action_endpoint_refs(defn),
         :ok <- validate_options_from_refs(defn),
         :ok <- validate_depends_on_refs(defn),
         :ok <- validate_aria_labels(defn),
         :ok <- validate_genie_fill_values(defn),
         :ok <- validate_primary_action(defn) do
      :ok
    end
  end

  defp validate_id(%{id: nil}),
    do: {:error, "lamp id is required"}

  defp validate_id(%{id: id}) do
    if Regex.match?(~r/^[^.\s]+\.[^.\s]+\.[^.\s]+$/, id) do
      :ok
    else
      {:error, "lamp id must match pattern {vendor}.{service}.{action}, got: #{id}"}
    end
  end

  defp validate_fields_present(%{fields: fields}) when length(fields) > 0, do: :ok
  defp validate_fields_present(_), do: {:error, "lamp must define at least one field"}

  defp validate_action_endpoint_refs(%{actions: actions, endpoints: endpoints}) do
    endpoint_ids = MapSet.new(endpoints, & &1.id)

    Enum.reduce_while(actions, :ok, fn action, :ok ->
      if action.endpoint_id && action.endpoint_id not in endpoint_ids do
        {:halt,
         {:error,
          "action #{action.id} references undefined endpoint #{action.endpoint_id}"}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_options_from_refs(%{fields: fields, endpoints: endpoints}) do
    endpoint_ids = MapSet.new(endpoints, & &1.id)

    Enum.reduce_while(fields, :ok, fn field, :ok ->
      if field.options_from && field.options_from not in endpoint_ids do
        {:halt,
         {:error,
          "field #{field.id} options-from references undefined endpoint #{field.options_from}"}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_depends_on_refs(%{fields: fields}) do
    field_ids = MapSet.new(fields, & &1.id)

    Enum.reduce_while(fields, :ok, fn field, :ok ->
      if field.depends_on && field.depends_on not in field_ids do
        {:halt,
         {:error, "field #{field.id} depends-on references undefined field #{field.depends_on}"}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_aria_labels(%{fields: fields, actions: actions, status_templates: templates}) do
    with :ok <- check_aria_on(fields, "field"),
         :ok <- check_aria_on(actions, "action"),
         :ok <- check_template_aria(templates) do
      :ok
    end
  end

  defp check_aria_on(items, kind) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      if item.aria_label do
        {:cont, :ok}
      else
        {:halt, {:error, "#{kind} #{item.id || "unknown"} is missing aria-label"}}
      end
    end)
  end

  defp check_template_aria(templates) do
    Enum.reduce_while(templates, :ok, fn tmpl, :ok ->
      result =
        Enum.reduce_while(tmpl.fields, :ok, fn field, :ok ->
          if field.aria_label do
            {:cont, :ok}
          else
            {:halt,
             {:error, "status template field in state #{tmpl.state} is missing aria-label"}}
          end
        end)

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_genie_fill_values(%{fields: fields}) do
    valid = [:from_context, :infer, :none, nil]

    Enum.reduce_while(fields, :ok, fn field, :ok ->
      if field.genie_fill in valid do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          "field #{field.id || "unknown"} has invalid genie-fill: #{inspect(field.genie_fill)}. Must be from-context, infer, or none"}}
      end
    end)
  end

  defp validate_primary_action(%{fields: fields, actions: actions}) do
    has_required = Enum.any?(fields, & &1.required)
    has_primary = Enum.any?(actions, &(&1.style == "primary"))

    if has_required && !has_primary do
      {:error, "lamp has required fields but no primary action defined"}
    else
      :ok
    end
  end

  # --- Helpers ---

  defp attr(attrs, name), do: Enum.find_value(attrs, fn {k, v} -> if k == name, do: v end)

  defp meta_key("requires-approval"), do: :requires_approval
  defp meta_key("approval-policy"), do: :approval_policy
  defp meta_key("base-url"), do: :base_url
  defp meta_key("auth-scheme"), do: :auth_scheme
  defp meta_key("timeout-ms"), do: :timeout_ms
  defp meta_key(name), do: String.to_existing_atom(name)

  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool(nil), do: nil
  defp parse_bool(_), do: false

  defp parse_int(nil), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(nil), do: nil

  defp parse_number(s) do
    case Integer.parse(s) do
      {n, ""} ->
        n

      _ ->
        case Float.parse(s) do
          {f, ""} -> f
          _ -> nil
        end
    end
  end

  defp parse_genie_fill("from-context"), do: :from_context
  defp parse_genie_fill("infer"), do: :infer
  defp parse_genie_fill("none"), do: :none
  defp parse_genie_fill(nil), do: nil
  defp parse_genie_fill(other), do: other

  defp parse_field_type("text"), do: :text
  defp parse_field_type("textarea"), do: :textarea
  defp parse_field_type("select"), do: :select
  defp parse_field_type("radio"), do: :radio
  defp parse_field_type("toggle"), do: :toggle
  defp parse_field_type("number"), do: :number
  defp parse_field_type("date"), do: :date
  defp parse_field_type("checkbox-group"), do: :checkbox_group
  defp parse_field_type("hidden"), do: :hidden
  defp parse_field_type("spinner"), do: :spinner
  defp parse_field_type("banner"), do: :banner
  defp parse_field_type("link"), do: :link
  defp parse_field_type("action"), do: :action
  defp parse_field_type("table"), do: :table
  defp parse_field_type(nil), do: nil
  defp parse_field_type(other), do: other

  defp parse_trigger("on-load"), do: :on_load
  defp parse_trigger("on-submit"), do: :on_submit
  defp parse_trigger("on-complete"), do: :on_complete
  defp parse_trigger("on-change"), do: :on_change
  defp parse_trigger("webhook"), do: :webhook
  defp parse_trigger(nil), do: nil

  defp parse_depends_behavior("show"), do: :show
  defp parse_depends_behavior("hide"), do: :hide
  defp parse_depends_behavior("enable"), do: :enable
  defp parse_depends_behavior("disable"), do: :disable
  defp parse_depends_behavior(nil), do: nil

  defp parse_behavior("submit"), do: :submit
  defp parse_behavior("reset-form"), do: :reset_form
  defp parse_behavior("cancel"), do: :cancel
  defp parse_behavior(nil), do: nil
end
