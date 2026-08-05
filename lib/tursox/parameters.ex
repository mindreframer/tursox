defmodule Tursox.Parameters do
  @moduledoc false

  alias Tursox.Error

  @i64_min -9_223_372_036_854_775_808
  @i64_max 9_223_372_036_854_775_807

  @type normalized :: {boolean(), [String.t()], [term()]}

  @spec normalize(term(), atom()) :: {:ok, normalized()} | {:error, Error.t()}
  def normalize(params, operation \\ :parameters)

  def normalize(params, operation) when is_map(params) do
    params
    |> Map.to_list()
    |> normalize_named(operation)
  end

  def normalize(params, operation) when is_list(params) do
    if named_list?(params) do
      normalize_named(params, operation)
    else
      with {:ok, values} <- normalize_values(params, operation) do
        {:ok, {false, [], values}}
      end
    end
  end

  def normalize(_params, operation),
    do: invalid(operation, "parameters must be a positional list, named map, or named pair list")

  defp named_list?([]), do: false
  defp named_list?(params), do: Enum.all?(params, &named_pair?/1)

  defp named_pair?({:blob, value}) when is_binary(value), do: false
  defp named_pair?({name, _value}) when is_atom(name) or is_binary(name), do: true
  defp named_pair?(_value), do: false

  defp normalize_named(pairs, operation) do
    with {:ok, names_values} <- normalize_pairs(pairs, operation),
         :ok <- reject_duplicate_names(names_values, operation),
         {:ok, values} <- normalize_values(Enum.map(names_values, &elem(&1, 1)), operation) do
      {:ok, {true, Enum.map(names_values, &elem(&1, 0)), values}}
    end
  end

  defp normalize_pairs(pairs, operation) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn
      {name, value}, {:ok, acc} ->
        case normalize_name(name, operation) do
          {:ok, name} -> {:cont, {:ok, [{name, value} | acc]}}
          {:error, error} -> {:halt, {:error, error}}
        end

      _other, _acc ->
        {:halt, invalid(operation, "named parameters must be {name, value} pairs")}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_name(name, operation) when is_atom(name),
    do: normalize_name(Atom.to_string(name), operation)

  defp normalize_name(name, operation) when is_binary(name) do
    normalized =
      if String.starts_with?(name, [":", "@", "$", "?"]),
        do: name,
        else: ":" <> name

    if Regex.match?(~r/^(?:[:@$][A-Za-z_][A-Za-z0-9_]*|\?[1-9][0-9]*)$/, normalized) do
      {:ok, normalized}
    else
      invalid(operation, "invalid named parameter name")
    end
  end

  defp normalize_name(_name, operation),
    do: invalid(operation, "parameter names must be atoms or strings")

  defp reject_duplicate_names(pairs, operation) do
    names = Enum.map(pairs, &elem(&1, 0))

    if length(names) == MapSet.size(MapSet.new(names)),
      do: :ok,
      else: invalid(operation, "named parameter names must be unique")
  end

  defp normalize_values(values, operation) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, acc} ->
      case normalize_value(value, index, operation) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_value(nil, _index, _operation), do: {:ok, nil}
  defp normalize_value(value, _index, _operation) when is_boolean(value), do: {:ok, value}

  defp normalize_value(value, _index, _operation)
       when is_integer(value) and value >= @i64_min and value <= @i64_max,
       do: {:ok, value}

  defp normalize_value(value, _index, _operation) when is_float(value), do: {:ok, value}

  defp normalize_value({:blob, value}, _index, _operation) when is_binary(value),
    do: {:ok, {:blob, value}}

  defp normalize_value(value, index, operation) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else:
        invalid(
          operation,
          "binary parameter at index #{index} is not UTF-8; tag it as {:blob, binary}"
        )
  end

  defp normalize_value(value, index, operation) when is_integer(value),
    do: invalid(operation, "integer parameter at index #{index} is outside signed 64-bit range")

  defp normalize_value(_value, index, operation),
    do: invalid(operation, "unsupported parameter at index #{index}")

  defp invalid(operation, message) do
    {:error, %Error{code: :invalid_argument, operation: operation, message: message}}
  end
end
