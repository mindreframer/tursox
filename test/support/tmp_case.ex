defmodule Tursox.TestSupport.TmpCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Tursox.TestSupport.TmpCase
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "tursox-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, tmp_dir: root}
  end

  def tmp_path(root, name \\ "database.db"), do: Path.join(root, name)
end
