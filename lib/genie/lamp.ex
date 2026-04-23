defmodule Genie.Lamp do
  @moduledoc false
  use Ash.Domain, otp_app: :genie

  resources do
    resource Genie.Lamp.LampRegistry
  end
end
