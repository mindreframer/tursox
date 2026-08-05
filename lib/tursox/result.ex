defmodule Tursox.Result do
  @moduledoc """
  Ordered result metadata for statement execution and explicit materialization.

  Rows are lists, never maps by default, so column order and duplicate names are
  preserved.
  """

  alias Tursox.{Column, Error}

  defstruct columns: nil, rows: nil, num_rows: 0, last_insert_rowid: nil

  @type t :: %__MODULE__{
          columns: [Column.t()] | nil,
          rows: [[term()]] | nil,
          num_rows: non_neg_integer(),
          last_insert_rowid: integer() | nil
        }

  @doc "Explicitly converts ordered rows to maps using a duplicate-name policy."
  @spec to_maps(t(), :first | :last | :error) :: {:ok, [map()]} | {:error, Error.t()}
  def to_maps(result, policy \\ :error)

  def to_maps(%__MODULE__{columns: columns, rows: rows}, policy)
      when is_list(columns) and is_list(rows) and policy in [:first, :last, :error] do
    names =
      Enum.map(columns, fn
        %Column{name: name} -> name
        name when is_binary(name) -> name
      end)

    with :ok <- duplicate_policy(names, policy) do
      {:ok, Enum.map(rows, &row_to_map(names, &1, policy))}
    end
  end

  def to_maps(_result, _policy) do
    {:error,
     %Error{
       code: :invalid_argument,
       operation: :result_to_maps,
       message: "result must contain columns and rows; policy must be :first, :last, or :error"
     }}
  end

  defp duplicate_policy(names, :error) do
    if length(names) == MapSet.size(MapSet.new(names)) do
      :ok
    else
      {:error,
       %Error{
         code: :conversion,
         operation: :result_to_maps,
         message: "duplicate column names require :first or :last collision policy"
       }}
    end
  end

  defp duplicate_policy(_names, _policy), do: :ok

  defp row_to_map(names, row, :first) do
    names
    |> Enum.zip(row)
    |> Enum.reverse()
    |> Map.new()
  end

  defp row_to_map(names, row, _policy), do: Map.new(Enum.zip(names, row))
end
