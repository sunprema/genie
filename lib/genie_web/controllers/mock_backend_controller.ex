defmodule GenieWeb.MockBackendController do
  @moduledoc "Dev-only mock backend that simulates lamp API endpoints."
  use GenieWeb, :controller

  def regions(conn, _params) do
    json(conn, [
      %{code: "us-east-1", name: "US East (N. Virginia)"},
      %{code: "us-east-2", name: "US East (Ohio)"},
      %{code: "us-west-1", name: "US West (N. California)"},
      %{code: "us-west-2", name: "US West (Oregon)"},
      %{code: "eu-west-1", name: "EU (Ireland)"},
      %{code: "eu-central-1", name: "EU (Frankfurt)"},
      %{code: "ap-southeast-1", name: "Asia Pacific (Singapore)"}
    ])
  end

  def ec2_instances(conn, params) do
    region = Map.get(params, "region", "us-east-1")
    state_filter = Map.get(params, "state", "running")

    all_instances = [
      %{
        instance_id: "i-0a1b2c3d4e5f6a7b8",
        instance_type: "t3.micro",
        state: "running",
        availability_zone: "#{region}a",
        public_ip: "54.210.12.34"
      },
      %{
        instance_id: "i-0b2c3d4e5f6a7b8c9",
        instance_type: "m5.large",
        state: "running",
        availability_zone: "#{region}b",
        public_ip: "18.234.56.78"
      },
      %{
        instance_id: "i-0c3d4e5f6a7b8c9d0",
        instance_type: "t3.small",
        state: "stopped",
        availability_zone: "#{region}a",
        public_ip: nil
      }
    ]

    instances =
      if state_filter == "all" do
        all_instances
      else
        Enum.filter(all_instances, &(&1.state == state_filter))
      end

    json(conn, %{state: "ready", region: region, instances: instances})
  end
end
