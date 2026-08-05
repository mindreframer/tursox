defmodule Tursox.Database do
  @moduledoc """
  Opaque root resource for one local embedded Turso database.

  A database is opened once and can derive many independent
  `Tursox.Connection` resources. `:memory` databases are shared by connections
  derived from the same handle; separate opens remain isolated.

  Builder features are experimental upstream and opt-in through `:features`.
  """

  alias Tursox.{Connection, Error, Native, Telemetry}

  @features [
    :attach,
    :custom_types,
    :generated_columns,
    :index_method,
    :materialized_views,
    :vacuum,
    :multiprocess_wal,
    :without_rowid
  ]
  @allowed_options [:busy_timeout, :create_parent, :features, :journal_mode, :mode]

  @enforce_keys [:resource, :path, :journal_mode, :features]
  defstruct [:resource, :path, :journal_mode, :features]

  @opaque t :: %__MODULE__{
            resource: reference(),
            path: :memory | String.t(),
            journal_mode: atom(),
            features: [atom()]
          }

  @doc """
  Opens a local file or isolated in-memory database.

  Supported options are:

    * `:journal_mode` — `:wal` (default) or experimental `:mvcc`;
    * `:features` — an opt-in list from `builder_features/0`;
    * `:create_parent` — create a missing file parent directory (default false);
    * `:mode` — only `:read_write_create` is supported by Turso 0.7.2;
    * `:busy_timeout` — timeout used while applying/verifying open pragmas.
  """
  @spec open(:memory | String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def open(path, opts \\ []) do
    Telemetry.span(
      :database_open,
      %{kind: if(path in [:memory, ":memory:"], do: :memory, else: :file)},
      fn ->
        do_open(path, opts)
      end
    )
  end

  defp do_open(path, opts) do
    with {:ok, config} <- validate_open(path, opts),
         :ok <- ensure_parent(config),
         {:ok, resource} <-
           native(Native.database_open(config.native_path, config.native_features)),
         {:ok, journal_mode} <- configure_journal(resource, config) do
      {:ok,
       %__MODULE__{
         resource: resource,
         path: config.public_path,
         journal_mode: journal_mode,
         features: config.features
       }}
    else
      {:native_opened, resource, error} ->
        Native.database_close(resource)
        {:error, error}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @doc "Derives an independent connection from this database handle."
  @spec connect(t(), keyword()) :: {:ok, Connection.t()} | {:error, Error.t()}
  def connect(database, opts \\ [])

  def connect(%__MODULE__{} = database, opts) do
    Telemetry.span(:database_connect, %{journal_mode: database.journal_mode}, fn ->
      do_connect(database, opts)
    end)
  end

  def connect(_database, _opts), do: invalid(:database_connect, "expected a database resource")

  defp do_connect(database, opts) do
    with {:ok, timeout} <- validate_connect_options(opts),
         {:ok, resource} <- native(Native.database_connect(database.resource, timeout)) do
      {:ok, %Connection{resource: resource, database: database, busy_timeout: timeout}}
    end
  end

  @doc "Logically closes a database. It is safe to call repeatedly."
  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.database_close(resource)

  @doc "Returns safe metadata without exposing the native reference."
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = database) do
    Map.take(database, [:path, :journal_mode, :features])
  end

  @doc "Builder feature names confirmed on the pinned Turso crate."
  @spec builder_features() :: [atom()]
  def builder_features, do: @features

  defp validate_open(path, opts) when is_list(opts) do
    with :ok <- validate_keyword(opts),
         :ok <- reject_unknown_options(opts),
         {:ok, paths} <- normalize_path(path),
         {:ok, journal_mode} <- validate_journal(Keyword.get(opts, :journal_mode, :wal)),
         {:ok, features} <- validate_features(Keyword.get(opts, :features, [])),
         :ok <- validate_boolean(opts, :create_parent, false),
         :ok <- validate_mode(Keyword.get(opts, :mode, :read_write_create)),
         {:ok, busy_timeout} <- validate_timeout(Keyword.get(opts, :busy_timeout, 0)),
         :ok <- validate_compatibility(journal_mode, features, paths.public_path) do
      {:ok,
       Map.merge(paths, %{
         journal_mode: journal_mode,
         features: features,
         native_features: Enum.map(features, &Atom.to_string/1),
         create_parent: Keyword.get(opts, :create_parent, false),
         busy_timeout: busy_timeout
       })}
    end
  end

  defp validate_open(_path, _opts), do: invalid(:database_open, "options must be a keyword list")

  defp validate_keyword(opts) do
    if Keyword.keyword?(opts),
      do: :ok,
      else: invalid(:database_open, "options must be a keyword list")
  end

  defp reject_unknown_options(opts) do
    case Keyword.keys(opts) -- @allowed_options do
      [] -> :ok
      unknown -> invalid(:database_open, "unknown database options: #{inspect(unknown)}")
    end
  end

  defp normalize_path(path) when path in [:memory, ":memory:"] do
    {:ok, %{native_path: ":memory:", public_path: :memory, parent: nil}}
  end

  defp normalize_path(path) when is_binary(path) and byte_size(path) > 0 do
    if String.contains?(path, <<0>>) do
      invalid(:database_open, "database path cannot contain a NUL byte")
    else
      expanded = Path.expand(path)
      {:ok, %{native_path: expanded, public_path: expanded, parent: Path.dirname(expanded)}}
    end
  end

  defp normalize_path(_path),
    do: invalid(:database_open, "path must be :memory or a non-empty string")

  defp validate_journal(mode) when mode in [:wal, :mvcc], do: {:ok, mode}
  defp validate_journal(_mode), do: invalid(:database_open, "journal_mode must be :wal or :mvcc")

  defp validate_features(features) when is_list(features) do
    cond do
      Enum.any?(features, &(not is_atom(&1))) ->
        invalid(:database_open, "features must contain atoms")

      (unknown = Enum.uniq(features) -- @features) != [] ->
        invalid(:database_open, "unsupported builder features: #{inspect(unknown)}", :unsupported)

      true ->
        {:ok, Enum.uniq(features)}
    end
  end

  defp validate_features(_features), do: invalid(:database_open, "features must be a list")

  defp validate_boolean(opts, key, default) do
    if is_boolean(Keyword.get(opts, key, default)),
      do: :ok,
      else: invalid(:database_open, "#{inspect(key)} must be boolean")
  end

  defp validate_mode(:read_write_create), do: :ok

  defp validate_mode(mode) when mode in [:read_only, :read_write] do
    invalid(
      :database_open,
      "Turso 0.7.2 does not expose #{inspect(mode)} local open mode",
      :unsupported
    )
  end

  defp validate_mode(_mode), do: invalid(:database_open, "invalid database open mode")

  defp validate_timeout(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_timeout(_value),
    do: invalid(:database_connect, "busy_timeout must be a non-negative integer")

  defp validate_compatibility(_journal, features, :memory) do
    if :multiprocess_wal in features,
      do: invalid(:database_open, "multiprocess WAL requires a file database"),
      else: :ok
  end

  defp validate_compatibility(:mvcc, features, _path) do
    if :multiprocess_wal in features do
      invalid(:database_open, "MVCC and multiprocess WAL cannot be enabled together")
    else
      :ok
    end
  end

  defp validate_compatibility(_journal, _features, _path), do: :ok

  defp ensure_parent(%{parent: nil}), do: :ok

  defp ensure_parent(%{parent: parent, create_parent: true}) do
    case File.mkdir_p(parent) do
      :ok -> :ok
      {:error, reason} -> invalid(:database_open, "cannot create database parent: #{reason}")
    end
  end

  defp ensure_parent(%{parent: parent}) do
    if File.dir?(parent),
      do: :ok,
      else: invalid(:database_open, "database parent directory does not exist")
  end

  defp configure_journal(resource, config) do
    case native(Native.database_connect(resource, config.busy_timeout)) do
      {:ok, connection} ->
        result =
          with {:ok, _rows} <-
                 native(
                   Native.connection_pragma_update(
                     connection,
                     "journal_mode",
                     Atom.to_string(config.journal_mode)
                   )
                 ),
               {:ok, [[effective | _] | _]} <-
                 native(Native.connection_pragma_query(connection, "journal_mode")),
               {:ok, mode} <- effective_journal(effective, config.journal_mode) do
            {:ok, mode}
          else
            {:error, %Error{} = error} -> {:error, error}
            _ -> invalid(:database_open, "journal_mode returned an unexpected result")
          end

        Native.connection_close(connection)

        case result do
          {:ok, mode} -> {:ok, mode}
          {:error, error} -> {:native_opened, resource, error}
        end

      {:error, error} ->
        {:native_opened, resource, error}
    end
  end

  defp effective_journal(value, expected) when is_binary(value) do
    case String.downcase(value) do
      "wal" when expected == :wal -> {:ok, :wal}
      "mvcc" when expected == :mvcc -> {:ok, :mvcc}
      other -> invalid(:database_open, "journal_mode verification failed: #{other}")
    end
  end

  defp effective_journal(_value, _expected),
    do: invalid(:database_open, "journal_mode verification returned a non-text value")

  defp validate_connect_options(opts) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        invalid(:database_connect, "options must be a keyword list")

      Keyword.keys(opts) -- [:busy_timeout] != [] ->
        invalid(:database_connect, "unknown connection options")

      true ->
        validate_timeout(Keyword.get(opts, :busy_timeout, 0))
    end
  end

  defp validate_connect_options(_opts),
    do: invalid(:database_connect, "options must be a keyword list")

  defp native({:ok, value}), do: {:ok, value}
  defp native({:error, error}), do: {:error, Error.from_native(error)}

  defp invalid(operation, message, code \\ :invalid_argument) do
    {:error, %Error{code: code, operation: operation, message: message}}
  end
end

defimpl Inspect, for: Tursox.Database do
  import Inspect.Algebra

  def inspect(database, opts) do
    concat([
      "#Tursox.Database<path: ",
      to_doc(database.path, opts),
      ", journal_mode: ",
      to_doc(database.journal_mode, opts),
      ", features: ",
      to_doc(database.features, opts),
      ">"
    ])
  end
end
