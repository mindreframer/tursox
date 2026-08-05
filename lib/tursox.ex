defmodule Tursox do
  @moduledoc """
  Low-level and optional managed Elixir bindings for the embedded Turso engine.

  Tursox preserves Turso's database → connection → statement → cursor resource
  hierarchy. The direct API does not require a pool or manager.
  """

  alias Tursox.{Error, Native, Telemetry}

  @doc "Returns deterministic logical native resource gauges."
  def resources, do: Telemetry.resources()

  @doc "Checks that the source-built or precompiled native library is loaded."
  @spec smoke() :: {:ok, pos_integer()} | {:error, Error.t()}
  def smoke do
    case Native.smoke() do
      {:ok, value} -> {:ok, value}
      {:error, error} -> {:error, Error.from_native(error)}
    end
  end
end
