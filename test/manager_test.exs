defmodule Tursox.ManagerTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Error, Manager, Native, Pool, Result}

  test "multiple managers isolate overlapping tenant IDs" do
    first = start_manager(max_databases: 5)
    second = start_manager(max_databases: 5)
    {:ok, first_pool} = Manager.open(first, "same-id", :memory)
    {:ok, second_pool} = Manager.open(second, "same-id", :memory)

    {:ok, _} = Pool.execute(first_pool, "CREATE TABLE isolated (value INTEGER)")
    {:ok, _} = Pool.execute(first_pool, "INSERT INTO isolated VALUES (1)")
    {:ok, _} = Pool.execute(second_pool, "CREATE TABLE isolated (value INTEGER)")
    {:ok, _} = Pool.execute(second_pool, "INSERT INTO isolated VALUES (2)")

    assert {:ok, %Result{rows: [[1]]}} = Pool.query(first_pool, "SELECT value FROM isolated")
    assert {:ok, %Result{rows: [[2]]}} = Pool.query(second_pool, "SELECT value FROM isolated")
    assert Manager.lookup(first, "same-id") == first_pool
    assert Manager.lookup(second, "same-id") == second_pool
  end

  test "duplicate ID and canonical path opens are atomic and leak-free", %{tmp_dir: tmp_dir} do
    baseline = Native.resource_snapshot()
    manager = start_manager(max_databases: 10)

    results =
      1..20
      |> Task.async_stream(fn _ -> Manager.open(manager, {:tenant, 1}, :memory) end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.count(results, fn
             {:error, %Error{metadata: %{reason: :already_open}}} -> true
             _ -> false
           end) == 19

    path = Path.join(tmp_dir, "canonical.db")
    {:ok, _pool} = Manager.open(manager, :path_owner, path)

    assert {:error, %Error{metadata: %{reason: :path_conflict}}} =
             Manager.open(manager, :other, Path.join(tmp_dir, ".") <> "/canonical.db")

    snapshot = Native.resource_snapshot()
    assert snapshot.databases == baseline.databases + 2
    assert length(Manager.list(manager)) == 2
  end

  test "capacity races reject before native allocation" do
    baseline = Native.resource_snapshot()
    manager = start_manager(max_databases: 3)

    results =
      1..20
      |> Task.async_stream(fn id -> Manager.open(manager, id, :memory) end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 3

    assert Enum.count(results, fn
             {:error, %Error{metadata: %{reason: :capacity}}} -> true
             _ -> false
           end) == 17

    assert Native.resource_snapshot().databases == baseline.databases + 3
  end

  test "closing one tenant drains only that entry" do
    baseline = Native.resource_snapshot()
    manager = start_manager(max_databases: 5)
    {:ok, first} = Manager.open(manager, :first, :memory, pool_size: 2)
    {:ok, second} = Manager.open(manager, :second, :memory, pool_size: 2)
    assert {:ok, _} = Pool.execute(second, "CREATE TABLE remains (value INTEGER)")

    assert :ok = Manager.close(manager, :first)
    assert Manager.lookup(manager, :first) == nil
    assert Manager.lookup(manager, :second) == second
    assert {:ok, _} = Pool.execute(second, "INSERT INTO remains VALUES (1)")

    snapshot = Native.resource_snapshot()
    assert snapshot.databases == baseline.databases + 1
    assert snapshot.connections == baseline.connections + 2
    assert {:error, %Error{metadata: %{reason: :not_found}}} = Manager.close(manager, :missing)
    refute Process.alive?(first)
  end

  test "force close is bounded while a checkout is held" do
    manager = start_manager(max_databases: 2, close_timeout: 10)
    {:ok, pool} = Manager.open(manager, :busy, :memory, pool_size: 1)
    parent = self()

    {:ok, holder} =
      Task.start(fn ->
        Pool.transaction(pool, fn _checkout ->
          send(parent, :checkout_held)
          receive do: (:release -> :ok)
        end)
      end)

    monitor = Process.monitor(holder)
    assert_receive :checkout_held
    assert :ok = Manager.close(manager, :busy, timeout: 1, force: true)
    assert Manager.lookup(manager, :busy) == nil
    send(holder, :release)
    assert_receive {:DOWN, ^monitor, :process, ^holder, _reason}, 5_000
  end

  test "persistent entry crash restarts and preserves data", %{tmp_dir: tmp_dir} do
    baseline = Native.resource_snapshot()
    manager = start_manager(max_databases: 5)
    path = Path.join(tmp_dir, "persistent.db")
    {:ok, original} = Manager.open(manager, "persistent", path, pool_size: 2)
    {:ok, _} = Pool.execute(original, "CREATE TABLE durable_manager (value TEXT)")
    {:ok, _} = Pool.execute(original, "INSERT INTO durable_manager VALUES ('kept')")

    Process.exit(original, :kill)
    restarted = await_restarted(manager, "persistent", original, 100)
    assert is_pid(restarted)
    assert restarted != original

    assert {:ok, %Result{rows: [["kept"]]}} = query_until_ready(restarted, 100)
    assert Native.resource_snapshot().databases == baseline.databases + 1
  end

  test "memory entry crash is removed because its state cannot be recovered" do
    manager = start_manager(max_databases: 5)
    {:ok, pool} = Manager.open(manager, :ephemeral, :memory)
    Process.exit(pool, :kill)
    assert nil == await_removed(manager, :ephemeral, 100)

    {:ok, reopened} = Manager.open(manager, :ephemeral, :memory)
    assert reopened != pool
  end

  test "100 mixed-mode string IDs create no atoms and shutdown returns baseline" do
    baseline = Native.resource_snapshot()
    manager = start_manager(max_databases: 110)
    {:ok, warm} = Manager.open(manager, "warm", :memory)

    {:ok, warm_mvcc} =
      Manager.open(manager, "warm-mvcc", :memory, database_options: [journal_mode: :mvcc])

    _ = Manager.list(manager)
    :ok = Manager.close(manager, "warm")
    :ok = Manager.close(manager, "warm-mvcc")
    refute Process.alive?(warm)
    refute Process.alive?(warm_mvcc)
    atoms_before = :erlang.system_info(:atom_count)

    for index <- 1..100 do
      journal_mode = if rem(index, 2) == 0, do: :mvcc, else: :wal

      assert {:ok, _pool} =
               Manager.open(manager, "tenant-#{index}", :memory,
                 database_options: [journal_mode: journal_mode]
               )
    end

    assert length(Manager.list(manager)) == 100
    assert :erlang.system_info(:atom_count) == atoms_before

    metadata = hd(Manager.list(manager))

    assert Map.keys(metadata) |> Enum.sort() ==
             [:id, :journal_mode, :path, :persistent?, :pool, :pool_size]

    :ok = Manager.stop(manager)
    assert baseline == Native.resource_snapshot()
  end

  test "manager lifecycle telemetry contains safe metadata only" do
    manager = start_manager(max_databases: 2)
    handler = "manager-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [[:tursox, :manager, :open], [:tursox, :manager, :close]],
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, _pool} = Manager.open(manager, "safe-id", :memory)
    :ok = Manager.close(manager, "safe-id")

    assert_receive {:telemetry, [:tursox, :manager, :open], %{count: 1}, open_metadata}
    assert open_metadata == %{id: "safe-id", path: nil}
    assert_receive {:telemetry, [:tursox, :manager, :close], %{count: 1}, close_metadata}
    assert close_metadata == %{id: "safe-id", path: nil, forced: false}
  end

  defp start_manager(opts) do
    {:ok, manager} = Manager.start_link(opts)
    Process.unlink(manager)
    on_exit(fn -> if Process.alive?(manager), do: Manager.stop(manager) end)
    manager
  end

  defp await_restarted(manager, id, old, attempts) do
    case Manager.lookup(manager, id) do
      pool when is_pid(pool) and pool != old -> pool
      _ when attempts > 0 -> await_restarted(manager, id, old, attempts - 1)
      _ -> flunk("persistent entry did not restart")
    end
  end

  defp await_removed(manager, id, attempts) do
    case Manager.lookup(manager, id) do
      nil -> nil
      _ when attempts > 0 -> await_removed(manager, id, attempts - 1)
      _ -> flunk("memory entry was not removed")
    end
  end

  defp query_until_ready(pool, attempts) do
    case Pool.query(pool, "SELECT value FROM durable_manager") do
      {:ok, _result} = result -> result
      {:error, _error} when attempts > 0 -> query_until_ready(pool, attempts - 1)
      result -> result
    end
  end
end
