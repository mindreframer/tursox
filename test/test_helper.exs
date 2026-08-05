ExUnit.start(capture_log: true)

# Per-test resource baselines cannot be compared while independent databases run
# concurrently. Verify the process-wide counters once, after every case has exited.
ExUnit.after_suite(fn _result ->
  snapshot = Tursox.Native.resource_snapshot()

  unless Enum.all?(snapshot, fn {_resource, count} -> count == 0 end) do
    raise "native resources leaked after the test suite: #{inspect(snapshot)}"
  end
end)
