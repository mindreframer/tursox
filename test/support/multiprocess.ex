defmodule Tursox.TestSupport.Multiprocess do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @timeout 2_500
  @cluster_timeout 8_000
  @remote_timeout 5_000
  @worker Tursox.TestSupport.MultiprocessWorker
  @child_erl_flags "+S 2:2 +SDcpu 1:1 +SDio 1 +sssdio 64"

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: @name)
  end

  def stop do
    if Process.whereis(@name), do: GenServer.stop(@name, :normal, @timeout), else: :ok
  end

  def supported? do
    match?({:unix, _}, :os.type()) and :erlang.system_info(:wordsize) == 8
  end

  def nodes, do: GenServer.call(@name, :nodes, @cluster_timeout)

  def replace(dead_node), do: GenServer.call(@name, {:replace, dead_node}, @cluster_timeout)

  def run!(node, args) do
    :erpc.call(node, @worker, :run, [args], @timeout)
  catch
    kind, reason ->
      raise "multiprocess worker #{node} failed: #{Exception.format_banner(kind, reason)}"
  end

  def start(node, args) do
    receiver = self()
    reference = make_ref()
    os_pid = :erpc.call(node, System, :pid, [], @timeout)

    caller =
      spawn(fn ->
        result =
          try do
            {:ok, :erpc.call(node, @worker, :run, [args], @remote_timeout)}
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(receiver, {@name, reference, result})
      end)

    %{caller: caller, node: node, os_pid: os_pid, reference: reference}
  end

  def await_exit(%{reference: reference}, timeout \\ @timeout) do
    receive do
      {@name, ^reference, {:ok, result}} -> {:ok, result}
      {@name, ^reference, {:error, reason}} -> {:error, reason}
    after
      timeout -> raise "timed out waiting for multiprocess worker"
    end
  end

  def kill(child) do
    if Node.ping(child.node) == :pong do
      {_output, 0} =
        System.cmd("kill", ["-KILL", child.os_pid], stderr_to_stdout: true)
    end

    await_node_down(child.node, @timeout)
    await_caller_down(child.caller, @timeout)
    flush_result(child.reference)
    :ok
  end

  def terminate(child) do
    if Process.alive?(child.caller), do: kill(child), else: flush_result(child.reference)
    :ok
  end

  def signal(path, term \\ :release), do: File.write!(path, :erlang.term_to_binary(term))

  def await_term(path, timeout \\ @timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_term(path, deadline)
  end

  @impl true
  def init(nil), do: {:ok, %{cluster: nil}}

  @impl true
  def handle_call(:nodes, _from, state) do
    with {:ok, cluster, state} <- ensure_cluster(state),
         {:ok, nodes} <- ensure_two_nodes(cluster) do
      {:reply, nodes, state}
    else
      {:error, reason} -> {:stop, reason, {:error, reason}, state}
    end
  end

  def handle_call({:replace, dead_node}, _from, state) do
    with :pang <- Node.ping(dead_node),
         {:ok, cluster, state} <- ensure_cluster(state),
         {:ok, [member]} <- DevCluster.start(cluster, 1) do
      {:reply, member.node, state}
    else
      :pong -> {:reply, {:error, {:node_still_alive, dead_node}}, state}
      {:error, reason} -> {:stop, reason, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %{cluster: cluster}) when is_pid(cluster) do
    DevCluster.stop(cluster, timeout: 2_500, controller_timeout: 1_000)
  end

  def terminate(_reason, _state), do: :ok

  defp ensure_cluster(%{cluster: cluster} = state) when is_pid(cluster) do
    if Process.alive?(cluster), do: {:ok, cluster, state}, else: start_cluster(state)
  end

  defp ensure_cluster(state), do: start_cluster(state)

  defp start_cluster(state) do
    result =
      with_child_erl_flags(fn ->
        DevCluster.start_link(2,
          applications: [:tursox],
          hidden: true,
          shutdown_timeout: 1_000,
          cluster_shutdown_timeout: 2_000
        )
      end)

    case result do
      {:ok, cluster} -> {:ok, cluster, %{state | cluster: cluster}}
      {:error, reason} -> {:error, {:multiprocess_cluster_start_failed, reason}}
    end
  end

  defp ensure_two_nodes(cluster) do
    with {:ok, nodes} <- DevCluster.nodes(cluster) do
      live = Enum.filter(nodes, &(Node.ping(&1) == :pong))

      case 2 - length(live) do
        missing when missing > 0 ->
          with {:ok, members} <- DevCluster.start(cluster, missing) do
            {:ok, live ++ Enum.map(members, & &1.node)}
          end

        _ ->
          {:ok, Enum.take(live, 2)}
      end
    end
  end

  defp with_child_erl_flags(fun) do
    previous = System.get_env("ERL_FLAGS")
    flags = [previous, @child_erl_flags] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
    System.put_env("ERL_FLAGS", flags)

    try do
      fun.()
    after
      if previous, do: System.put_env("ERL_FLAGS", previous), else: System.delete_env("ERL_FLAGS")
    end
  end

  defp do_await_term(path, deadline) do
    cond do
      File.exists?(path) ->
        path |> File.read!() |> :erlang.binary_to_term([:safe])

      System.monotonic_time(:millisecond) >= deadline ->
        raise "timed out waiting for barrier #{path}"

      true ->
        Process.sleep(10)
        do_await_term(path, deadline)
    end
  end

  defp await_node_down(node, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_node_down(node, deadline)
  end

  defp do_await_node_down(node, deadline) do
    cond do
      Node.ping(node) == :pang ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "timed out waiting for node #{node} to stop"

      true ->
        Process.sleep(10)
        do_await_node_down(node, deadline)
    end
  end

  defp await_caller_down(caller, timeout) do
    monitor = Process.monitor(caller)

    receive do
      {:DOWN, ^monitor, :process, ^caller, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(monitor, [:flush])
        Process.exit(caller, :kill)
        raise "timed out reaping multiprocess RPC caller"
    end
  end

  defp flush_result(reference) do
    receive do
      {@name, ^reference, _result} -> :ok
    after
      0 -> :ok
    end
  end
end
