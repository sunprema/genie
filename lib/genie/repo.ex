defmodule Genie.Repo do
  use Ecto.Repo,
    otp_app: :genie,
    adapter: Ecto.Adapters.Postgres
end
