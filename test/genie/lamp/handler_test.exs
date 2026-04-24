defmodule Genie.Lamp.HandlerTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.{Compiler, Context}

  describe "Context struct" do
    test "requires lamp_id, endpoint_id, and trace_id" do
      assert_raise ArgumentError, fn ->
        struct!(Context, session_id: "s")
      end

      ctx = struct!(Context, lamp_id: "a.b.c", endpoint_id: "run", trace_id: "t")
      assert ctx.lamp_id == "a.b.c"
      assert ctx.endpoint_id == "run"
      assert ctx.trace_id == "t"
      assert ctx.metadata == %{}
    end
  end

  describe "Compiler.expected_endpoints/1" do
    test "returns endpoint IDs for a known lamp" do
      assert {:ok, ids} = Compiler.expected_endpoints("aws.s3.create-bucket")
      assert "load_regions" in ids
      assert "create_bucket" in ids
      assert "poll_status" in ids
    end

    test "returns error for an unknown lamp" do
      assert {:error, _} = Compiler.expected_endpoints("does.not.exist")
    end

    test "returns error when lamp_id is nil" do
      assert {:error, :missing_lamp_id} = Compiler.expected_endpoints(nil)
    end
  end

  describe "use Genie.Lamp.Handler — compile-time check" do
    import ExUnit.CaptureIO

    test "warns when a declared endpoint has no @endpoint clause" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Genie.Lamp.HandlerTest.MissingClause do
            use Genie.Lamp.Handler, lamp_id: "aws.s3.create-bucket"

            @endpoint "load_regions"
            def handle_endpoint("load_regions", _p, _c), do: {:ok, []}
          end
          """)
        end)

      assert warnings =~ "create_bucket"
      assert warnings =~ "poll_status"
    end

    test "no warning when every declared endpoint has an @endpoint clause" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Genie.Lamp.HandlerTest.CompleteHandler do
            use Genie.Lamp.Handler, lamp_id: "aws.s3.create-bucket"

            @endpoint "load_regions"
            def handle_endpoint("load_regions", _p, _c), do: {:ok, []}

            @endpoint "create_bucket"
            def handle_endpoint("create_bucket", _p, _c), do: {:ok, %{"state" => "submitting"}}

            @endpoint "poll_status"
            def handle_endpoint("poll_status", _p, _c), do: {:ok, %{"state" => "ready", "status" => "ready"}}
          end
          """)
        end)

      refute warnings =~ "missing @endpoint"
    end

    test "warns when handler declares @endpoint not in the lamp" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Genie.Lamp.HandlerTest.ExtraClause do
            use Genie.Lamp.Handler, lamp_id: "aws.s3.create-bucket"

            @endpoint "load_regions"
            def handle_endpoint("load_regions", _p, _c), do: {:ok, []}

            @endpoint "create_bucket"
            def handle_endpoint("create_bucket", _p, _c), do: {:ok, %{}}

            @endpoint "poll_status"
            def handle_endpoint("poll_status", _p, _c), do: {:ok, %{}}

            @endpoint "phantom"
            def handle_endpoint("phantom", _p, _c), do: {:ok, %{}}
          end
          """)
        end)

      assert warnings =~ "phantom"
      assert warnings =~ "not declared"
    end

    test "warns when the lamp_id does not exist" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Genie.Lamp.HandlerTest.UnknownLamp do
            use Genie.Lamp.Handler, lamp_id: "no.such.lamp"

            def handle_endpoint(_, _, _), do: {:ok, %{}}
          end
          """)
        end)

      assert warnings =~ "could not verify endpoints"
    end
  end
end
