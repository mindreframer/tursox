defmodule Tursox.PoolTest do
  use ExUnit.Case, async: false

  alias Tursox.{Database, Error, Native, Pool, Query, Result}

  test "pool_size connections derive from exactly one in-memory database" do
    baseline = Native.resource_snapshot()
    {:ok, pool} = start_pool(database: :memory, pool_size: 3, connection_listeners: [self()])
    workers = await_workers(3, MapSet.new())

    snapshot = Native.resource_snapshot()
    assert snapshot.databases == baseline.databases + 1
    assert snapshot.connections == baseline.connections + 3
    assert MapSet.size(workers) == 3

    assert {:ok, %Result{}} = Pool.execute(pool, "CREATE TABLE shared_pool (value INTEGER)")
    assert {:ok, %Result{}} = Pool.execute(pool, "INSERT INTO shared_pool VALUES (?)", [7])
    assert {:ok, %Result{rows: [[7]]}} = Pool.query(pool, "SELECT value FROM shared_pool")

    assert :ok = Pool.stop(pool)
    assert baseline == Native.resource_snapshot()
  end

  test "caller-owned database survives pool shutdown" do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory)

    {:ok, pool} =
      start_pool(database: database, pool_size: 2, connection_listeners: [self()])

    _workers = await_workers(2, MapSet.new())
    assert Pool.metadata(pool).owned? == false

    assert {:ok, _} = Pool.execute(pool, "CREATE TABLE caller_owned (value INTEGER)")
    :ok = Pool.stop(pool)
    assert Native.resource_snapshot().databases == baseline.databases + 1

    {:ok, connection} = Database.connect(database)
    assert :ok = Tursox.Connection.execute(connection, "INSERT INTO caller_owned VALUES (1)")
    Tursox.Connection.close(connection)
    Database.close(database)
    assert baseline == Native.resource_snapshot()
  end

  test "prepare, execute, close, ping/status, and bounded query results work" do
    {:ok, pool} = start_pool(database: :memory, pool_size: 1, connection_listeners: [self()])
    _workers = await_workers(1, MapSet.new())
    assert {:ok, _} = Pool.execute(pool, "CREATE TABLE prepared_pool (value INTEGER)")

    assert {:ok, %Query{} = query} =
             Pool.prepare(pool, "INSERT INTO prepared_pool VALUES (?)", :execute)

    assert {:ok, ^query, %Result{num_rows: 1}} = Pool.execute_prepared(pool, query, [1])
    assert {:ok, _query, %Result{num_rows: 1}} = Pool.execute_prepared(pool, query, [2])
    assert {:ok, %Result{}} = Pool.close(pool, query)

    assert {:ok, %Result{rows: [[1], [2]], num_rows: 2}} =
             Pool.query(pool, "SELECT value FROM prepared_pool ORDER BY value", [], max_rows: 2)

    assert {:error, %Error{operation: :cursor_all}} =
             Pool.query(pool, "SELECT value FROM prepared_pool", [], max_rows: 1)

    assert DBConnection.status(Pool.pool(pool)) == :idle
    :ok = Pool.stop(pool)
  end

  test "prepared stream chunks and early halt release native cursor" do
    baseline = Native.resource_snapshot()
    {:ok, pool} = start_pool(database: :memory, pool_size: 1, connection_listeners: [self()])
    _workers = await_workers(1, MapSet.new())
    {:ok, _} = Pool.execute(pool, "CREATE TABLE stream_rows (value INTEGER)")

    for value <- 1..30 do
      {:ok, _} = Pool.execute(pool, "INSERT INTO stream_rows VALUES (?)", [value])
    end

    chunks =
      pool
      |> Pool.stream("SELECT value FROM stream_rows ORDER BY value", [], chunk_size: 7)
      |> Enum.to_list()

    assert Enum.map(chunks, & &1.num_rows) == [7, 7, 7, 7, 2]
    assert Enum.flat_map(chunks, & &1.rows) |> List.last() == [30]

    [_first] =
      pool
      |> Pool.stream("SELECT value FROM stream_rows ORDER BY value", [], chunk_size: 5)
      |> Enum.take(1)

    snapshot = Native.resource_snapshot()
    assert snapshot.cursors == baseline.cursors
    :ok = Pool.stop(pool)
    assert baseline == Native.resource_snapshot()
  end

  test "DBConnection transactions forward modes and roll back safely" do
    {:ok, pool} =
      start_pool(
        database: :memory,
        database_options: [journal_mode: :mvcc],
        pool_size: 2,
        connection_listeners: [self()]
      )

    _workers = await_workers(2, MapSet.new())
    {:ok, _} = Pool.execute(pool, "CREATE TABLE tx_pool (value INTEGER)")

    for mode <- [:deferred, :immediate, :exclusive, :concurrent] do
      assert {:ok, :inserted} =
               Pool.transaction(
                 pool,
                 fn connection ->
                   assert {:ok, _} =
                            Pool.execute(connection, "INSERT INTO tx_pool VALUES (?)", [1])

                   :inserted
                 end,
                 mode: mode
               )
    end

    assert {:error, :stop} =
             Pool.transaction(pool, fn connection ->
               {:ok, _} = Pool.execute(connection, "INSERT INTO tx_pool VALUES (99)")
               DBConnection.rollback(connection, :stop)
             end)

    assert {:ok, %Result{rows: [[4]]}} = Pool.query(pool, "SELECT COUNT(*) FROM tx_pool")
    :ok = Pool.stop(pool)
  end

  test "MVCC pool transactions hold concurrent checkouts and commit disjoint writes" do
    {:ok, pool} =
      start_pool(
        database: :memory,
        database_options: [journal_mode: :mvcc],
        pool_size: 2,
        connection_listeners: [self()]
      )

    _workers = await_workers(2, MapSet.new())

    {:ok, _} =
      Pool.execute(pool, "CREATE TABLE pool_writers (id INTEGER PRIMARY KEY, value INTEGER)")

    {:ok, _} = Pool.execute(pool, "INSERT INTO pool_writers VALUES (1, 0)")
    {:ok, _} = Pool.execute(pool, "INSERT INTO pool_writers VALUES (2, 0)")
    parent = self()

    tasks =
      for id <- [1, 2] do
        Task.async(fn ->
          Pool.transaction(
            pool,
            fn checkout ->
              send(parent, {:pool_writer_ready, id})
              receive do: (:write -> :ok)

              {:ok, _} =
                Pool.execute(checkout, "UPDATE pool_writers SET value = 1 WHERE id = ?", [id])

              send(parent, {:pool_writer_written, id})
              receive do: (:commit -> :ok)
              id
            end,
            mode: :concurrent
          )
        end)
      end

    assert_receive {:pool_writer_ready, 1}
    assert_receive {:pool_writer_ready, 2}
    Enum.each(tasks, &send(&1.pid, :write))
    assert_receive {:pool_writer_written, 1}
    assert_receive {:pool_writer_written, 2}
    Enum.each(tasks, &send(&1.pid, :commit))
    assert Enum.map(tasks, &Task.await(&1)) |> Enum.sort() == [{:ok, 1}, {:ok, 2}]

    assert {:ok, %Result{rows: [[1, 1], [2, 1]]}} =
             Pool.query(pool, "SELECT id, value FROM pool_writers ORDER BY id")

    :ok = Pool.stop(pool)
  end

  test "checkout isolation prevents transaction interleaving on one worker" do
    {:ok, pool} = start_pool(database: :memory, pool_size: 1, connection_listeners: [self()])
    _workers = await_workers(1, MapSet.new())
    {:ok, _} = Pool.execute(pool, "CREATE TABLE isolated_checkout (value INTEGER)")
    parent = self()

    holder =
      Task.async(fn ->
        Pool.transaction(pool, fn checkout ->
          {:ok, _} = Pool.execute(checkout, "INSERT INTO isolated_checkout VALUES (1)")
          send(parent, :holder_ready)
          receive do: (:release -> :ok)
          :held
        end)
      end)

    assert_receive :holder_ready

    waiter =
      Task.async(fn ->
        send(parent, :waiter_started)
        result = Pool.execute(pool, "INSERT INTO isolated_checkout VALUES (2)")
        send(parent, {:waiter_done, result})
      end)

    assert_receive :waiter_started
    refute_receive {:waiter_done, _}, 0
    send(holder.pid, :release)
    assert {:ok, :held} = Task.await(holder)
    assert_receive {:waiter_done, {:ok, %Result{}}}
    Task.await(waiter)

    assert {:ok, %Result{rows: [[2]]}} =
             Pool.query(pool, "SELECT COUNT(*) FROM isolated_checkout")

    :ok = Pool.stop(pool)
  end

  test "a killed worker is replaced without reopening the database" do
    baseline = Native.resource_snapshot()
    {:ok, pool} = start_pool(database: :memory, pool_size: 2, connection_listeners: [self()])
    workers = await_workers(2, MapSet.new())
    victim = Enum.at(workers, 0)
    Process.exit(victim, :kill)

    replacement = await_replacement(workers)
    refute replacement in workers
    _metadata = Pool.metadata(pool)

    snapshot = Native.resource_snapshot()
    assert snapshot.databases == baseline.databases + 1
    assert snapshot.connections == baseline.connections + 2
    assert {:ok, _} = query_until_ready(pool, 10)
    :ok = Pool.stop(pool)
    assert baseline == Native.resource_snapshot()
  end

  defp start_pool(opts) do
    case Pool.start_link(opts) do
      {:ok, pool} = result ->
        on_exit(fn -> if Process.alive?(pool), do: Pool.stop(pool) end)
        result

      error ->
        error
    end
  end

  defp query_until_ready(pool, attempts) do
    case Pool.query(pool, "PRAGMA user_version") do
      {:error, %Error{code: :closed}} when attempts > 1 -> query_until_ready(pool, attempts - 1)
      result -> result
    end
  end

  defp await_workers(0, workers), do: workers

  defp await_workers(left, workers) do
    receive do
      {:connected, worker} -> await_workers(left - 1, MapSet.put(workers, worker))
    after
      5_000 -> flunk("pool workers did not connect")
    end
  end

  defp await_replacement(old_workers) do
    receive do
      {:connected, worker} ->
        if worker in old_workers, do: await_replacement(old_workers), else: worker

      {:disconnected, _worker} ->
        await_replacement(old_workers)
    after
      5_000 -> flunk("pool worker was not replaced")
    end
  end
end
