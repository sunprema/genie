defmodule Genie.Orchestrator.Steps.PushCockpitStepTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.Steps.PushCockpitStep
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Audit.AuditLog

  defp create_org!, do: Organisation |> Ash.Changeset.for_create(:create, %{name: "Org#{System.unique_integer([:positive])}", slug: "org-#{System.unique_integer([:positive])}"}) |> Ash.create!(authorize?: false)

  defp create_user!(org) do
    n = System.unique_integer([:positive])
    user = User |> Ash.Changeset.for_create(:register_with_password, %{email: "u-#{n}@t.com", password: "password123", password_confirmation: "password123"}) |> Ash.create!(authorize?: false)
    user |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: :admin}) |> Ash.update!(authorize?: false)
  end

  describe "run/3 — canvas push" do
    test "broadcasts update_canvas event and writes audit log" do
      org = create_org!()
      actor = create_user!(org)
      session_id = Ecto.UUID.generate()
      html = "<div>Test canvas</div>"

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      assert {:ok, :sent} =
               PushCockpitStep.run(
                 %{
                   ui_result: %{type: :canvas, html: html, lamp_id: "aws.s3.create-bucket"},
                   session_id: session_id,
                   actor: actor
                 },
                 %{},
                 []
               )

      assert_receive {:push_canvas, ^html}

      {:ok, logs} = Ash.read(AuditLog, authorize?: false)
      matching_logs = Enum.filter(logs, &(&1.session_id == session_id))
      assert Enum.any?(matching_logs, &(&1.result == :success))
    end
  end

  describe "run/3 — chat push" do
    test "broadcasts chat message" do
      org = create_org!()
      actor = create_user!(org)
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      assert {:ok, :sent} =
               PushCockpitStep.run(
                 %{
                   ui_result: %{type: :chat, message: "Agent response", html: nil, lamp_id: nil},
                   session_id: session_id,
                   actor: actor
                 },
                 %{},
                 []
               )

      assert_receive {:push_chat, "Agent response"}
    end
  end

  describe "undo/4" do
    test "always returns :ok" do
      assert :ok =
               PushCockpitStep.undo(
                 :sent,
                 %{session_id: "test", ui_result: %{}},
                 %{},
                 []
               )
    end
  end
end
