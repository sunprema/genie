defmodule Genie.Lamps.AWS.EC2ListInstances do
  @moduledoc """
  Inline handler for the `aws.ec2.list-instances` lamp. Serves static demo data;
  a future version will call the EC2 DescribeInstances API.
  """

  use Genie.Lamp.Handler, lamp_id: "aws.ec2.list-instances"

  alias Genie.Lamps.AWS.Regions

  @endpoint "load_regions"
  def handle_endpoint("load_regions", _params, _ctx), do: {:ok, Regions.list()}

  @endpoint "list_instances"
  def handle_endpoint("list_instances", params, _ctx) do
    region = Map.get(params, "region", "us-east-1")
    state_filter = Map.get(params, "state", "running")

    all = [
      %{
        "instance_id" => "i-0a1b2c3d4e5f6a7b8",
        "instance_type" => "t3.micro",
        "state" => "running",
        "availability_zone" => "#{region}a",
        "public_ip" => "54.210.12.34"
      },
      %{
        "instance_id" => "i-0b2c3d4e5f6a7b8c9",
        "instance_type" => "m5.large",
        "state" => "running",
        "availability_zone" => "#{region}b",
        "public_ip" => "18.234.56.78"
      },
      %{
        "instance_id" => "i-0c3d4e5f6a7b8c9d0",
        "instance_type" => "t3.small",
        "state" => "stopped",
        "availability_zone" => "#{region}a",
        "public_ip" => nil
      }
    ]

    instances =
      if state_filter == "all" do
        all
      else
        Enum.filter(all, &(&1["state"] == state_filter))
      end

    {:ok, %{"state" => "ready", "region" => region, "instances" => instances}}
  end
end
