defmodule Tursox.TestSupport.Multiprocess do
  @moduledoc false
  @timeout 15_000

  def supported? do
    match?({:unix, _}, :os.type()) and :erlang.system_info(:wordsize) == 8
  end

  def run!(args) do
    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-compile", "bin/multiprocess_probe.exs" | args],
        cd: File.cwd!(),
        env: child_env(),
        stderr_to_stdout: true
      )

    if status != 0, do: raise("multiprocess child failed (#{status}): #{output}")
    output
  end

  def start(args) do
    executable = System.find_executable("mix") || raise "mix executable not found"

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:cd, String.to_charlist(File.cwd!())},
          {:env,
           Enum.map(child_env(), fn {key, value} ->
             {String.to_charlist(key), String.to_charlist(value)}
           end)},
          {:args,
           Enum.map(
             ["run", "--no-compile", "bin/multiprocess_probe.exs" | args],
             &String.to_charlist/1
           )}
        ]
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    %{port: port, os_pid: os_pid}
  end

  def await_term(path, timeout \\ @timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_term(path, deadline)
  end

  def signal(path, term \\ :release), do: File.write!(path, :erlang.term_to_binary(term))

  def await_exit(%{port: port}, timeout \\ @timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_exit(port, deadline, "")
  end

  def kill(%{port: port, os_pid: os_pid}) do
    if Port.info(port) do
      System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
      await_exit(%{port: port}, 5_000)
    else
      {:ok, 0, ""}
    end
  end

  def terminate(child) do
    if Port.info(child.port), do: kill(child), else: {:ok, 0, ""}
  end

  defp do_await_term(path, deadline) do
    cond do
      File.exists?(path) ->
        path |> File.read!() |> :erlang.binary_to_term([:safe])

      System.monotonic_time(:millisecond) >= deadline ->
        raise "timed out waiting for barrier #{path}"

      true ->
        receive do
          _message -> do_await_term(path, deadline)
        after
          10 -> do_await_term(path, deadline)
        end
    end
  end

  defp await_exit(port, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> await_exit(port, deadline, output <> data)
      {^port, {:exit_status, status}} -> {:ok, status, output}
    after
      remaining -> raise "timed out waiting for child exit; output: #{output}"
    end
  end

  defp child_env do
    [{"MIX_ENV", "test"}, {"TURSOX_BUILD", "1"}, {"ERL_FLAGS", "+sssdio 64"}]
  end
end
