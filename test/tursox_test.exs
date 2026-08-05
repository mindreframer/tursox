defmodule TursoxTest do
  use ExUnit.Case
  doctest Tursox

  test "greets the world" do
    assert Tursox.hello() == :world
  end
end
