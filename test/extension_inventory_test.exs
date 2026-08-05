defmodule Tursox.ExtensionInventoryTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)

    on_exit(fn ->
      Connection.close(connection)
      Database.close(database)
      assert baseline == Native.resource_snapshot()
    end)

    {:ok, connection: connection}
  end

  test "runtime inventory identifies available and absent extension families", %{
    connection: connection
  } do
    {:ok, functions} = Connection.pragma_query(connection, :function_list)
    names = functions |> Enum.map(&hd/1) |> MapSet.new()

    for name <- ~w(uuid4 uuid4_str uuid7 uuid_str uuid_blob regexp vector32
                   vector_distance_l2 vector_extract time_now time_fmt_date
                   median percentile percentile_cont percentile_disc load_extension) do
      assert MapSet.member?(names, name), "expected built-in #{name}"
    end

    for name <- ~w(regexp_substr regexp_capture regexp_replace crypto_sha256
                   crypto_encode fuzzy_leven fuzzy_soundex ipfamily ipnetwork ipcontains) do
      refute MapSet.member?(names, name), "unexpected newer extension #{name}"
    end

    assert {:ok, modules} = Connection.pragma_query(connection, :module_list)
    module_names = modules |> Enum.map(&hd/1) |> MapSet.new()
    assert MapSet.member?(module_names, "generate_series")
    refute MapSet.member?(module_names, "csv")
  end

  test "UUID, regexp, vector, time, percentile, and series smoke exact value shapes", %{
    connection: connection
  } do
    assert [[16, 36, "550e8400-e29b-41d4-a716-446655440000"]] =
             rows(connection, """
             SELECT length(uuid4()), length(uuid4_str()),
                    uuid_str(uuid_blob('550e8400-e29b-41d4-a716-446655440000'))
             """)

    assert rows(connection, "SELECT regexp('[0-9]+', 'abc123'), 'hello123' REGEXP '[a-z]+[0-9]+'") ==
             [[1, 1]]

    assert [["[1,2]", 2.0]] =
             rows(connection, """
             SELECT vector_extract(vector32('[1,2]')),
                    vector_distance_l2(vector32('[1,2]'), vector32('[1,4]'))
             """)

    assert [["blob", "2026-08-05", 1_000_000_000]] =
             rows(connection, """
             SELECT typeof(time_now()), time_fmt_date(time_date(2026,8,5)), dur_s()
             """)

    assert [[30.0, 40.0, 20.0, 20.0]] =
             rows(connection, """
             SELECT median(column1), percentile(column1,75),
                    percentile_cont(column1,0.25), percentile_disc(column1,0.25)
             FROM (VALUES(10),(20),(30),(40),(50))
             """)

    assert rows(connection, "SELECT value FROM generate_series(1,5)") ==
             [[1], [2], [3], [4], [5]]
  end

  test "available families have pinned malformed-input behavior", %{connection: connection} do
    # These 0.7.2 functions use NULL rather than an error for malformed input.
    assert rows(connection, "SELECT uuid_blob('not-a-uuid'), regexp('(', 'text')") ==
             [[nil, nil]]

    assert rows(connection, "SELECT percentile(column1, 101) FROM (VALUES(1))") == [[nil]]

    # A zero series step is treated as the default positive step on this pin.
    assert rows(connection, "SELECT value FROM generate_series(1, 3, 0)") == [[1], [2], [3]]

    for sql <- [
          "SELECT vector_distance_l2(vector32('[1]'), vector32('[1,2]'))",
          "SELECT time_parse('not-a-time')"
        ] do
      assert {:error, %Error{}} = all_rows(connection, sql)
    end
  end

  test "newer and runtime-loadable extensions are unavailable safely", %{connection: connection} do
    for sql <- [
          "SELECT regexp_substr('abc123', '[0-9]+')",
          "SELECT crypto_sha256('hello')",
          "SELECT fuzzy_leven('a', 'b')",
          "SELECT ipfamily('127.0.0.1')",
          "CREATE VIRTUAL TABLE temp.data USING csv(filename='missing.csv', header=yes)"
        ] do
      assert {:error, %Error{code: :misuse}} = all_rows(connection, sql)
    end

    assert {:error, %Error{code: :misuse}} =
             all_rows(connection, "SELECT load_extension('uuid')")

    assert {:error, %Error{code: :misuse}} =
             all_rows(connection, "SELECT load_extension('/tmp/arbitrary.so')")
  end

  defp rows(connection, sql) do
    {:ok, values} = all_rows(connection, sql)
    values
  end

  defp all_rows(connection, sql) do
    with {:ok, cursor} <- Connection.query(connection, sql),
         {:ok, result} <- Cursor.all(cursor, 10_000, 64) do
      {:ok, result.rows}
    end
  end
end
