defmodule PoliceBox.Server do
  use GenServer
  require Logger

  @default_port 1963
  @log_prefix "[#{inspect(__MODULE__)}] "

  def start_link(opts) do
    {port, opts} = Keyword.pop(opts, :port, @default_port)
    GenServer.start_link(__MODULE__, port, opts)
  end

  @impl true
  def init(port) do
    Logger.info(@log_prefix <> "Listening on port #{port}.")
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, socket}
  end

  @phase_regex ~r/^\s*BackupPhase = ([A-Za-z]+);$/m
  @running_regex ~r/^\s*Running = ([01]);$/m
  @percent_regex ~r/^\s*Percent = \"([0-9.-]+)\";$/m

  @impl true
  def handle_info({:udp, socket, ip, port, data}, socket) do
    case parse_packet(data) do
      {:ok, running, percent} ->
        Logger.info(
          @log_prefix <>
            "From #{:inet.ntoa(ip)}:#{port}: " <>
            inspect(running: running, percent: percent)
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
         {:ok, percent} <- match_percent(data),
         {:ok, phase} <- match_phase(data) do
      percent =
        case phase do
          "ThinningPostBackup" -> nil
          "MountingBackupVol" -> 0.0
          "PreparingSourceVolumes" -> 0.0
          "FindingChanges" -> 0.0
          "Copying" -> percent
          "Finishing" -> 1.0
          _ -> nil
        end

      {:ok, true, percent}
    else
      {:ok, false} -> {:ok, false, nil}
      :error -> :error
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
      [_, "-1"] -> {:ok, 1.0}
      [_, float] -> parse_float(float)
      nil -> {:ok, nil}
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, ""} -> {:ok, float}
      {_, _} -> :error
      :error -> :error
    end
  end
end
