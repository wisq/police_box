defmodule PoliceBox.Server do
  use GenServer
  require Logger

  @default_port 1963
  @log_prefix "[#{inspect(__MODULE__)}] "

  def start_link(opts) do
    {port, opts} = Keyword.pop(opts, :port, @default_port)
    GenServer.start_link(__MODULE__, port, opts)
  end

  def port(pid) do
    GenServer.call(pid, :port)
  end

  @impl true
  def init(port) do
    Logger.info(@log_prefix <> "Listening on port #{port}.")
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, socket}
  end

  @impl true
  def handle_call(:port, _from, socket) do
    {:reply, :inet.port(socket), socket}
  end

  @phase_regex ~r/^\s*BackupPhase = ([A-Za-z]+);$/m
  @running_regex ~r/^\s*Running = ([01]);$/m
  @percent_regex ~r/^\s*(?:Percent|FractionDone) = \"?([0-9e.-]+)\"?;$/m

  @impl true
  def handle_info({:udp, socket, ip, port, data}, socket) do
    case parse_packet(data) do
      {:ok, phase, running, percent} ->
        Logger.info(
          @log_prefix <>
            "From #{:inet.ntoa(ip)}:#{port}: " <>
            inspect(phase: phase, running: running, percent: percent)
        )

        PoliceBox.Lights.update(running, percent)
        {:noreply, socket}

      :error ->
        Logger.warn(@log_prefix <> "Received bogus packet from #{:inet.ntoa(ip)}:#{port}.")
        {:noreply, socket}
    end
  end

  defp parse_packet(data) do
    with {:ok, true} <- match_running(data),
         {:ok, phase} <- match_phase(data),
         {:ok, percent} <- calculate_percent(phase, data) do
      {:ok, phase, true, percent}
    else
      {:ok, false} -> {:ok, nil, false, nil}
      :error -> :error
    end
  end

  defp calculate_percent("FindingBackupVol", _), do: {:ok, 0.0}
  defp calculate_percent("MountingBackupVol", _), do: {:ok, 0.0}
  defp calculate_percent("PreparingSourceVolumes", _), do: {:ok, 0.0}
  defp calculate_percent("Finishing", _), do: {:ok, 1.0}
  defp calculate_percent("ThinningPostBackup", _), do: {:ok, 1.0}

  defp calculate_percent("FindingChanges", data) do
    with {:ok, percent} <- match_percent(data) do
      {:ok, 0.1 * percent}
    end
  end

  defp calculate_percent("Copying", data) do
    with {:ok, percent} <- match_percent(data) do
      {:ok, 0.1 + 0.9 * percent}
    end
  end

  defp match_phase(data) do
    case Regex.run(@phase_regex, data, captures: :all_but_first) do
      [_, phase] -> {:ok, phase}
      nil -> :error
    end
  end

  defp match_running(data) do
    case Regex.run(@running_regex, data, captures: :all_but_first) do
      [_, "0"] -> {:ok, false}
      [_, "1"] -> {:ok, true}
      nil -> :error
    end
  end

  defp match_percent(data) do
    case Regex.run(@percent_regex, data, captures: :all_but_first) do
      [_, float] -> parse_float(float)
      nil -> :error
    end
  end

  defp parse_float(str) do
    with {float, ""} <- Float.parse(str) do
      {:ok, float}
    else
      {_, _} ->
        Logger.error("Leftover characters parsing float #{inspect(str)}")
        :error

      :error ->
        Logger.error("Cannot parse float #{inspect(str)}")
        :error
    end
  end
end
