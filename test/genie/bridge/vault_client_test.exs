defmodule Genie.Bridge.VaultClientTest do
  use ExUnit.Case, async: true

  alias Genie.Bridge.VaultClient

  describe "get_scoped_token/1" do
    test "returns ok with configured bridge token" do
      Application.put_env(:genie, :bridge_token, "test-token-123")
      on_exit(fn -> Application.delete_env(:genie, :bridge_token) end)

      assert {:ok, "test-token-123"} = VaultClient.get_scoped_token("aws")
    end

    test "returns ok with default dev-token when no env configured" do
      Application.delete_env(:genie, :bridge_token)
      assert {:ok, token} = VaultClient.get_scoped_token("aws")
      assert is_binary(token)
    end

    test "returns ok for any auth scheme string" do
      assert {:ok, _} = VaultClient.get_scoped_token("bearer")
      assert {:ok, _} = VaultClient.get_scoped_token("api_key")
    end
  end
end
