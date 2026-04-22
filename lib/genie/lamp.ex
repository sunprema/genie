defmodule Genie.Lamp do
  use Ash.Domain, otp_app: :genie

  resources do
    resource Genie.Lamp.LampRegistry
  end
end
