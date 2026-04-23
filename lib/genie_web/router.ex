defmodule GenieWeb.Router do
  use GenieWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GenieWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", GenieWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      live "/cockpit", CockpitLive
    end
  end

  scope "/", GenieWeb do
    pipe_through :api

    post "/webhooks/:lamp_id", WebhookController, :create
    get "/health", HealthController, :index
  end

  scope "/", GenieWeb do
    pipe_through :browser

    get "/", PageController, :home

    auth_routes AuthController, Genie.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{GenieWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    GenieWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  GenieWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Genie.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [GenieWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Genie.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [GenieWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", GenieWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:genie, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GenieWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end

    # Mock lamp backends — simulates real AWS endpoints locally
    scope "/genie", GenieWeb do
      pipe_through :api

      get "/aws/regions", MockBackendController, :regions
      post "/aws/s3/buckets", MockBackendController, :create_s3_bucket
      get "/aws/s3/buckets/:bucket_name/status", MockBackendController, :s3_bucket_status
      get "/aws/ec2/instances", MockBackendController, :ec2_instances
      get "/pagerduty/incidents", MockBackendController, :pagerduty_incidents
      get "/github/pulls", MockBackendController, :github_pull_requests
      get "/github/pulls/:id", MockBackendController, :github_pr_detail
      get "/elixir/processes", MockBackendController, :elixir_processes
      get "/elixir/processes/:pid", MockBackendController, :elixir_process_detail
    end
  end

  if Application.compile_env(:genie, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
