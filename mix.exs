defmodule Tursox.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mindreframer/tursox"
  @authors ["Roman Heinrich <roman.heinrich@gmail.com>"]

  def project do
    [
      app: :tursox,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Flexible embedded Turso resources for Elixir",
      source_url: @source_url,
      homepage_url: @source_url,
      authors: @authors,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:db_connection, "== 2.10.2"},
      {:rustler, "== 0.38.0", runtime: false},
      {:rustler_precompiled, "== 0.8.4"},
      {:telemetry, "== 1.4.2"},
      {:ex_doc, "== 0.40.3", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "THIRD_PARTY_NOTICES.md",
        "docs/architecture.md",
        "docs/capabilities.md",
        "docs/compatibility/turso-0.7.2.md",
        "docs/databases-and-connections.md",
        "docs/queries-and-cursors.md",
        "docs/transactions-and-mvcc.md",
        "docs/pools.md",
        "docs/managers.md",
        "docs/operations.md"
      ],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: @authors,
      links: %{"Source" => @source_url},
      build_tools: ["mix", "cargo"],
      files:
        [
          "lib",
          "native/tursox_nif/src",
          "native/tursox_nif/Cargo.toml",
          "native/tursox_nif/Cargo.lock",
          ".cargo/config.toml",
          "rust-toolchain.toml",
          ".formatter.exs",
          "mix.exs",
          "README.md",
          "CHANGELOG.md",
          "LICENSE",
          "SECURITY.md",
          "THIRD_PARTY_NOTICES.md",
          "docs"
        ] ++ Path.wildcard("checksum-Elixir.Tursox.Native.exs")
    ]
  end
end
