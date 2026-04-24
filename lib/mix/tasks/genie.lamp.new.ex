defmodule Mix.Tasks.Genie.Lamp.New do
  @shortdoc "Generates a new inline lamp: XML + handler module + test"

  @moduledoc """
  Scaffolds a new inline Genie lamp.

      mix genie.lamp.new vendor.service.action

  For example:

      mix genie.lamp.new aws.s3.delete-bucket

  Generates three files:

    * `priv/lamps/aws_s3_delete_bucket.xml` — lamp definition
    * `lib/genie/lamps/aws/s3_delete_bucket.ex` — handler module stub
    * `test/genie/lamps/aws/s3_delete_bucket_test.exs` — handler test stub

  The generated module name follows `Genie.Lamps.<Vendor>.<ServiceAction>` with
  `Macro.camelize/1` applied. Adjust the module name in both the handler file
  and the XML's `<handler>` element if your brand uses non-standard casing
  (for example `AWS` or `GitHub`).

  Pass `--dir <path>` to generate into a different base directory (used by tests).
  """

  use Mix.Task

  @switches [dir: :string, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("loadpaths")

    {opts, positional, _invalid} = OptionParser.parse(argv, switches: @switches)

    lamp_id =
      case positional do
        [id] ->
          id

        _ ->
          Mix.raise(
            "expected exactly one positional argument: mix genie.lamp.new vendor.service.action"
          )
      end

    base_dir = Keyword.get(opts, :dir) || File.cwd!()
    force? = Keyword.get(opts, :force, false)

    lamp = parse_lamp_id!(lamp_id)

    xml_path = Path.join([base_dir, "priv", "lamps", "#{lamp.file_stem}.xml"])
    handler_path = Path.join([base_dir, "lib", "genie", "lamps", lamp.vendor_snake, "#{lamp.service_action_snake}.ex"])
    test_path = Path.join([base_dir, "test", "genie", "lamps", lamp.vendor_snake, "#{lamp.service_action_snake}_test.exs"])

    for path <- [xml_path, handler_path, test_path], File.exists?(path) and not force? do
      Mix.raise("refusing to overwrite #{path} — pass --force to overwrite")
    end

    create_file(xml_path, render_xml(lamp))
    create_file(handler_path, render_handler(lamp))
    create_file(test_path, render_test(lamp))

    Mix.shell().info("""

    Next steps:
      1. Edit #{xml_path} — flesh out the form, endpoints, and templates.
      2. Edit #{handler_path} — implement handle_endpoint/3 for each endpoint.
      3. Run mix genie.lamp.verify to check the lamp/handler contract.
      4. Register the lamp: mix genie.lamps.load
    """)
  end

  defp parse_lamp_id!(id) do
    parts = String.split(id, ".")

    unless length(parts) == 3 do
      Mix.raise(~s(lamp id must have exactly three dot-separated parts: got "#{id}"))
    end

    [vendor, service, action] = parts

    for part <- parts, part == "" or String.contains?(part, " ") do
      Mix.raise(~s(lamp id parts cannot be empty or contain spaces: got "#{id}"))
    end

    vendor_snake = snake(vendor)
    service_snake = snake(service)
    action_snake = snake(action)
    service_action_snake = "#{service_snake}_#{action_snake}"

    %{
      lamp_id: id,
      vendor: vendor,
      service: service,
      action: action,
      vendor_snake: vendor_snake,
      service_snake: service_snake,
      action_snake: action_snake,
      service_action_snake: service_action_snake,
      file_stem: "#{vendor_snake}_#{service_action_snake}",
      module:
        "Genie.Lamps.#{Macro.camelize(vendor_snake)}.#{Macro.camelize(service_snake)}#{Macro.camelize(action_snake)}",
      title:
        "#{Macro.camelize(vendor_snake)} #{Macro.camelize(service_snake)} #{Macro.camelize(action_snake)}"
    }
  end

  defp snake(str) do
    str
    |> String.replace("-", "_")
    |> String.downcase()
  end

  defp create_file(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    Mix.shell().info("  * created #{Path.relative_to_cwd(path)}")
  end

  defp render_xml(lamp) do
    template_path =
      :code.priv_dir(:genie)
      |> to_string()
      |> Path.join("lamp_templates/inline_lamp.xml.eex")

    EEx.eval_file(template_path,
      assigns: [
        lamp_id: lamp.lamp_id,
        vendor: lamp.vendor,
        service: lamp.service,
        action: lamp.action,
        module: lamp.module,
        title: lamp.title
      ]
    )
  end

  defp render_handler(lamp) do
    """
    defmodule #{lamp.module} do
      @moduledoc \"\"\"
      Inline handler for the `#{lamp.lamp_id}` lamp.
      \"\"\"

      use Genie.Lamp.Handler, lamp_id: "#{lamp.lamp_id}"

      @endpoint "submit"
      def handle_endpoint("submit", _params, _ctx) do
        {:ok, %{"state" => "ready", "message" => "replace me"}}
      end
    end
    """
  end

  defp render_test(lamp) do
    """
    defmodule #{lamp.module}Test do
      use ExUnit.Case, async: true

      alias Genie.Lamp.Handler.Context
      alias #{lamp.module}

      defp ctx do
        %Context{
          lamp_id: "#{lamp.lamp_id}",
          endpoint_id: "submit",
          session_id: "t",
          trace_id: "trace-1"
        }
      end

      test "submit returns a ready response" do
        assert {:ok, response} = #{module_name_alias(lamp.module)}.handle_endpoint("submit", %{}, ctx())
        assert response["state"] == "ready"
      end
    end
    """
  end

  defp module_name_alias(full), do: full |> String.split(".") |> List.last()
end
