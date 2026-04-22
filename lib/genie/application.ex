defmodule Genie.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GenieWeb.Telemetry,
      Genie.Repo,
      {DNSCluster, query: Application.get_env(:genie, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:genie, :ash_domains),
         Application.fetch_env!(:genie, Oban)
       )},
      {Phoenix.PubSub, name: Genie.PubSub},
      # Start a worker by calling: Genie.Worker.start_link(arg)
      # {Genie.Worker, arg},
      # Start to serve requests, typically the last entry
      GenieWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :genie]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Genie.Supervisor]
    result = Supervisor.start_link(children, opts)

    if Application.get_env(:genie, :load_lamps_on_startup, false) do
      Task.start(fn -> Genie.Lamp.Loader.load_all() end)
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GenieWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
