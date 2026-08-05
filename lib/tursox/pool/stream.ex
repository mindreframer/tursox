defmodule Tursox.Pool.Stream do
  @moduledoc false
  @enforce_keys [:pool, :query, :params, :opts]
  defstruct [:pool, :query, :params, :opts]
end

defimpl Enumerable, for: Tursox.Pool.Stream do
  def reduce(stream, acc, fun) do
    source = Tursox.Pool.pool(stream.pool)

    DBConnection.run(
      source,
      fn connection ->
        connection
        |> DBConnection.prepare_stream(stream.query, stream.params, stream.opts)
        |> Enumerable.reduce(acc, fun)
      end,
      stream.opts
    )
  end

  def count(_stream), do: {:error, __MODULE__}
  def member?(_stream, _value), do: {:error, __MODULE__}
  def slice(_stream), do: {:error, __MODULE__}
end
