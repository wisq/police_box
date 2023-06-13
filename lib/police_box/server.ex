defmodule PoliceBox.Server do
  use GenServer
  require Logger

  @default_port 1963
  @log_prefix "[PoliceBox] "

  def start_link(opts) do
    {port, opts} = Keyword.pop(opts, :port, @default_port)
    GenServer.start_link(__MODULE__, port, opts)
  end

  defmodule State do
    @enforce_keys [:socket]
    defstruct(
      socket: nil,
      running: false,
      percent: nil
    )
  end

  @impl true
  def init(port) do
    Logger.info(@log_prefix <> "Listening on port #{port}.")
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %State{socket: socket}}
  end

  @running_regex ~r/^\s*Running = ([01]);$/m
  @percent_regex ~r/^\s*Percent = \"([0-9.-]+)\";$/m

  @impl true
  def handle_info({:udp, socket, ip, port, data}, %State{socket: socket} = old_state) do
    with {:ok, running} <- match_running(data),
         {:ok, percent} <- match_percent(data) do
      new_state = %State{old_state | running: running, percent: percent}

      Logger.info(
        @log_prefix <>
          "From #{:inet.ntoa(ip)}:#{port}: " <>
          inspect(running: running, percent: percent)
      )

      handle_state_change(old_state, new_state)
      {:noreply, new_state}
    else
      :error ->
        Logger.warn(@log_prefix <> "Received bogus packet from #{:inet.ntoa(ip)}:#{port}.")
        {:noreply, old_state}
    end
  end

  defp handle_state_change(old, %State{running: true} = new) do
    if !old.running, do: pulse_leds(2)
    update_leds_percent(new.percent)
  end

  defp handle_state_change(old, %State{running: false}) do
    if old.running, do: pulse_leds(1)
    turn_off_leds()
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
      [_, "-1"] -> {:ok, nil}
      [_, float] -> parse_float(float)
      nil -> nil
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, ""} -> {:ok, float}
      {_, _} -> :error
      :error -> :error
    end
  end

  @pulse [0..255, 255..0]
         |> Enum.flat_map(& &1)
         |> Enum.map(&PiGlow.LED.gamma_correct/1)

  defp pulse_leds(count) do
    1..count
    |> Enum.flat_map(fn _ -> @pulse end)
    |> Enum.each(fn v -> PiGlow.map_leds(fn _ -> v end) end)
  end

  defp turn_off_leds do
    PiGlow.map_leds(fn _ -> 0 end)
  end

  defp update_leds_percent(percent) do
    leds = percent_to_leds(percent)

    PiGlow.map_leds(fn led ->
      if led in leds, do: 1, else: 0
    end)
  end

  @leds PiGlow.LED.leds()
        |> Enum.sort_by(fn led -> {0 - led.ring, led.arm} end)

  def percent_to_leds(float) when float >= 0.0 and float <= 1.0 do
    count = round(float / 1.0 * 17 + 1)
    @leds |> Enum.take(count)
  end
end
