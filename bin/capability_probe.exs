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
      when feature in ["materialized_views", "custom_types"] do
    feature_atom = String.to_existing_atom(feature)
    {:ok, database} = Tursox.Database.open(path, features: [feature_atom])
    {:ok, connection} = Tursox.Database.connect(database)

    sql =
      case feature do
        "materialized_views" ->
          "CREATE TABLE base(value INTEGER); " <>
            "CREATE MATERIALIZED VIEW materialized AS SELECT value FROM base"

        "custom_types" ->
          "CREATE TYPE cents BASE integer ENCODE value * 100 DECODE value / 100"
      end

    result = Tursox.Connection.execute_batch(connection, sql)
    close(database, connection)
    IO.puts("result:#{feature}:#{inspect(result)}")
  end

  def run(["type-sql", kind, path])
      when kind in ["custom_type", "builtin", "array", "struct", "union", "domain"] do
    {:ok, database} = Tursox.Database.open(path, features: [:custom_types])
    {:ok, connection} = Tursox.Database.connect(database)

    sql =
      case kind do
        "custom_type" ->
          "CREATE TYPE cents BASE integer ENCODE value * 100 DECODE value / 100; " <>
            "CREATE TABLE typed(value cents) STRICT; INSERT INTO typed VALUES (42)"

        "builtin" ->
          "CREATE TABLE typed(value date) STRICT; INSERT INTO typed VALUES ('2026-08-05')"

        "array" ->
          "CREATE TABLE typed(value INTEGER[]) STRICT; INSERT INTO typed VALUES (ARRAY[1, 2])"

        "struct" ->
          "CREATE TYPE point AS STRUCT(x INT, y INT); " <>
            "CREATE TABLE typed(value point) STRICT"

        "union" ->
          "CREATE TYPE choice AS UNION(one INT, two TEXT); " <>
            "CREATE TABLE typed(value choice) STRICT"

        "domain" ->
          "CREATE DOMAIN positive AS integer CHECK(value > 0); " <>
            "CREATE TABLE typed(value positive) STRICT; INSERT INTO typed VALUES (1)"
      end

    result = Tursox.Connection.execute_batch(connection, sql)
    close(database, connection)
    IO.puts("result:type:#{kind}:#{inspect(result)}")
  end

  def run(_args) do
    IO.puts(
      :stderr,
      "usage: capability_probe.exs mvcc-manual-checkpoint PATH | experimental-sql FEATURE PATH | type-sql KIND PATH"
    )

    System.halt(64)
  end

  defp close(database, connection) do
    :ok = Tursox.Connection.close(connection)
    :ok = Tursox.Database.close(database)
  end
end

Tursox.CapabilityProbe.run(System.argv())
