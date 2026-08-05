alias Tursox.TestSupport.Multiprocess, as: Multiprocess

if Multiprocess.supported?() do
  epmd = System.find_executable("epmd") || raise "epmd executable not found"
  {_, 0} = System.cmd(epmd, ["-daemon"], stderr_to_stdout: true)
  :ok = DevCluster.start_distribution()
end

{:ok, _started} = Application.ensure_all_started(:tursox)
{:ok, multiprocess} = Multiprocess.start_link()
Process.unlink(multiprocess)

ExUnit.start(capture_log: true)

# Per-test resource baselines cannot be compared while independent databases run
# concurrently. Verify the process-wide counters once, after every case has exited.
ExUnit.after_suite(fn _result ->
  Multiprocess.stop()
  snapshot = Tursox.Native.resource_snapshot()

  unless Enum.all?(snapshot, fn {_resource, count} -> count == 0 end) do
    raise "native resources leaked after the test suite: #{inspect(snapshot)}"
  end
end)
