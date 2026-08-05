defmodule Tursox.HardeningTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Result, Statement}

  test "telemetry includes durations/classes but no SQL, params, or rows" do
    parent = self()
    handler = "hardening-#{System.unique_integer([:positive])}"

    events = [
      [:tursox, :database_open, :stop],
      [:tursox, :database_connect, :stop],
      [:tursox, :query, :stop],
      [:tursox, :cursor_fetch, :stop],
      [:tursox, :transaction, :stop],
      [:tursox, :resources]
    ]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, _config ->
          send(parent, {:event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    secret = "never-emit-this-value"
    sql = "SELECT ? AS private_value"
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    {:ok, cursor} = Connection.query(connection, sql, [secret])
    assert {:rows, [[^secret]]} = Cursor.fetch(cursor, 1)
    assert :done = Cursor.fetch(cursor, 1)
    assert {:ok, :done} = Connection.transaction(connection, fn -> :done end)
    _snapshot = Tursox.resources()

    captured = collect_events(MapSet.new(events), [])
    rendered = inspect(captured, limit: :infinity)
    refute rendered =~ secret
    refute rendered =~ sql

    assert Enum.all?(captured, fn
             {event, measurements, metadata} when event == [:tursox, :resources] ->
               is_integer(measurements.databases) and metadata == %{}

             {_event, %{duration: duration}, %{result: _result}} ->
               is_integer(duration) and duration >= 0
           end)

    Connection.close(connection)
    Database.close(database)
  end

  test "large blobs and oversized results remain fetch bounded" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE large_rows (id INTEGER, payload BLOB)")
    {:ok, statement} = Connection.prepare(connection, "INSERT INTO large_rows VALUES (?, ?)")
    payload = :binary.copy(<<0, 255>>, 32 * 1024)

    for id <- 1..40 do
      assert {:ok, %Result{num_rows: 1}} = Statement.execute(statement, [id, {:blob, payload}])
    end

    Statement.close(statement)
    {:ok, cursor} = Connection.query(connection, "SELECT id, payload FROM large_rows ORDER BY id")

    chunks = fetch_sizes(cursor, 3, [])
    assert Enum.all?(chunks, &(&1 <= 3))
    assert Enum.sum(chunks) == 40

    Connection.close(connection)
    Database.close(database)
  end

  test "dirty bounded fetch leaves normal BEAM work responsive" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE responsiveness (value BLOB)")
    {:ok, insert} = Connection.prepare(connection, "INSERT INTO responsiveness VALUES (?)")
    blob = {:blob, :binary.copy(<<7>>, 16 * 1024)}
    for _ <- 1..100, do: {:ok, _} = Statement.execute(insert, [blob])
    Statement.close(insert)
    {:ok, cursor} = Connection.query(connection, "SELECT value FROM responsiveness")
    parent = self()

    fetcher = Task.async(fn -> Cursor.fetch(cursor, 100) end)
    spawn(fn -> send(parent, :normal_scheduler_heartbeat) end)
    assert_receive :normal_scheduler_heartbeat, 1_000
    assert {:rows, rows} = Task.await(fetcher, 15_000)
    assert length(rows) == 100
    assert :done = Cursor.fetch(cursor, 1)

    Connection.close(connection)
    Database.close(database)
  end

  test "corrupt files and invalid options fail without leaking", %{tmp_dir: tmp_dir} do
    baseline = Tursox.resources()
    path = Path.join(tmp_dir, "corrupt.db")
    File.write!(path, :crypto.strong_rand_bytes(4_096))

    assert {:error, %Error{code: code}} = Database.open(path)
    assert code in [:corrupt, :misuse, :io]
    assert baseline == Tursox.resources()
  end

  test "opaque inspection excludes native references and row values" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    {:ok, statement} = Connection.prepare(connection, "SELECT ?")
    {:ok, cursor} = Statement.query(statement, ["private-row-value"])

    rendered = inspect([database, connection, statement, cursor])
    refute rendered =~ "private-row-value"
    refute rendered =~ "#Reference"

    Cursor.close(cursor)
    Statement.close(statement)
    Connection.close(connection)
    Database.close(database)
  end

  defp collect_events(expected, acc) do
    if MapSet.size(expected) == 0 do
      Enum.reverse(acc)
    else
      receive do
        {:event, event, measurements, metadata} ->
          collect_events(MapSet.delete(expected, event), [{event, measurements, metadata} | acc])
      after
        2_000 -> flunk("missing telemetry events: #{inspect(MapSet.to_list(expected))}")
      end
    end
  end

  defp fetch_sizes(cursor, size, acc) do
    case Cursor.fetch(cursor, size) do
      {:rows, rows} -> fetch_sizes(cursor, size, [length(rows) | acc])
      {:done, rows} -> Enum.reverse([length(rows) | acc])
      :done -> Enum.reverse(acc)
    end
  end
end
