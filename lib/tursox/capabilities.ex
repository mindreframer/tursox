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
      status: :unsafe,
      builder: :experimental_materialized_views,
      option: :views,
      cargo: nil,
      note:
        "ordinary views are always on; the documented flag enables materialized views, whose CREATE reaches SIGBUS on 0.7.2/macOS"
    },
    materialized_views: %{
      status: :unsafe,
      builder: :experimental_materialized_views,
      option: :materialized_views,
      cargo: nil,
      note:
        "legacy alias for :views; CREATE MATERIALIZED VIEW reaches SIGBUS after open/connect on 0.7.2/macOS"
    },
    custom_types: %{
      status: :unsafe,
      builder: :experimental_custom_types,
      option: :custom_types,
      cargo: nil,
      note:
        "the flag is accepted, but a fresh custom-type database can SIGBUS during open and type-family probes are child-only"
    },
    encryption: %{
      status: :supported,
      builder: :experimental_encryption,
      option: :encryption,
      cargo: :pure_rust_crypto,
      note:
        "raw-key API wires with_encryption; all eight 0.7.2 cipher modes create, persist, reopen, reject wrong keys, and redact secrets"
    },
    index_method: %{
      status: :supported,
      builder: :experimental_index_method,
      option: :index_method,
      cargo: :fts,
      note: "parser/index switch and deliberate Cargo FTS support are enabled"
    },
    autovacuum: %{
      status: :partial,
      builder: :experimental_autovacuum,
      option: :autovacuum,
      cargo: nil,
      note:
        "Tursox patches the exact 0.7.2 wrapper omission; the disabled gate errors and enabled update executes, but the fresh-file header remains mode 0 due the pinned early-halt path"
    },
    vacuum: %{
      status: :unsafe,
      builder: :experimental_vacuum,
      option: :vacuum,
      cargo: nil,
      note:
        "the switch is exposed; initialized-file VACUUM currently reaches SIGBUS on 0.7.2/macOS and is child-only"
    },
    attach: %{
      status: :supported,
      builder: :experimental_attach,
      option: :attach,
      cargo: nil,
      note: "file behavior is covered by the advanced schema suite"
    },
    generated_columns: %{
      status: :unsafe,
      builder: :experimental_generated_columns,
      option: :generated_columns,
      cargo: nil,
      note:
        "full create/insert/read succeeds on macOS but has produced SIGSEGV on Linux; explicit unsafe opt-in and child evidence are retained"
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
      option: :mvcc_passive_checkpoint,
      cargo: nil,
      note:
        "runtime switch is exposed; PASSIVE checkpoint reaches SIGBUS after open/connect/write on 0.7.2/macOS"
    },
    runtime_extensions: %{
      status: :unsafe,
      builder: :set_load_extension_enabled,
      option: :runtime_extensions,
      cargo: nil,
      note:
        "explicit connection loader is exposed; libraries execute native code in the BEAM and must use Turso's extension ABI, not merely SQLite's ABI"
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

  @doc "Returns the release-level executable compatibility summary."
  @spec report() :: map()
  def report do
    %{
      report_version: 2,
      tursox: "0.2.1",
      engine: %{
        crate: "turso",
        version: "0.7.2",
        cargo_features: [:fts, :pure_rust_crypto]
      },
      statuses: @statuses,
      categories: %{
        core_sql: %{status: :supported, proof: ["test/core_sql_regression_test.exs"]},
        pragmas: %{status: :partial, proof: ["test/pragma_capability_test.exs"]},
        experimental: %{
          status: :partial,
          proof: ["test/experimental_capability_test.exs"]
        },
        types: %{status: :partial, proof: ["test/type_capability_test.exs"]},
        schema: %{
          status: :partial,
          proof:
            ~w(test/view_capability_test.exs test/table_feature_test.exs test/storage_schema_test.exs)
        },
        fts: %{status: :supported, proof: ["test/fts_test.exs"]},
        extensions: %{
          status: :partial,
          proof: ["test/extension_inventory_test.exs", "test/runtime_extension_test.exs"]
        },
        multiprocess_wal: %{
          status: :platform_limited,
          proof: ~w(test/multiprocess_access_test.exs test/multiprocess_recovery_test.exs)
        }
      },
      experimental_features: @experimental
    }
  end
end
