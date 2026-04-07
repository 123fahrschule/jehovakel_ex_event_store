defmodule Shared.EventStoreSchemaTest do
  use ExUnit.Case, async: false

  defmodule NamespacedEventStore do
    @moduledoc false
    use Shared.EventStore, otp_app: :jehovakel_ex_event_store
  end

  @event %Shared.EventTest.FakeEvent{}
  @metadata %{meta: "data"}
  @schema "event_store_find_event_test"

  setup do
    base_config = Application.fetch_env!(:jehovakel_ex_event_store, JehovakelEx.EventStore)
    runtime_config = Keyword.put(base_config, :schema, @schema)

    Application.put_env(:jehovakel_ex_event_store, NamespacedEventStore, runtime_config)

    config = EventStore.Config.parsed(NamespacedEventStore, :jehovakel_ex_event_store)

    case EventStore.Storage.Schema.drop(config) do
      :ok -> :ok
      {:error, :already_down} -> :ok
    end

    :ok = EventStore.Storage.Schema.create(config)

    {:ok, postgrex_connection} =
      config
      |> EventStore.Config.default_postgrex_opts()
      |> Postgrex.start_link()

    EventStore.Storage.Initializer.run!(postgrex_connection, config)

    {:ok, _} = Application.ensure_all_started(:eventstore)

    start_supervised!(NamespacedEventStore)
    start_supervised!(Support.Repo)

    on_exit(fn ->
      Process.exit(postgrex_connection, :shutdown)
      Application.delete_env(:jehovakel_ex_event_store, NamespacedEventStore)
    end)

    :ok
  end

  test "find event by event_id when the event store uses a custom schema" do
    assert {:ok, [%{data: @event}]} =
             NamespacedEventStore.append_event("stream_uuid", @event, @metadata)

    [%EventStore.RecordedEvent{event_id: event_id}] =
      NamespacedEventStore.all_events(nil, unwrap: false)

    assert {:ok, {@event, %{event_id: ^event_id}}} =
             NamespacedEventStore.find_event(event_id)
  end
end

defmodule Shared.EventStoreDefaultSchemaTest do
  use ExUnit.Case, async: false

  defmodule DefaultSchemaEventStore do
    @moduledoc false
    use Shared.EventStore, otp_app: :jehovakel_ex_event_store
  end

  @event %Shared.EventTest.FakeEvent{}
  @metadata %{meta: "data"}

  setup do
    base_config = Application.fetch_env!(:jehovakel_ex_event_store, JehovakelEx.EventStore)
    runtime_config = Keyword.delete(base_config, :schema)

    Application.put_env(:jehovakel_ex_event_store, DefaultSchemaEventStore, runtime_config)

    config = EventStore.Config.parsed(DefaultSchemaEventStore, :jehovakel_ex_event_store)

    {:ok, postgrex_connection} =
      config
      |> EventStore.Config.default_postgrex_opts()
      |> Postgrex.start_link()

    EventStore.Storage.Initializer.reset!(postgrex_connection, config)

    {:ok, _} = Application.ensure_all_started(:eventstore)

    start_supervised!(DefaultSchemaEventStore)
    start_supervised!(Support.Repo)

    on_exit(fn ->
      Process.exit(postgrex_connection, :shutdown)
      Application.delete_env(:jehovakel_ex_event_store, DefaultSchemaEventStore)
    end)

    {:ok, config: config}
  end

  test "find event by event_id when the event store falls back to the public schema",
       %{config: config} do
    assert Keyword.fetch!(config, :schema) == "public"

    assert {:ok, [%{data: @event}]} =
             DefaultSchemaEventStore.append_event("stream_uuid", @event, @metadata)

    [%EventStore.RecordedEvent{event_id: event_id}] =
      DefaultSchemaEventStore.all_events(nil, unwrap: false)

    assert {:ok, {@event, %{event_id: ^event_id}}} =
             DefaultSchemaEventStore.find_event(event_id)
  end
end
