defmodule Tursox.TestSupport.CapabilityProbe do
  @moduledoc false

  defstruct [:command, :kind, :last_phase, :output, :signal, :status]

  @timeout 15_000
  @signals %{6 => :sigabrt, 7 => :sigbus, 10 => :sigbus, 11 => :sigsegv}

  def run(args, timeout \\ @timeout) do
    task =
      Task.async(fn ->
        System.cmd(
          "mix",
          ["run", "--no-compile", "bin/capability_probe.exs" | args],
          cd: File.cwd!(),
          env: [
            {"MIX_ENV", "test"},
            {"TURSOX_BUILD", "1"},
            {"ERL_FLAGS", "+S 2:2 +SDcpu 1:1 +SDio 1 +sssdio 64"}
          ],
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout) do
      {:ok, {output, status}} ->
        classify(args, output, status)

      nil ->
        Task.shutdown(task, :brutal_kill)
        %__MODULE__{command: args, kind: :timeout, status: nil, output: "", last_phase: nil}
    end
  end

  defp classify(args, output, 0) do
    %__MODULE__{
      command: args,
      kind: :success,
      status: 0,
      output: output,
      last_phase: last_phase(output)
    }
  end

  defp classify(args, output, status) do
    signal_number = if status >= 128, do: status - 128
    signal = Map.get(@signals, signal_number)

    %__MODULE__{
      command: args,
      kind: if(signal, do: :signal, else: :exit),
      signal: signal,
      status: status,
      output: output,
      last_phase: last_phase(output)
    }
  end

  defp last_phase(output) do
    ~r/^TURSOX_PROBE phase=([^\s]+)$/m
    |> Regex.scan(output, capture: :all_but_first)
    |> List.last()
    |> case do
      [phase] -> phase
      nil -> nil
    end
  end
end
