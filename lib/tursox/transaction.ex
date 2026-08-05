defmodule Tursox.Transaction do
  @moduledoc """
  Rollback-safe direct transaction operations and bounded whole-callback retry.

  MVCC is experimental upstream and provides snapshot isolation. Concurrent
  transactions use tested `BEGIN CONCURRENT` SQL because Turso 0.7.2 has no
  public Rust `TransactionBehavior::Concurrent` variant.
  """

  alias Tursox.{Connection, Cursor, Error, Telemetry}

  @modes [:deferred, :immediate, :exclusive, :concurrent]

  @doc "Begins a transaction in the selected mode."
  @spec begin(Connection.t(), keyword()) :: :ok | {:error, Error.t()}
  def begin(%Connection{} = connection, opts \\ []) do
    with {:ok, mode} <- mode(opts),
         :ok <- ensure_idle(connection),
         :ok <- ensure_mode_supported(connection, mode) do
      Connection.execute(connection, begin_sql(mode))
    end
  end

  @doc "Commits the active transaction."
  @spec commit(Connection.t()) :: :ok | {:error, Error.t()}
  def commit(%Connection{} = connection), do: Connection.execute(connection, "COMMIT")

  @doc "Rolls back the active transaction."
  @spec rollback(Connection.t()) :: :ok | {:error, Error.t()}
  def rollback(%Connection{} = connection), do: Connection.execute(connection, "ROLLBACK")

  @doc """
  Runs a callback and commits only its successful return value.

  `{:error, reason}`, exceptions, throws, and exits roll back. Raised/thrown/exited
  control flow is re-raised after rollback.
  """
  @spec transaction(Connection.t(), (-> term()), keyword()) ::
          {:ok, term()} | {:error, term() | Error.t()} | no_return()
  def transaction(%Connection{} = connection, fun, opts \\ []) when is_function(fun, 0) do
    Telemetry.span(:transaction, %{mode: mode_metadata(opts)}, fn ->
      do_transaction(connection, fun, opts)
    end)
  end

  defp do_transaction(connection, fun, opts) do
    case begin(connection, opts) do
      :ok -> run_callback(connection, fun)
      {:error, error} -> {:error, error}
    end
  end

  @doc "Retries a complete transaction callback only after retryable engine errors."
  @spec retry_transaction(Connection.t(), (-> term()), keyword()) ::
          {:ok, term()} | {:error, term() | Error.t()}
  def retry_transaction(%Connection{} = connection, fun, opts \\ []) when is_function(fun, 0) do
    Telemetry.span(:transaction_retry, %{mode: mode_metadata(opts)}, fn ->
      do_retry_transaction(connection, fun, opts)
    end)
  end

  defp do_retry_transaction(connection, fun, opts) do
    with {:ok, _mode} <- mode(opts),
         {:ok, attempts} <- positive_integer(opts, :attempts, 3),
         {:ok, backoff} <- backoff(opts),
         {:ok, jitter} <- jitter(opts) do
      retry(connection, fun, opts, attempts, 1, backoff, jitter)
    end
  end

  @doc "Runs a tested WAL/MVCC checkpoint pragma and returns its ordered rows."
  @spec checkpoint(Connection.t(), :passive | :full | :restart | :truncate) ::
          {:ok, [[term()]]} | {:error, Error.t()}
  def checkpoint(connection, mode \\ :passive)

  def checkpoint(
        %Connection{
          database: %{journal_mode: :mvcc, unsafe_features: unsafe_features}
        } = connection,
        :passive
      ) do
    if :mvcc_passive_checkpoint in unsafe_features do
      do_checkpoint(connection, :passive)
    else
      {:error,
       %Error{
         code: :unsupported,
         operation: :checkpoint,
         message: "PASSIVE MVCC checkpoint requires unsafe_features: [:mvcc_passive_checkpoint]"
       }}
    end
  end

  def checkpoint(%Connection{} = connection, mode)
      when mode in [:passive, :full, :restart, :truncate],
      do: do_checkpoint(connection, mode)

  def checkpoint(%Connection{}, _mode),
    do: invalid(:checkpoint, "checkpoint mode must be :passive, :full, :restart, or :truncate")

  defp do_checkpoint(connection, mode) do
    with {:ok, cursor} <-
           Connection.query(
             connection,
             "PRAGMA wal_checkpoint(#{mode |> Atom.to_string() |> String.upcase()})"
           ),
         {:ok, result} <- Cursor.all(cursor, 10, 10) do
      {:ok, result.rows}
    end
  end

  @doc "Sets and verifies the experimental MVCC checkpoint threshold."
  @spec set_mvcc_checkpoint_threshold(Connection.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def set_mvcc_checkpoint_threshold(%Connection{} = connection, threshold)
      when is_integer(threshold) and threshold >= 0 do
    with {:ok, _rows} <-
           Connection.pragma_update(connection, :mvcc_checkpoint_threshold, threshold),
         {:ok, [[effective | _] | _]} <-
           Connection.pragma_query(connection, :mvcc_checkpoint_threshold) do
      {:ok, effective}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        invalid(:mvcc_checkpoint_threshold, "checkpoint threshold returned an unexpected result")
    end
  end

  def set_mvcc_checkpoint_threshold(%Connection{}, _threshold),
    do: invalid(:mvcc_checkpoint_threshold, "threshold must be a non-negative integer")

  defp run_callback(connection, fun) do
    try do
      case fun.() do
        {:error, reason} ->
          rollback_best_effort(connection)
          {:error, reason}

        result ->
          case commit(connection) do
            :ok ->
              {:ok, result}

            {:error, error} ->
              rollback_best_effort(connection)
              {:error, error}
          end
      end
    rescue
      exception ->
        rollback_best_effort(connection)
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        rollback_best_effort(connection)
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp retry(connection, fun, opts, attempts, attempt, backoff, jitter) do
    case transaction(connection, fun, opts) do
      {:error, %Error{} = error} = result ->
        if Error.retryable?(error) and attempt < attempts do
          delay = backoff_value(backoff, attempt, error) |> jitter.() |> normalize_delay()
          if delay > 0, do: Process.sleep(delay)
          retry(connection, fun, opts, attempts, attempt + 1, backoff, jitter)
        else
          result
        end

      result ->
        result
    end
  end

  defp mode_metadata(opts) when is_list(opts), do: Keyword.get(opts, :mode, :deferred)
  defp mode_metadata(_opts), do: :invalid

  defp mode(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      if Keyword.keys(opts) -- [:mode, :attempts, :backoff, :jitter] == [] do
        case Keyword.get(opts, :mode, :deferred) do
          mode when mode in @modes ->
            {:ok, mode}

          _ ->
            invalid(
              :transaction_begin,
              "mode must be deferred, immediate, exclusive, or concurrent"
            )
        end
      else
        invalid(:transaction_begin, "unknown transaction option")
      end
    else
      invalid(:transaction_begin, "transaction options must be a keyword list")
    end
  end

  defp mode(_opts), do: invalid(:transaction_begin, "transaction options must be a keyword list")

  defp ensure_idle(connection) do
    case Connection.autocommit?(connection) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error,
         %Error{
           code: :misuse,
           operation: :transaction_begin,
           message: "nested transactions are not supported"
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ensure_mode_supported(%Connection{database: %{journal_mode: :mvcc}}, :concurrent), do: :ok

  defp ensure_mode_supported(_connection, :concurrent) do
    {:error,
     %Error{
       code: :unsupported,
       operation: :transaction_begin,
       message: "concurrent transactions require journal_mode: :mvcc"
     }}
  end

  defp ensure_mode_supported(_connection, _mode), do: :ok

  defp begin_sql(:deferred), do: "BEGIN DEFERRED"
  defp begin_sql(:immediate), do: "BEGIN IMMEDIATE"
  defp begin_sql(:exclusive), do: "BEGIN EXCLUSIVE"
  defp begin_sql(:concurrent), do: "BEGIN CONCURRENT"

  defp rollback_best_effort(connection) do
    case Connection.autocommit?(connection) do
      {:ok, false} -> rollback(connection)
      _ -> :ok
    end
  end

  defp positive_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> invalid(:transaction_retry, "#{key} must be a positive integer")
    end
  end

  defp backoff(opts) do
    case Keyword.get(opts, :backoff, 0) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      fun when is_function(fun, 2) ->
        {:ok, fun}

      _ ->
        invalid(
          :transaction_retry,
          "backoff must be non-negative milliseconds or an arity-2 function"
        )
    end
  end

  defp jitter(opts) do
    case Keyword.get(opts, :jitter, &Function.identity/1) do
      fun when is_function(fun, 1) -> {:ok, fun}
      _ -> invalid(:transaction_retry, "jitter must be an arity-1 function")
    end
  end

  defp backoff_value(value, _attempt, _error) when is_integer(value), do: value
  defp backoff_value(fun, attempt, error), do: fun.(attempt, error)
  defp normalize_delay(value) when is_integer(value) and value >= 0, do: value
  defp normalize_delay(_value), do: 0

  defp invalid(operation, message) do
    {:error, %Error{code: :invalid_argument, operation: operation, message: message}}
  end
end
