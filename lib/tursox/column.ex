defmodule Tursox.Column do
  @moduledoc "Ordered result-column metadata."

  @enforce_keys [:name]
  defstruct [:name, :declaration_type]

  @type t :: %__MODULE__{name: String.t(), declaration_type: String.t() | nil}
end
