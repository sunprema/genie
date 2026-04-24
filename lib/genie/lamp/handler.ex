defmodule Genie.Lamp.Handler do
  @moduledoc """
  Behaviour implemented by inline lamp handlers.

  A handler module declares which lamp it serves via
  `use Genie.Lamp.Handler, lamp_id: "vendor.service.action"`,
  then provides one `handle_endpoint/3` clause per endpoint declared in the
  lamp XML. Declare each clause with a preceding `@endpoint "<endpoint_id>"`
  attribute so the compile-time check can verify coverage.

      defmodule Genie.Lamps.AWS.S3CreateBucket do
        use Genie.Lamp.Handler, lamp_id: "aws.s3.create-bucket"

        @endpoint "load_regions"
        def handle_endpoint("load_regions", _params, _ctx),
          do: {:ok, [%{"code" => "us-east-1", "name" => "US East"}]}

        @endpoint "create_bucket"
        def handle_endpoint("create_bucket", params, ctx) do
          {:ok, %{"state" => "submitting", "bucket_name" => params["bucket_name"]}}
        end
      end

  Optional `handle_options/2` lets handlers serve option lists for
  `fills-field` endpoints with a different shape from ordinary responses.
  If not defined, `handle_endpoint/3` is called with empty params and must
  return `{:ok, [map()]}`.
  """

  alias Genie.Lamp.Handler.Context

  @type endpoint_id :: String.t()
  @type params :: map()
  @type response :: map()

  @callback handle_endpoint(endpoint_id, params, Context.t()) ::
              {:ok, response} | {:error, term()}

  @callback handle_options(endpoint_id, Context.t()) ::
              {:ok, [map()]} | {:error, term()}

  @optional_callbacks handle_options: 2

  defmacro __using__(opts) do
    lamp_id = Keyword.fetch!(opts, :lamp_id)

    quote do
      @behaviour Genie.Lamp.Handler
      Module.register_attribute(__MODULE__, :endpoint, accumulate: true, persist: true)
      @genie_lamp_id unquote(lamp_id)
      @before_compile Genie.Lamp.Handler.Compiler

      def __genie_lamp_id__, do: unquote(lamp_id)
    end
  end
end
