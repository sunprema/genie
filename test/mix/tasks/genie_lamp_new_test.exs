defmodule Mix.Tasks.Genie.Lamp.NewTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Genie.Lamp.LampParser
  alias Mix.Tasks.Genie.Lamp.New, as: NewTask

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "genie_lamp_new_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  test "generates three files for a well-formed lamp id" do
    dir = tmp_dir()

    capture_io(fn -> NewTask.run(["example.demo.hello", "--dir", dir]) end)

    assert File.exists?(Path.join([dir, "priv/lamps/example_demo_hello.xml"]))
    assert File.exists?(Path.join([dir, "lib/genie/lamps/example/demo_hello.ex"]))
    assert File.exists?(Path.join([dir, "test/genie/lamps/example/demo_hello_test.exs"]))
  end

  test "generated XML parses cleanly through LampParser" do
    dir = tmp_dir()
    capture_io(fn -> NewTask.run(["example.demo.hello", "--dir", dir]) end)

    xml = File.read!(Path.join([dir, "priv/lamps/example_demo_hello.xml"]))
    assert {:ok, defn} = LampParser.parse(xml)
    assert defn.id == "example.demo.hello"
    assert defn.meta.runtime == "inline"
    assert defn.meta.handler == "Genie.Lamps.Example.DemoHello"
    assert Enum.map(defn.endpoints, & &1.id) == ["submit"]
  end

  test "generated handler references the correct lamp id and endpoint" do
    dir = tmp_dir()
    capture_io(fn -> NewTask.run(["example.demo.hello", "--dir", dir]) end)

    handler = File.read!(Path.join([dir, "lib/genie/lamps/example/demo_hello.ex"]))
    assert handler =~ ~s(defmodule Genie.Lamps.Example.DemoHello do)
    assert handler =~ ~s(use Genie.Lamp.Handler, lamp_id: "example.demo.hello")
    assert handler =~ ~s(@endpoint "submit")
  end

  test "handles hyphens in action names" do
    dir = tmp_dir()
    capture_io(fn -> NewTask.run(["aws.s3.delete-bucket", "--dir", dir]) end)

    assert File.exists?(Path.join([dir, "priv/lamps/aws_s3_delete_bucket.xml"]))
    assert File.exists?(Path.join([dir, "lib/genie/lamps/aws/s3_delete_bucket.ex"]))

    handler = File.read!(Path.join([dir, "lib/genie/lamps/aws/s3_delete_bucket.ex"]))
    # Macro.camelize produces Aws/S3/DeleteBucket — developers can hand-fix to AWS
    assert handler =~ "S3DeleteBucket"
  end

  test "refuses to overwrite an existing file without --force" do
    dir = tmp_dir()
    capture_io(fn -> NewTask.run(["example.demo.hello", "--dir", dir]) end)

    assert_raise Mix.Error, ~r/refusing to overwrite/, fn ->
      capture_io(fn -> NewTask.run(["example.demo.hello", "--dir", dir]) end)
    end
  end

  test "rejects a lamp id without three dot-separated parts" do
    dir = tmp_dir()

    assert_raise Mix.Error, ~r/three dot-separated parts/, fn ->
      capture_io(fn -> NewTask.run(["only-two.parts", "--dir", dir]) end)
    end
  end
end
