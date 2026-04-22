defmodule Genie.Lamp.LampDefinition do
  @type t :: %__MODULE__{}

  defstruct [
    :id,
    :version,
    :category,
    :vendor,
    :meta,
    :endpoints,
    :fields,
    :groups,
    :actions,
    :status_templates,
    :form_aria_label,
    :form_aria_describedby,
    :form_description_id,
    :form_description
  ]
end

defmodule Genie.Lamp.MetaDef do
  defstruct [
    :title,
    :description,
    :icon,
    :tags,
    :requires_approval,
    :approval_policy,
    :destructive,
    :audit,
    :base_url,
    :auth_scheme,
    :timeout_ms
  ]
end

defmodule Genie.Lamp.FieldDef do
  defstruct [
    :id,
    :type,
    :label,
    :aria_label,
    :aria_desc,
    :genie_fill,
    :required,
    :default,
    :placeholder,
    :pattern,
    :max_length,
    :min,
    :max,
    :step,
    :min_offset_days,
    :max_offset_days,
    :rows,
    :options,
    :options_from,
    :options_value_key,
    :options_label_key,
    :depends_on,
    :depends_on_value,
    :depends_on_behavior,
    :group_id,
    :hint,
    :style,
    :href,
    :action_id,
    value: nil
  ]
end

defmodule Genie.Lamp.OptionDef do
  defstruct [:value, :label, :description]
end

defmodule Genie.Lamp.ActionDef do
  defstruct [:id, :label, :aria_label, :style, :endpoint_id, :destructive, :behavior]
end

defmodule Genie.Lamp.EndpointDef do
  defstruct [
    :id,
    :method,
    :path,
    :trigger,
    :fills_field,
    :action_id,
    :poll_interval_ms,
    :poll_until,
    :timeout_ms
  ]
end

defmodule Genie.Lamp.GroupDef do
  defstruct [:id, :label, :aria_label, :collapsible]
end

defmodule Genie.Lamp.StatusTemplate do
  defstruct [:state, :fields]
end
