defmodule Tursox.CapabilityReportTest do
  use ExUnit.Case, async: true

  alias Tursox.Capabilities

  test "generated compatibility snapshot matches executable metadata and named proofs" do
    {snapshot, _binding} =
      Code.eval_file("docs/compatibility/turso-0.7.2-roadmap002.exs")

    assert snapshot == Capabilities.report()
    assert snapshot.engine == %{crate: "turso", version: "0.7.2", cargo_features: [:fts]}
    assert snapshot.tursox == "0.2.0"

    for {_category, %{proof: proofs}} <- snapshot.categories,
        proof <- proofs do
      assert File.regular?(proof), "missing capability proof #{proof}"
    end
  end

  test "human report includes every executable category" do
    report = File.read!("docs/roadmap002-capabilities.md")

    for heading <- [
          "Core SQL",
          "PRAGMAs",
          "Experimental feature switches",
          "STRICT tables, custom types, and domains",
          "Views and advanced schema",
          "Full-text search",
          "Built-in and loadable extensions",
          "Multiprocess WAL"
        ] do
      assert report =~ "## #{heading}"
    end
  end
end
