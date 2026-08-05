# Disposable native capability probes. Invoke through `mix run --no-compile`
# so a native abort remains outside the caller's BEAM.
defmodule Tursox.CapabilityProbe do
  def run(["mvcc-manual-checkpoint", path]) do
    {:ok, database} = Tursox.Database.open(path, journal_mode: :mvcc)
    {:ok, connection} = Tursox.Database.connect(database)

    case Tursox.Connection.checkpoint(connection, :passive) do
      {:error, %Tursox.Error{code: :unsupported}} ->
        close(database, connection)
        IO.puts("unsupported:mvcc_manual_checkpoint")

      other ->
        IO.puts(:stderr, "unexpected:#{inspect(other)}")
        System.halt(2)
    end
  end

  def run(["experimental-sql", feature, path])
      when feature in ["materialized_views", "custom_types", "generated_columns"] do
    feature_atom = String.to_existing_atom(feature)
    {:ok, database} = Tursox.Database.open(path, features: [feature_atom])
    {:ok, connection} = Tursox.Database.connect(database)

    result =
      case feature do
        "materialized_views" ->
          Tursox.Connection.execute_batch(
            connection,
            "CREATE TABLE base(value INTEGER); " <>
              "CREATE MATERIALIZED VIEW materialized AS SELECT value FROM base"
          )

        "custom_types" ->
          Tursox.Connection.execute_batch(
            connection,
            "CREATE TYPE cents BASE integer ENCODE value * 100 DECODE value / 100"
          )

        "generated_columns" ->
          with :ok <-
                 Tursox.Connection.execute_batch(
                   connection,
                   "CREATE TABLE generated(a INTEGER, b INTEGER GENERATED ALWAYS AS (a + 1)); " <>
                     "INSERT INTO generated(a) VALUES (4)"
                 ),
               {:ok, cursor} <-
                 Tursox.Connection.query(connection, "SELECT a, b FROM generated"),
               {:ok, result} <- Tursox.Cursor.all(cursor, 10, 10) do
            {:ok, result.rows}
          end
      end

    close(database, connection)
    IO.puts("result:#{feature}:#{inspect(result)}")
  end

  def run(_args) do
    IO.puts(
      :stderr,
      "usage: capability_probe.exs mvcc-manual-checkpoint PATH | experimental-sql FEATURE PATH"
    )

    System.halt(64)
  end

  defp close(database, connection) do
    :ok = Tursox.Connection.close(connection)
    :ok = Tursox.Database.close(database)
  end
end

Tursox.CapabilityProbe.run(System.argv())
