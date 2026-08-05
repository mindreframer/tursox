defmodule Tursox.Native do
  @moduledoc false

  @version Mix.Project.config()[:version]
  @force_build Mix.env() == :test or
                 String.downcase(System.get_env("TURSOX_BUILD", "")) in ["1", "true", "yes", "on"] or
                 not File.exists?(Path.expand("../../checksum-Elixir.Tursox.Native.exs", __DIR__))

  use RustlerPrecompiled,
    otp_app: :tursox,
    crate: "tursox_nif",
    base_url: "https://github.com/mindreframer/tursox/releases/download/v#{@version}",
    version: @version,
    nif_versions: ["2.16"],
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      x86_64-pc-windows-msvc
    ),
    force_build: @force_build,
    path: "native/tursox_nif",
    cargo: {:system, "+1.91.0"},
    mode: if(Mix.env() == :prod, do: :release, else: :debug),
    features: ["nif_version_2_16"]

  def smoke, do: :erlang.nif_error(:nif_not_loaded)
  def smoke_error, do: :erlang.nif_error(:nif_not_loaded)
  def smoke_panic, do: :erlang.nif_error(:nif_not_loaded)
  def smoke_resource_open, do: :erlang.nif_error(:nif_not_loaded)
  def smoke_resource_close(_resource), do: :erlang.nif_error(:nif_not_loaded)

  def database_open(_path, _features), do: :erlang.nif_error(:nif_not_loaded)
  def database_close(_database), do: :erlang.nif_error(:nif_not_loaded)
  def database_connect(_database, _busy_timeout_ms), do: :erlang.nif_error(:nif_not_loaded)
  def connection_close(_connection), do: :erlang.nif_error(:nif_not_loaded)
  def connection_status(_connection), do: :erlang.nif_error(:nif_not_loaded)
  def connection_cache_flush(_connection), do: :erlang.nif_error(:nif_not_loaded)
  def connection_pragma_query(_connection, _name), do: :erlang.nif_error(:nif_not_loaded)

  def connection_pragma_update(_connection, _name, _value),
    do: :erlang.nif_error(:nif_not_loaded)

  def resource_snapshot, do: :erlang.nif_error(:nif_not_loaded)
end
