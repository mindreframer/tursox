# Disposable native capability probe. Invoke through `mix run --no-compile` so
# crashes remain outside the caller's BEAM.
case System.argv() do
  ["mvcc-manual-checkpoint", path] ->
    {:ok, database} = Tursox.Database.open(path, journal_mode: :mvcc)
    {:ok, connection} = Tursox.Database.connect(database)

    case Tursox.Connection.checkpoint(connection, :passive) do
      {:error, %Tursox.Error{code: :unsupported}} ->
        :ok = Tursox.Connection.close(connection)
        :ok = Tursox.Database.close(database)
        IO.puts("unsupported:mvcc_manual_checkpoint")

      other ->
        IO.puts(:stderr, "unexpected:#{inspect(other)}")
        System.halt(2)
    end

  _ ->
    IO.puts(:stderr, "usage: capability_probe.exs mvcc-manual-checkpoint PATH")
    System.halt(64)
end
