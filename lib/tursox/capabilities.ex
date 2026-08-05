defmodule Tursox.Capabilities do
  @moduledoc """
  Machine-readable capability metadata for the pinned Turso 0.7.2 engine.

  Statuses describe behavior verified through Tursox, not features present only
  in newer web documentation. Experimental features remain explicit database
  open options and are not production-stability claims.
  """

  @statuses [:supported, :partial, :unsupported, :platform_limited, :unsafe]

  @experimental %{
    views: %{
      status: :supported,
      builder: nil,
      option: nil,
      cargo: nil,
      note: "ordinary views are always enabled on 0.7.2"
    },
    materialized_views: %{
      status: :unsafe,
      builder: :experimental_materialized_views,
      option: :materialized_views,
      cargo: nil,
      note: "disabled gate is stable; enabled 0.7.2 probe can terminate the process"
    },
    custom_types: %{
      status: :unsafe,
      builder: :experimental_custom_types,
      option: :custom_types,
      cargo: nil,
      note: "CREATE TYPE/domain enabled probes can terminate the process on the pin"
    },
    encryption: %{
      status: :unsupported,
      builder: :experimental_encryption,
      option: nil,
      cargo: :pure_rust_crypto,
      note: "no validated key/open contract; deliberately not exposed"
    },
    index_method: %{
      status: :supported,
      builder: :experimental_index_method,
      option: :index_method,
      cargo: :fts,
      note: "parser/index switch and deliberate Cargo FTS support are enabled"
    },
    autovacuum: %{
      status: :unsupported,
      builder: nil,
      option: nil,
      cargo: nil,
      note: "documented experimental builder switch is absent from 0.7.2"
    },
    vacuum: %{
      status: :partial,
      builder: :experimental_vacuum,
      option: :vacuum,
      cargo: nil,
      note: "requires an initialized file database"
    },
    attach: %{
      status: :supported,
      builder: :experimental_attach,
      option: :attach,
      cargo: nil,
      note: "file behavior is covered by the advanced schema suite"
    },
    generated_columns: %{
      status: :supported,
      builder: :experimental_generated_columns,
      option: :generated_columns,
      cargo: nil,
      note: "virtual generated columns"
    },
    without_rowid: %{
      status: :supported,
      builder: :experimental_without_rowid,
      option: :without_rowid,
      cargo: nil,
      note: "explicit opt-in"
    },
    multiprocess_wal: %{
      status: :platform_limited,
      builder: :experimental_multiprocess_wal,
      option: :multiprocess_wal,
      cargo: nil,
      note: "64-bit local-filesystem Unix probe only; detailed release result below"
    },
    mvcc_passive_checkpoint: %{
      status: :unsafe,
      builder: :experimental_mvcc_passive_checkpoint,
      option: nil,
      cargo: nil,
      note: "manual checkpoint probe can crash 0.7.2 and is rejected before allocation"
    },
    triggers: %{
      status: :supported,
      builder: nil,
      option: nil,
      cargo: nil,
      note: "always enabled compatibility no-op in the Rust builder"
    },
    strict: %{
      status: :supported,
      builder: nil,
      option: nil,
      cargo: nil,
      note: "always enabled compatibility no-op in the Rust builder"
    }
  }

  @doc "Returns all stable capability statuses accepted in reports."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Returns the documented experimental-feature matrix for Turso 0.7.2."
  @spec experimental_features() :: %{atom() => map()}
  def experimental_features, do: @experimental
end
