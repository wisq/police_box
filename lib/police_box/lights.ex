defmodule PoliceBox.Lights do
  use GenServer
  require Logger

  @log_prefix "[#{inspect(__MODULE__)}] "
  @flash_delay 1000

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def update(running, percent, pid \\ __MODULE__) do
    GenServer.cast(pid, {:update, running, percent})
  end

  defmodule State do
    defstruct(
      running: false,
      percent: nil,
      flash_ref: nil,
      flash_on: true
    )
  end

  @impl true
  def init(_) do
    Logger.info(@log_prefix <> "Started.")
    {:ok, %State{}}
  end

  @impl true
  def handle_cast({:update, running, percent}, old_state) do
    new_state = %State{old_state | running: running, percent: percent}
    new_state = handle_state_change(old_state, new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:flash, ref}, %State{flash_ref: ref, flash_on: on} = state) do
    case on do
      true -> update_leds_percent(state.percent)
      false -> turn_off_leds()
    end

    {:noreply, %State{state | flash_on: !on} |> schedule_flash()}
  end

  @impl true
  def handle_info({:flash, _}, state) do
    Logger.debug("Ignoring expired :flash message")
    {:noreply, state}
  end

  defp handle_state_change(%State{running: false}, %State{running: true} = new) do
    pulse_leds(2)
    update_leds_percent(new.percent)
    new |> schedule_flash()
  end

  defp handle_state_change(%State{running: true}, %State{running: false} = new) do
    pulse_leds(1)
    turn_off_leds()
    %State{new | flash_ref: nil}
  end

  defp handle_state_change(%State{running: true}, %State{running: true} = new) do
    update_leds_percent(new.percent)
    new
  end

  defp handle_state_change(%State{running: false}, %State{running: false} = new), do: new

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

  defp percent_to_leds(float) when float >= 0.0 and float <= 1.0 do
    count = round(float / 1.0 * 17 + 1)
    @leds |> Enum.take(count)
  end

  defp schedule_flash(%State{running: true} = state) do
    ref = make_ref()
    Process.send_after(self(), {:flash, ref}, @flash_delay)
    %State{state | flash_ref: ref}
  end
end
