defmodule Genie.Bridge.VaultClient do
  @moduledoc "Retrieves temporary scoped credentials for lamp auth schemes."

  @spec get_scoped_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_scoped_token(auth_scheme) when is_binary(auth_scheme) do
    token =
      Application.get_env(:genie, :bridge_token) ||
        System.get_env("GENIE_BRIDGE_TOKEN", "dev-token")

    {:ok, token}
  end
end
