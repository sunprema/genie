defmodule Genie.Audit do
  @moduledoc false
  use Ash.Domain, otp_app: :genie

  resources do
    resource Genie.Audit.AuditLog
  end
end
