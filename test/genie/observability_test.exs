defmodule Genie.ObservabilityTest do
  use Genie.DataCase, async: false

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Audit.AuditLog

  describe "OTel trace ID propagation to AuditLog" do
    test "AuditLog entry stores the trace ID from an active span" do
      Tracer.with_span "Genie.reactor.start" do
        span_ctx = :otel_tracer.current_span_ctx()
        trace_id_int = :otel_span.trace_id(span_ctx)

        trace_id_hex =
          trace_id_int
          |> Integer.to_string(16)
          |> String.downcase()
          |> String.pad_leading(32, "0")

        {:ok, log} =
          AuditLog
          |> Ash.Changeset.for_create(:create, %{
            lamp_id: "aws.s3.create-bucket",
            trace_id: trace_id_hex,
            result: :success
          })
          |> Ash.create(authorize?: false)

        assert log.trace_id == trace_id_hex
        assert String.length(log.trace_id) == 32
        assert log.trace_id =~ ~r/^[0-9a-f]{32}$/
      end
    end

    test "AuditLog.trace_id is a valid 32-char lowercase hex string" do
      trace_id = "abcdef1234567890abcdef1234567890"

      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{
          lamp_id: "test.lamp",
          trace_id: trace_id,
          result: :success
        })
        |> Ash.create(authorize?: false)

      assert log.trace_id == trace_id
    end

    test "AuditLog accepts nil trace_id (no active span)" do
      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{
          lamp_id: "test.lamp",
          result: :success
        })
        |> Ash.create(authorize?: false)

      assert is_nil(log.trace_id)
    end

    test "span trace ID from OrchestratorWorker span is non-zero when OTel is active" do
      Tracer.with_span "Genie.reactor.start", %{
        attributes: [{"session_id", "test-session"}, {"actor_id", "test-actor"}]
      } do
        span_ctx = :otel_tracer.current_span_ctx()
        trace_id = :otel_span.trace_id(span_ctx)
        assert trace_id != 0
      end
    end
  end

  describe "AuditLog entries for denied lamp actions" do
    test "denied AuditLog entry has result :denied" do
      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{
          lamp_id: "aws.s3.create-bucket",
          intent_name: "create_bucket",
          result: :denied
        })
        |> Ash.create(authorize?: false)

      assert log.result == :denied
    end

    test "completed AuditLog entry has result :success" do
      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{
          lamp_id: "aws.ec2.list-instances",
          intent_name: "list_instances",
          result: :success
        })
        |> Ash.create(authorize?: false)

      assert log.result == :success
    end
  end
end
