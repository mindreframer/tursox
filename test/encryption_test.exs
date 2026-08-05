defmodule Tursox.EncryptionTest do
  use Tursox.TestSupport.TmpCase, async: true

  alias Tursox.{Connection, Cursor, Database, Error}

  test "every compiled cipher encrypts, persists, and reopens", %{tmp_dir: root} do
    for {cipher, key_size} <- Database.encryption_ciphers() do
      path = Path.join(root, "#{cipher}.db")
      key = :crypto.strong_rand_bytes(key_size)
      secret = "plaintext-marker-#{cipher}-#{System.unique_integer([:positive])}"

      {database, connection} = open_encrypted(path, cipher, key)
      :ok = Connection.execute(connection, "CREATE TABLE secrets(value TEXT)")

      assert {:ok, :committed} =
               Connection.transaction(connection, fn ->
                 :ok = Connection.execute(connection, "INSERT INTO secrets VALUES (?)", [secret])
                 :committed
               end)

      close(database, connection)
      refute File.read!(path) =~ secret

      {reopened, reader} = open_encrypted(path, cipher, key)
      assert rows(reader, "SELECT value FROM secrets") == [[secret]]
      assert {:ok, [["ok"]]} = Connection.pragma_query(reader, :integrity_check)
      close(reopened, reader)
    end
  end

  test "wrong and missing credentials fail without leaking key material", %{tmp_dir: root} do
    path = Path.join(root, "wrong-key.db")
    key = :crypto.strong_rand_bytes(32)
    wrong_key = :crypto.strong_rand_bytes(32)

    {database, connection} = open_encrypted(path, :aes_256_gcm, key)
    :ok = Connection.execute(connection, "CREATE TABLE encrypted(value INTEGER)")
    close(database, connection)

    assert {:error, %Error{} = wrong_error} =
             Database.open(path,
               features: [:encryption],
               encryption: [cipher: :aes_256_gcm, key: wrong_key]
             )

    refute inspect(wrong_error) =~ Base.encode16(wrong_key)

    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(path, features: [:encryption])

    assert {:error, %Error{}} = Database.open(path)
  end

  test "encryption validates feature, path, cipher, and exact key size before allocation", %{
    tmp_dir: root
  } do
    path = Path.join(root, "validation.db")

    invalid = [
      [encryption: [cipher: :aes_256_gcm, key: <<0::256>>]],
      [features: [:encryption], encryption: [cipher: :unknown, key: <<0::256>>]],
      [features: [:encryption], encryption: [cipher: :aes_128_gcm, key: <<0::120>>]],
      [features: [:encryption], encryption: [cipher: :aes_128_gcm, key: "not-16-bytes"]]
    ]

    for opts <- invalid do
      assert {:error, %Error{code: :invalid_argument}} = Database.open(path, opts)
    end

    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(:memory,
               features: [:encryption],
               encryption: [cipher: :aes_128_gcm, key: <<0::128>>]
             )
  end

  test "database metadata and inspect expose state but never credentials", %{tmp_dir: root} do
    path = Path.join(root, "redaction.db")
    key = :crypto.strong_rand_bytes(16)
    {database, connection} = open_encrypted(path, :aes_128_gcm, key)

    assert Database.metadata(database) == %{
             path: path,
             journal_mode: :wal,
             features: [:encryption],
             unsafe_features: [],
             encrypted: true
           }

    rendered = inspect(database)
    assert rendered =~ "encrypted: true"
    refute rendered =~ Base.encode16(key)
    refute rendered =~ Base.encode16(key, case: :lower)
    close(database, connection)
  end

  defp open_encrypted(path, cipher, key) do
    {:ok, database} =
      Database.open(path,
        features: [:encryption],
        encryption: [cipher: cipher, key: key]
      )

    {:ok, connection} = Database.connect(database)
    {database, connection}
  end

  defp rows(connection, sql) do
    {:ok, cursor} = Connection.query(connection, sql)
    {:ok, result} = Cursor.all(cursor, 100, 32)
    result.rows
  end

  defp close(database, connection) do
    :ok = Connection.close(connection)
    :ok = Database.close(database)
  end
end
