defmodule Genie.Lamp.LampRegistryTest do
  use Genie.DataCase, async: true

  alias Genie.Lamp.{LampDefinition, LampRegistry, MetaDef}

  @s3_xml File.read!(Path.join(:code.priv_dir(:genie), "lamps/aws_s3_create_bucket.xml"))

  @minimal_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <lamp id="test.minimal.lamp" version="1.0" category="compute" vendor="test">
    <meta>
      <title>Minimal Lamp</title>
      <base-url>https://example.com</base-url>
      <auth-scheme>bearer</auth-scheme>
      <requires-approval>false</requires-approval>
      <destructive>false</destructive>
      <audit>false</audit>
    </meta>
    <endpoints>
      <endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="submit"/>
    </endpoints>
    <ui>
      <form aria-label="Test form">
        <field id="name" type="text" aria-label="Name" genie-fill="none"/>
      </form>
    </ui>
    <actions>
      <action id="submit" label="Submit" aria-label="Submit" style="primary" endpoint-id="run" behavior="submit"/>
    </actions>
  </lamp>
  """

  @invalid_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <lamp version="1.0">
    <meta><title>No ID</title></meta>
    <ui><form aria-label="F"></form></ui>
  </lamp>
  """

  describe "register/2 — valid XML" do
    test "succeeds and stores lamp_id" do
      assert {:ok, record} = LampRegistry.register(%{xml_source: @minimal_xml})
      assert record.lamp_id == "test.minimal.lamp"
      assert record.enabled == true
    end

    test "stores parsed_definition as a map" do
      assert {:ok, record} = LampRegistry.register(%{xml_source: @minimal_xml})
      assert is_map(record.parsed_definition)
      assert record.parsed_definition["id"] == "test.minimal.lamp"
    end

    test "extracts lamp_id from xml, not from caller" do
      assert {:ok, record} = LampRegistry.register(%{xml_source: @s3_xml})
      assert record.lamp_id == "aws.s3.create-bucket"
    end

    test "upserts on re-registration of same lamp_id" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @minimal_xml})
      assert {:ok, _} = LampRegistry.register(%{xml_source: @minimal_xml})

      assert {:ok, records} = Ash.read(LampRegistry, authorize?: false)
      count = Enum.count(records, &(&1.lamp_id == "test.minimal.lamp"))
      assert count == 1
    end

    test "org_id defaults to nil (available to all orgs)" do
      assert {:ok, record} = LampRegistry.register(%{xml_source: @minimal_xml})
      assert record.org_id == nil
    end
  end

  describe "register/2 — invalid XML" do
    test "returns error with reason for missing lamp id" do
      assert {:error, error} = LampRegistry.register(%{xml_source: @invalid_xml})
      assert %Ash.Error.Invalid{} = error
    end

    test "returns error for invalid XML syntax" do
      assert {:error, _error} = LampRegistry.register(%{xml_source: "not xml at all"})
    end

    test "cannot register lamp with invalid manifest" do
      xml_no_fields = """
      <?xml version="1.0" encoding="UTF-8"?>
      <lamp id="test.nope.nope" version="1.0" category="compute" vendor="test">
        <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme>
        <requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
        <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit"/></endpoints>
        <ui><form aria-label="F"></form></ui>
        <actions></actions>
      </lamp>
      """

      assert {:error, _} = LampRegistry.register(%{xml_source: xml_no_fields})
    end
  end

  describe "load_active_manifests/1" do
    test "returns only enabled lamps" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @minimal_xml, enabled: true})

      disabled_xml = String.replace(@minimal_xml, ~s(id="test.minimal.lamp"), ~s(id="test.disabled.lamp"))
      assert {:ok, _} = LampRegistry.register(%{xml_source: disabled_xml, enabled: false})

      assert {:ok, defns} = LampRegistry.load_active_manifests(nil)
      ids = Enum.map(defns, & &1.id)
      assert "test.minimal.lamp" in ids
      refute "test.disabled.lamp" in ids
    end

    test "returns LampDefinition structs with meta" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @s3_xml})

      assert {:ok, defns} = LampRegistry.load_active_manifests(nil)
      s3 = Enum.find(defns, &(&1.id == "aws.s3.create-bucket"))
      assert %LampDefinition{} = s3
      assert %MetaDef{} = s3.meta
      assert s3.meta.title == "AWS S3 Bucket Creator"
    end

    test "includes nil-org lamps regardless of org_id filter" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @minimal_xml})

      some_org_id = Ecto.UUID.generate()
      assert {:ok, defns} = LampRegistry.load_active_manifests(some_org_id)
      ids = Enum.map(defns, & &1.id)
      assert "test.minimal.lamp" in ids
    end
  end

  describe "fetch_lamp/1" do
    test "returns LampDefinition by lamp_id" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @s3_xml})

      assert {:ok, defn} = LampRegistry.fetch_lamp("aws.s3.create-bucket")
      assert %LampDefinition{} = defn
      assert defn.id == "aws.s3.create-bucket"
    end

    test "returns error for unknown lamp_id" do
      assert {:error, "lamp not found: does.not.exist"} = LampRegistry.fetch_lamp("does.not.exist")
    end

    test "round-trips all field types correctly" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @s3_xml})
      assert {:ok, defn} = LampRegistry.fetch_lamp("aws.s3.create-bucket")

      region = Enum.find(defn.fields, &(&1.id == "region"))
      assert region.genie_fill == :from_context
      assert region.type == :select

      versioning = Enum.find(defn.fields, &(&1.id == "versioning"))
      assert versioning.type == :toggle
      assert versioning.genie_fill == :infer

      org_id_field = Enum.find(defn.fields, &(&1.id == "org_id"))
      assert org_id_field.type == :hidden
    end

    test "round-trips endpoints with trigger atoms" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @s3_xml})
      assert {:ok, defn} = LampRegistry.fetch_lamp("aws.s3.create-bucket")

      ep = Enum.find(defn.endpoints, &(&1.id == "load_regions"))
      assert ep.trigger == :on_load
    end

    test "round-trips status templates" do
      assert {:ok, _} = LampRegistry.register(%{xml_source: @s3_xml})
      assert {:ok, defn} = LampRegistry.fetch_lamp("aws.s3.create-bucket")

      states = Enum.map(defn.status_templates, & &1.state)
      assert "ready" in states
      assert "submitting" in states
    end
  end
end
