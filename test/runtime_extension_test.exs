defmodule Tursox.RuntimeExtensionTest do
  use ExUnit.Case, async: false

  alias Tursox.{Connection, Cursor, Database, Error}

  @fixture Path.expand("fixtures/runtime_extension/Cargo.toml", __DIR__)

  setup_all do
    {output, 0} =
      System.cmd(
        "cargo",
        ["+1.91.0", "build", "--release", "--locked", "--manifest-path", @fixture],
        stderr_to_stdout: true
      )

    assert output =~ "Finished" or output == ""
    :ok
  end

  test "a real Turso ABI extension loads only after explicit unsafe opt-in" do
    extension = fixture_library()

    {:ok, disabled_db} = Database.open(:memory)
    {:ok, disabled} = Database.connect(disabled_db)

    assert {:error, %Error{code: :unsupported}} =
             Connection.load_extension(disabled, extension)

    close(disabled_db, disabled)

    {:ok, database} = Database.open(:memory, unsafe_features: [:runtime_extensions])
    {:ok, connection} = Database.connect(database)
    assert :ok = Connection.load_extension(connection, extension)
    assert rows(connection, "SELECT tursox_fixture()") == [[4242]]
    close(database, connection)
  end

  test "enabled loader returns a bounded error for missing libraries" do
    {:ok, database} = Database.open(:memory, unsafe_features: [:runtime_extensions])
    {:ok, connection} = Database.connect(database)

    assert {:error, %Error{operation: :connection_load_extension, message: message}} =
             Connection.load_extension(connection, "/definitely/missing/tursox-extension")

    assert message =~ "Extension error"
    close(database, connection)
  end

  defp fixture_library do
    directory = Path.join(Path.dirname(@fixture), "target/release")

    case :os.type() do
      {:unix, :darwin} -> Path.join(directory, "libtursox_runtime_extension_fixture.dylib")
      {:unix, _} -> Path.join(directory, "libtursox_runtime_extension_fixture.so")
      {:win32, _} -> Path.join(directory, "tursox_runtime_extension_fixture.dll")
    end
  end

  defp rows(connection, sql) do
    {:ok, cursor} = Connection.query(connection, sql)
    {:ok, result} = Cursor.all(cursor, 10, 10)
    result.rows
  end

  defp close(database, connection) do
    :ok = Connection.close(connection)
    :ok = Database.close(database)
  end
end
