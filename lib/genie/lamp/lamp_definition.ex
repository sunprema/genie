defmodule Genie.Lamp.LampDefinition do
  @moduledoc false
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
  @moduledoc false
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
    :timeout_ms,
    :runtime,
    :handler
  ]
end

defmodule Genie.Lamp.ColumnDef do
  @moduledoc false
  defstruct [:key, :label]
end

defmodule Genie.Lamp.FieldDef do
  @moduledoc false
  @type t :: %__MODULE__{}

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
    :value_key,
    :columns,
    :row_click,
    :row_id_key,
    :row_click_endpoint,
    value: nil
  ]
end

defmodule Genie.Lamp.OptionDef do
  @moduledoc false
  defstruct [:value, :label, :description]
end

defmodule Genie.Lamp.ActionDef do
  @moduledoc false
  defstruct [:id, :label, :aria_label, :style, :endpoint_id, :destructive, :behavior]
end

defmodule Genie.Lamp.EndpointDef do
  @moduledoc false
  @type t :: %__MODULE__{}

  defstruct [
    :id,
    :method,
    :path,
    :trigger,
    :fills_field,
    :action_id,
    :poll_interval_ms,
    :poll_until,
    :timeout_ms,
    response_keys: []
  ]
end

defmodule Genie.Lamp.ResponseKeyDef do
  @moduledoc false
  defstruct [:name, :type, :required]
end

defmodule Genie.Lamp.GroupDef do
  @moduledoc false
  defstruct [:id, :label, :aria_label, :collapsible]
end

defmodule Genie.Lamp.StatusTemplate do
  @moduledoc false
  defstruct [:state, :fields]
end
