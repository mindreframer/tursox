defmodule Tursox.Query do
  @moduledoc "A DBConnection query backed by per-worker native prepared statements."

  @enforce_keys [:statement, :command, :ref]
  defstruct name: "", statement: nil, command: :query, ref: nil, persistent: true

  @type command :: :query | :execute
  @type t :: %__MODULE__{
          name: String.t(),
          statement: String.t(),
          command: command(),
          ref: reference(),
          persistent: boolean()
        }

  @doc false
  def new(statement, command, opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name, ""),
      statement: statement,
      command: command,
      ref: make_ref(),
      persistent: Keyword.get(opts, :persistent, true)
    }
  end
end

defimpl DBConnection.Query, for: Tursox.Query do
  def parse(query, _opts), do: query
  def describe(query, _opts), do: query
  def encode(_query, params, _opts), do: params
  def decode(_query, result, _opts), do: result
end

defimpl String.Chars, for: Tursox.Query do
  def to_string(%Tursox.Query{statement: statement}), do: statement
end

defimpl Inspect, for: Tursox.Query do
  import Inspect.Algebra

  def inspect(query, opts) do
    concat([
      "#Tursox.Query<name: ",
      to_doc(query.name, opts),
      ", command: ",
      to_doc(query.command, opts),
      ">"
    ])
  end
end
