defmodule Tursox.Telemetry do
  @moduledoc """
  Redacted telemetry helpers.

  Events use `[:tursox, operation, :start | :stop | :exception]`. Metadata never
  contains SQL, bound parameters, rows, keys, tokens, or database contents.
  """

  alias Tursox.{Error, Native}

  @doc false
  def span(operation, metadata \\ %{}, fun) when is_atom(operation) and is_function(fun, 0) do
    :telemetry.span([:tursox, operation], metadata, fn ->
      result = fun.()
      {result, %{result: result_class(result)}}
    end)
  end

  @doc "Returns and emits current logical native resource gauges."
  def resources do
    snapshot = Native.resource_snapshot()
    :telemetry.execute([:tursox, :resources], snapshot, %{})
    snapshot
  end

  defp result_class({:error, %Error{code: code}}), do: {:error, code}
  defp result_class({:error, _reason}), do: :error
  defp result_class(_result), do: :ok
end
