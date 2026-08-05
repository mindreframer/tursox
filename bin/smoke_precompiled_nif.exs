nif_input = System.fetch_env!("NIF_PATH")

nif_file =
  case {:os.type(), System.find_executable("cygpath")} do
    {{:win32, _}, cygpath} when is_binary(cygpath) ->
      {native_path, 0} = System.cmd(cygpath, ["-w", nif_input])
      String.trim(native_path)

    _other ->
      Path.expand(nif_input)
  end
unless File.regular?(nif_file), do: raise("NIF library does not exist: #{nif_file}")

runtime_extension = if match?({:win32, _}, :os.type()), do: ".dll", else: ".so"
extension = Path.extname(nif_file)

load_file =
  if extension == runtime_extension do
    nif_file
  else
    copied = Path.join(System.tmp_dir!(), "tursox_raw_#{System.unique_integer([:positive])}#{runtime_extension}")
    File.cp!(nif_file, copied)
    copied
  end

load_path = String.trim_trailing(load_file, runtime_extension)

functions = [
  smoke: 0,
  smoke_error: 0,
  smoke_panic: 0,
  smoke_resource_open: 0,
  smoke_resource_close: 1,
  database_open: 2,
  database_close: 1,
  database_connect: 2,
  connection_close: 1,
  connection_status: 1,
  connection_cache_flush: 1,
  connection_pragma_query: 2,
  connection_pragma_update: 3,
  connection_execute: 5,
  connection_execute_batch: 2,
  connection_prepare: 2,
  connection_last_insert_rowid: 1,
  statement_close: 1,
  statement_execute: 4,
  statement_query: 4,
  statement_reset: 1,
  statement_columns: 1,
  cursor_fetch: 2,
  cursor_close: 1,
  resource_snapshot: 0
]

definitions =
  Enum.map(functions, fn {name, arity} ->
    args = if arity == 0, do: [], else: Enum.map(1..arity, &Macro.var(:"_arg#{&1}", __MODULE__))

    quote do
      def unquote(name)(unquote_splicing(args)), do: :erlang.nif_error(:nif_not_loaded)
    end
  end)

{:module, Tursox.Native, _binary, _term} =
  Module.create(
    Tursox.Native,
    quote do
      @on_load :__load_nif__
      def __load_nif__, do: :erlang.load_nif(unquote(String.to_charlist(load_path)), 0)
      unquote_splicing(definitions)
    end,
    Macro.Env.location(__ENV__)
  )

{:ok, 1} = Tursox.Native.smoke()
resource = Tursox.Native.smoke_resource_open()
%{smoke: 1} = Tursox.Native.resource_snapshot()
:ok = Tursox.Native.smoke_resource_close(resource)
%{smoke: 0} = Tursox.Native.resource_snapshot()

# Load the direct public API around this exact artifact without compiling the
# RustlerPrecompiled loader or invoking Cargo.
unless Code.ensure_loaded?(:telemetry) do
  defmodule :telemetry do
    def execute(_event, _measurements, _metadata), do: :ok

    def span(_event, metadata, fun) do
      {result, _stop_metadata} = fun.()
      result
    rescue
      exception -> reraise(exception, __STACKTRACE__)
    after
      _ = metadata
    end
  end
end

root = Path.expand("..", __DIR__)
Code.compiler_options(no_warn_undefined: [Tursox.Statement, Tursox.Transaction])

for file <- ~w(error column result parameters telemetry cursor statement connection transaction database) do
  Code.require_file(Path.join(root, "lib/tursox/#{file}.ex"))
end

Code.require_file(Path.join(root, "lib/tursox.ex"))
{:ok, 1} = Tursox.smoke()
{:ok, database} = Tursox.Database.open(:memory)
{:ok, connection} = Tursox.Database.connect(database)
:ok = Tursox.Connection.execute(connection, "CREATE TABLE smoke (value TEXT)")
:ok = Tursox.Connection.execute(connection, "INSERT INTO smoke VALUES (?)", ["precompiled"])
{:ok, cursor} = Tursox.Connection.query(connection, "SELECT value FROM smoke")
{:done, [["precompiled"]]} = Tursox.Cursor.fetch(cursor, 10)
:ok = Tursox.Connection.close(connection)
:ok = Tursox.Database.close(database)
IO.puts("Raw and public-API precompiled NIF smoke passed: #{nif_file}")
