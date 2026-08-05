defmodule Tursox.TestSupport.MultiprocessWorker do
  @moduledoc false
  @timeout_ms 3_000

  def run(["init", path]) do
    with_connection(path, fn connection ->
      :ok =
        Tursox.Connection.execute(
          connection,
          "CREATE TABLE IF NOT EXISTS process_rows(id INTEGER PRIMARY KEY, value TEXT)"
        )
    end)
  end

  def run(["insert", path, id, value]) do
    with_connection(path, fn connection ->
      :ok =
        Tursox.Connection.execute(
          connection,
          "INSERT INTO process_rows VALUES (?, ?)",
          [String.to_integer(id), value]
        )
    end)
  end

  def run(["hold-open", path, ready, release]) do
    with_connection(path, fn _connection ->
      signal(ready, :open)
      await_file(release)
    end)
  end

  def run(["hold-write", path, id, ready, release, result]) do
    with_connection(path, fn connection ->
      :ok = Tursox.Connection.begin(connection, mode: :immediate)

      :ok =
        Tursox.Connection.execute(
          connection,
          "INSERT INTO process_rows VALUES (?, ?)",
          [String.to_integer(id), "held"]
        )

      signal(ready, :written)
      await_file(release)
      outcome = Tursox.Connection.commit(connection)
      signal(result, outcome)
    end)
  end

  def run(["contended-write", path, id, ready, result]) do
    with_connection(path, fn connection ->
      signal(ready, :attempting)
      outcome = Tursox.Connection.begin(connection, mode: :immediate)

      if outcome == :ok do
        :ok =
          Tursox.Connection.execute(
            connection,
            "INSERT INTO process_rows VALUES (?, 'contended')",
            [String.to_integer(id)]
          )

        :ok = Tursox.Connection.commit(connection)
      end

      signal(result, outcome)
    end)
  end

  def run(["hold-reader", path, ready, release, result]) do
    with_connection(path, fn connection ->
      :ok = Tursox.Connection.begin(connection)
      before = scalar(connection, "SELECT COUNT(*) FROM process_rows")
      signal(ready, before)
      await_file(release)
      snapshot = scalar(connection, "SELECT COUNT(*) FROM process_rows")
      :ok = Tursox.Connection.commit(connection)
      after_commit = scalar(connection, "SELECT COUNT(*) FROM process_rows")
      signal(result, {before, snapshot, after_commit})
    end)
  end

  def run(["hold-uncommitted", path, id, ready]) do
    with_connection(path, fn connection ->
      :ok = Tursox.Connection.begin(connection, mode: :immediate)

      :ok =
        Tursox.Connection.execute(
          connection,
          "INSERT INTO process_rows VALUES (?, 'uncommitted')",
          [String.to_integer(id)]
        )

      signal(ready, :uncommitted)

      receive do
        :never -> :ok
      after
        @timeout_ms -> raise "timed out while holding an uncommitted write"
      end
    end)
  end

  def run(["schema", path]) do
    with_connection(path, fn connection ->
      :ok = Tursox.Connection.execute(connection, "ALTER TABLE process_rows ADD COLUMN note TEXT")
    end)
  end

  def run(["checkpoint", path, result]) do
    with_connection(path, fn connection ->
      signal(result, Tursox.Connection.checkpoint(connection, :passive))
    end)
  end

  def run(args),
    do: raise(ArgumentError, "invalid multiprocess probe arguments: #{inspect(args)}")

  defp with_connection(path, fun) do
    {:ok, database} =
      Tursox.Database.open(path, features: [:multiprocess_wal], busy_timeout: 5_000)

    try do
      {:ok, connection} = Tursox.Database.connect(database, busy_timeout: 5_000)

      try do
        fun.(connection)
      after
        Tursox.Connection.close(connection)
      end
    after
      Tursox.Database.close(database)
    end
  end

  defp scalar(connection, sql) do
    {:ok, cursor} = Tursox.Connection.query(connection, sql)
    {:ok, result} = Tursox.Cursor.all(cursor, 1, 1)
    [[value]] = result.rows
    value
  end

  defp signal(path, term) do
    temporary = path <> ".#{System.pid()}.tmp"
    File.write!(temporary, :erlang.term_to_binary(term))
    File.rename!(temporary, path)
  end

  defp await_file(path) do
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    await_file(path, deadline)
  end

  defp await_file(path, deadline) do
    cond do
      File.exists?(path) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "timed out waiting for barrier #{path}"

      true ->
        Process.sleep(10)
        await_file(path, deadline)
    end
  end
end
