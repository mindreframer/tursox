# Disposable native capability probes. Invoke through `mix run --no-compile`
# so a native abort remains outside the caller's BEAM.
defmodule Tursox.CapabilityProbe do
  def run(["mvcc-manual-checkpoint", path]) do
    phase("before_open")

    {:ok, database} =
      Tursox.Database.open(path,
        journal_mode: :mvcc,
        unsafe_features: [:mvcc_passive_checkpoint]
      )

    phase("opened")
    {:ok, connection} = Tursox.Database.connect(database)
    phase("connected")
    :ok = Tursox.Connection.execute(connection, "CREATE TABLE probe(value INTEGER)")
    phase("mvcc_before_passive_checkpoint")
    result = Tursox.Connection.checkpoint(connection, :passive)
    phase("mvcc_passive_checkpoint_returned")
    close(database, connection)
    phase("closed")
    IO.puts("result:mvcc_manual_checkpoint:#{inspect(result)}")
  end

  def run(["experimental-sql", feature, path])
      when feature in [
             "views",
             "materialized_views",
             "custom_types",
             "generated_columns",
             "vacuum"
           ] do
    feature_atom =
      %{
        "views" => :views,
        "materialized_views" => :materialized_views,
        "custom_types" => :custom_types,
        "generated_columns" => :generated_columns,
        "vacuum" => :vacuum
      }
      |> Map.fetch!(feature)

    phase("before_open")
    {:ok, database} = Tursox.Database.open(path, unsafe_features: [feature_atom])
    phase("opened")
    {:ok, connection} = Tursox.Database.connect(database)
    phase("connected")

    result =
      case feature do
        feature when feature in ["views", "materialized_views"] ->
          phase("materialized_views_before_create")

          result =
            Tursox.Connection.execute_batch(
              connection,
              "CREATE TABLE base(value INTEGER); " <>
                "CREATE MATERIALIZED VIEW materialized AS SELECT value FROM base"
            )

          phase("materialized_views_create_returned")
          result

        "custom_types" ->
          phase("custom_types_before_create")

          result =
            Tursox.Connection.execute_batch(
              connection,
              "CREATE TYPE cents BASE integer ENCODE value * 100 DECODE value / 100"
            )

          phase("custom_types_create_returned")
          result

        "generated_columns" ->
          phase("generated_columns_before_create_insert")

          with :ok <-
                 Tursox.Connection.execute_batch(
                   connection,
                   "CREATE TABLE generated(a INTEGER, b INTEGER GENERATED ALWAYS AS (a + 1)); " <>
                     "INSERT INTO generated(a) VALUES (4)"
                 ),
               :ok <- phase("generated_columns_inserted"),
               {:ok, cursor} <-
                 Tursox.Connection.query(connection, "SELECT a, b FROM generated"),
               :ok <- phase("generated_columns_queried"),
               {:ok, result} <- Tursox.Cursor.all(cursor, 10, 10),
               :ok <- phase("generated_columns_read") do
            {:ok, result.rows}
          end

        "vacuum" ->
          :ok = Tursox.Connection.execute(connection, "CREATE TABLE initialized(value INTEGER)")
          phase("vacuum_before_execute")
          result = Tursox.Connection.execute(connection, "VACUUM")
          phase("vacuum_execute_returned")
          result
      end

    close(database, connection)
    phase("closed")
    IO.puts("result:#{feature}:#{inspect(result)}")
  end

  def run(["type-sql", kind, path])
      when kind in ["custom_type", "builtin", "array", "struct", "union", "domain"] do
    phase("before_open")
    {:ok, database} = Tursox.Database.open(path, unsafe_features: [:custom_types])
    phase("opened")
    {:ok, connection} = Tursox.Database.connect(database)
    phase("connected")

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

    phase("type_#{kind}_before_execute")
    result = Tursox.Connection.execute_batch(connection, sql)
    phase("type_#{kind}_execute_returned")
    close(database, connection)
    phase("closed")
    IO.puts("result:type:#{kind}:#{inspect(result)}")
  end

  def run(_args) do
    IO.puts(
      :stderr,
      "usage: capability_probe.exs mvcc-manual-checkpoint PATH | experimental-sql FEATURE PATH | type-sql KIND PATH"
    )

    System.halt(64)
  end

  defp phase(name) do
    IO.puts(:stderr, "TURSOX_PROBE phase=#{name}")
    :ok
  end

  defp close(database, connection) do
    :ok = Tursox.Connection.close(connection)
    :ok = Tursox.Database.close(database)
  end
end

Tursox.CapabilityProbe.run(System.argv())
