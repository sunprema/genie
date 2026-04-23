defmodule Genie.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Genie.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:genie, :token_signing_secret)
  end
end
