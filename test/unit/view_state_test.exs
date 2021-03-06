defmodule Brook.ViewStateTest do
  use ExUnit.Case
  import Assertions

  @instance :brook_test

  defmodule CustomHandler do
    use Brook.Event.Handler

    def handle_event(%Brook.Event{type: "create", data: data}) do
      create(:data, data["id"], data)
    end

    def handle_event(%Brook.Event{type: "merge", data: data}) do
      merge(:data, data["id"], data)
    end

    def handle_event(%Brook.Event{type: "delete", data: data}) do
      delete(:data, data["id"])
    end

    def handle_event(%Brook.Event{type: "cache_read", data: data}) do
      create(:data, data["id"], data)
      cached_value = Brook.get!(instance(), :data, data["id"])
      create(:cached_read, data["id"], cached_value)
    end

    def handle_event(%Brook.Event{type: "delete_cache_read", data: data}) do
      delete(:data, data["id"])
      cached_value = Brook.get!(instance(), :data, data["id"])
      create(:cached_read, data["id"], %{cached_value: cached_value})
    end

    def handle_event(%Brook.Event{type: "cache_read_all", data: data}) do
      create(:data, data["id"], data)
      entries = Brook.get_all!(instance(), :data)
      create(:cached_read, data["id"], entries)
    end

    def handle_event(%Brook.Event{type: "double_merge", data: data}) do
      merge(:data, data["id"], data)
      merge(:data, data["id"], %{second_merge: true})
    end

    def handle_event(%Brook.Event{type: "function_merge", data: data}) do
      merge(:data, data["id"], fn _old -> data end)
    end
  end

  setup do
    {:ok, brook} =
      Brook.start_link(
        instance: @instance,
        handlers: [CustomHandler]
      )

    on_exit(fn ->
      ref = Process.monitor(brook)
      Process.exit(brook, :normal)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)

    [brook: brook]
  end

  describe "create" do
    test "data is persisted to view state" do
      send_event("create", %{"id" => 1, "name" => "joe"})

      assert_async do
        assert %{"id" => 1, "name" => "joe"} == Brook.get!(@instance, :data, 1)
      end
    end

    test "data can be read from cache before commit to storage" do
      send_event("cache_read", %{"id" => 12, "name" => "George"})

      assert_async do
        assert %{"id" => 12, "name" => "George"} == Brook.get!(@instance, :data, 12)
        assert %{"id" => 12, "name" => "George"} == Brook.get!(@instance, :cached_read, 12)
      end
    end

    test "event is still persisted with data" do
      send_event("create", %{"id" => 3, "name" => "holler"})
      send_event("merge", %{"id" => 3, "age" => 21})

      assert_async do
        events = Brook.get_events!(@instance, :data, 3)
        assert 2 == length(events)
        assert Enum.at(events, 0).type == "create"
        assert Enum.at(events, 1).type == "merge"
      end
    end

    test "cannot be called outside of event handler" do
      assert_raise Brook.InvalidEvent, fn ->
        Brook.ViewState.create("people", "key1", "value1")
      end
    end
  end

  describe "merge" do
    test "data is merged into view state" do
      send_event("create", %{"id" => 1, "name" => "joe"})
      send_event("merge", %{"id" => 1, "age" => 21})

      assert_async do
        assert %{"id" => 1, "name" => "joe", "age" => 21} == Brook.get!(@instance, :data, 1)
      end
    end

    test "cannot be called outside of event handler" do
      assert_raise Brook.InvalidEvent, fn ->
        Brook.ViewState.merge("people", "key1", %{one: 1})
      end
    end

    test "data can be merged into more than once in scope of a single event" do
      send_event("double_merge", %{"id" => 18, "name" => "Bill"})

      assert_async do
        assert %{"id" => 18, "name" => "Bill", second_merge: true} == Brook.get!(@instance, :data, 18)
      end
    end

    test "data can be merged with a function and no current value" do
      send_event("function_merge", %{"id" => 23, "name" => "Nathaniel"})

      assert_async do
        assert %{"id" => 23, "name" => "Nathaniel"} == Brook.get!(@instance, :data, 23)
      end
    end
  end

  describe "delete" do
    test "data in view state is deleted" do
      send_event("create", %{"id" => 7, "name" => "joe"})

      assert_async do
        assert %{"id" => 7, "name" => "joe"} == Brook.get!(@instance, :data, 7)
      end

      send_event("delete", %{"id" => 7})

      assert_async do
        assert nil == Brook.get!(@instance, :data, 7)
      end
    end

    test "cached delete overrides a get where data is in persistence storage" do
      send_event("create", %{"id" => 5, "name" => "bob"})
      send_event("delete_cache_read", %{"id" => 5})

      assert_async do
        assert %{cached_value: nil} == Brook.get!(@instance, :cached_read, 5)
      end
    end

    test "cannot be called outside of event handler" do
      assert_raise Brook.InvalidEvent, fn ->
        Brook.ViewState.delete("people", "key1")
      end
    end
  end

  describe "get_all/1" do
    test "returns all cached and persisted entries" do
      send_event("create", %{"id" => 67, "name" => "fred"})
      send_event("cache_read_all", %{"id" => 68, "name" => "wilma"})

      assert_async do
        entries = Brook.get!(@instance, :cached_read, 68) || %{}
        assert 2 == Enum.count(entries)
        assert Map.get(entries, 67) == %{"id" => 67, "name" => "fred"}
        assert Map.get(entries, 68) == %{"id" => 68, "name" => "wilma"}
      end
    end
  end

  def send_event(type, data) do
    Brook.Event.send(@instance, type, "testing", data)
  end
end
