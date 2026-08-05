defmodule Tursox.Error do
  @moduledoc """
  Stable, redacted error returned by Tursox operations.

  SQL parameters and row values are never included in an error.
  """

  @codes [
    :busy,
    :busy_snapshot,
    :constraint,
    :readonly,
    :database_full,
    :interrupt,
    :io,
    :corrupt,
    :misuse,
    :conversion,
    :invalid_argument,
    :closed,
    :unsupported,
    :internal
  ]

  defexception [:message, :code, :operation, metadata: %{}]

  @type code ::
          :busy
          | :busy_snapshot
          | :constraint
          | :readonly
          | :database_full
          | :interrupt
          | :io
          | :corrupt
          | :misuse
          | :conversion
          | :invalid_argument
          | :closed
          | :unsupported
          | :internal

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          operation: atom() | nil,
          metadata: map()
        }

  @doc false
  def from_native(%{code: code, message: message, operation: operation}) when code in @codes do
    %__MODULE__{code: code, message: message, operation: operation}
  end

  def from_native(other) do
    %__MODULE__{
      code: :internal,
      message: "invalid error returned by native boundary",
      operation: :native,
      metadata: %{shape: inspect(other, limit: 3)}
    }
  end

  @doc "Returns whether an error can safely retry a complete transaction."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{code: code}), do: code in [:busy, :busy_snapshot]
end
