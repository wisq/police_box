defmodule PoliceBox.Lights do
  use GenServer
  require Logger

  @log_prefix "[#{inspect(__MODULE__)}] "

  # Flash for one second on, one second off.
  @flash_delay 1000
  # Minimum brightness is enough.
  @brightness 1

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
  def handle_info({:flash, ref, on_off}, %State{flash_ref: ref} = state) do
    case on_off do
      :on ->
        enable_leds(true)
        {:noreply, state |> schedule_flash(:off)}

      :off ->
        enable_leds(false)
        {:noreply, state |> schedule_flash(:on)}
    end
  end

  @impl true
  def handle_info({:flash, _, _}, state) do
    Logger.debug("Ignoring expired :flash message")
    {:noreply, state}
  end

  defp handle_state_change(%State{running: false}, %State{running: true} = new) do
    enable_leds(true)
    pulse_leds(2)
    update_leds_percent(new.percent)
    new |> schedule_flash(:off)
  end

  defp handle_state_change(%State{running: true}, %State{running: false} = new) do
    pulse_leds(1)
    enable_leds(false)
    %State{new | flash_ref: nil}
  end

  defp handle_state_change(%State{running: true}, %State{running: true} = new) do
    if new.flash_on, do: update_leds_percent(new.percent)
    new
  end

  defp handle_state_change(%State{running: false}, %State{running: false} = new), do: new

  @pulse [0..255, 255..0]
         |> Enum.flat_map(& &1)
         |> Enum.map(&PiGlow.LED.gamma_correct/1)

  defp pulse_leds(count) do
    1..count
    |> Enum.flat_map(fn _ -> @pulse end)
    |> Enum.each(fn v -> PiGlow.map_power(fn _ -> v end) end)

    PiGlow.wait()
  end

  defp enable_leds(enable) do
    PiGlow.map_enable(fn _ -> enable end)
  end

  defp update_leds_percent(nil), do: :noop

  defp update_leds_percent(percent) do
    leds = percent_to_leds(percent)

    PiGlow.map_power(fn led ->
      if led in leds, do: @brightness, else: 0
    end)
  end

  @leds PiGlow.LED.leds()
        |> Enum.sort_by(fn led -> {0 - led.ring, led.arm} end)

  defp percent_to_leds(float) when float >= 0.0 and float <= 1.0 do
    count = round(float / 1.0 * 17 + 1)
    @leds |> Enum.take(count)
  end

  defp schedule_flash(%State{running: true} = state, on_off) do
    ref = make_ref()
    Process.send_after(self(), {:flash, ref, on_off}, @flash_delay)
    %State{state | flash_ref: ref}
  end
end
