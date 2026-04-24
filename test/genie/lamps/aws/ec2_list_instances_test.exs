defmodule Genie.Lamps.AWS.EC2ListInstancesTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.AWS.EC2ListInstances

  defp ctx(endpoint_id) do
    %Context{
      lamp_id: "aws.ec2.list-instances",
      endpoint_id: endpoint_id,
      session_id: "t",
      trace_id: "trace-1"
    }
  end

  describe "load_regions" do
    test "returns a non-empty region list with code + name" do
      assert {:ok, regions} = EC2ListInstances.handle_endpoint("load_regions", %{}, ctx("load_regions"))
      assert is_list(regions)
      assert Enum.any?(regions, &(&1["code"] == "us-east-1"))
      assert Enum.all?(regions, &(&1["code"] && &1["name"]))
    end
  end

  describe "list_instances" do
    test "filters by state=running by default" do
      {:ok, response} =
        EC2ListInstances.handle_endpoint(
          "list_instances",
          %{"region" => "us-east-1"},
          ctx("list_instances")
        )

      assert response["state"] == "ready"
      assert Enum.all?(response["instances"], &(&1["state"] == "running"))
    end

    test "state=all returns instances in all states" do
      {:ok, response} =
        EC2ListInstances.handle_endpoint(
          "list_instances",
          %{"region" => "us-east-1", "state" => "all"},
          ctx("list_instances")
        )

      states = Enum.map(response["instances"], & &1["state"]) |> Enum.uniq()
      assert "running" in states
      assert "stopped" in states
    end

    test "availability zones include the requested region prefix" do
      {:ok, response} =
        EC2ListInstances.handle_endpoint(
          "list_instances",
          %{"region" => "eu-west-1", "state" => "all"},
          ctx("list_instances")
        )

      assert Enum.all?(response["instances"], fn i ->
               String.starts_with?(i["availability_zone"], "eu-west-1")
             end)
    end
  end
end
