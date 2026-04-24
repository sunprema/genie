defmodule Genie.Lamps.AWS.Regions do
  @moduledoc "Shared AWS region catalog used by lamps that have a region selector."

  @regions [
    %{"code" => "us-east-1", "name" => "US East (N. Virginia)"},
    %{"code" => "us-east-2", "name" => "US East (Ohio)"},
    %{"code" => "us-west-1", "name" => "US West (N. California)"},
    %{"code" => "us-west-2", "name" => "US West (Oregon)"},
    %{"code" => "eu-west-1", "name" => "EU (Ireland)"},
    %{"code" => "eu-central-1", "name" => "EU (Frankfurt)"},
    %{"code" => "ap-southeast-1", "name" => "Asia Pacific (Singapore)"}
  ]

  def list, do: @regions
end
