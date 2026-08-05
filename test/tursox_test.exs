defmodule TursoxTest do
  use ExUnit.Case, async: false

  alias Tursox.{Error, Native}

  test "source-built NIF loads and uses the managed runtime" do
    assert {:ok, 1} = Tursox.smoke()
    assert {:ok, 1} = Tursox.smoke()
  end

  test "native errors cross the stable boundary" do
    assert {:error, native} = Native.smoke_error()
    error = Error.from_native(native)

    assert %Error{
             code: :internal,
             operation: :smoke,
             message: "deterministic native smoke error"
           } = error

    refute error.message =~ "secret"
  end

  test "panic is contained without crashing the VM" do
    assert {:error, native} = Native.smoke_panic()

    assert %Error{code: :internal, operation: :smoke_panic} = Error.from_native(native)
    assert {:ok, 1} = Tursox.smoke()
  end

  test "logical resource accounting is deterministic" do
    baseline = Native.resource_snapshot()
    resource = Native.smoke_resource_open()
    assert %{baseline | smoke: baseline.smoke + 1} == Native.resource_snapshot()
    assert :ok = Native.smoke_resource_close(resource)
    assert :ok = Native.smoke_resource_close(resource)
    assert baseline == Native.resource_snapshot()
  end
end
