defmodule PoliceBox.LightsTest do
  use ExUnit.Case, async: true

  alias PoliceBox.Lights

  setup :start

  describe "when backup starts" do
    test "pulses lights twice, then enables one light", %{pid: pid, mock: mock} do
      Lights.update(true, 0.0, pid)
      Process.sleep(100)

      assert [
               {:set_enable, 0x3F},
               :pulse,
               :pulse,
               :wait,
               {:set_power, power}
             ] = MockPiGlow.events_reversed(mock) |> compress_pulses()

      assert Enum.count(power, &(&1 > 0)) == 1
    end

    test "enables more lights based on starting progress", %{pid: pid, mock: mock} do
      percent = :rand.uniform()
      Lights.update(true, percent, pid)
      Process.sleep(100)

      assert [{:set_power, power} | _] = MockPiGlow.events_reversed(mock)
      assert_in_delta percent_leds_enabled(power), percent, 1.5 / 18.0
    end
  end

  describe "during backup" do
    setup :begin_backup

    test "enables additional lights as backup progresses", %{pid: pid, mock: mock} do
      # Generates a random ascending list of roughly 5 to 10 progress steps.
      # The last element will always be 1.0 (100%).
      Stream.unfold(0.0, fn
        :done -> nil
        n when n > 1.0 -> {1.0, :done}
        n -> {n, n + 0.1 + :rand.uniform() / 10.0}
      end)
      |> Enum.each(fn percent ->
        Lights.update(true, percent, pid)
        Process.sleep(50)

        assert [{:set_power, power}] = MockPiGlow.events_reversed(mock) |> ignore_flashes()
        assert_in_delta percent_leds_enabled(power), percent, 1.5 / 18.0
      end)
    end

    test "pulses once at end of backup", %{pid: pid, mock: mock} do
      Lights.update(false, nil, pid)
      Process.sleep(100)

      assert [
               :pulse,
               :wait,
               {:set_enable, 0}
             ] = MockPiGlow.events_reversed(mock) |> compress_pulses()
    end

    test "flashes lights on and off at regular intervals", %{mock: mock} do
      assert {{:set_enable, 0x00}, _} = MockPiGlow.next_event(mock)
      assert {{:set_enable, 0x3F}, t1} = MockPiGlow.next_event(mock)
      assert {{:set_enable, 0x00}, t2} = MockPiGlow.next_event(mock)
      assert {{:set_enable, 0x3F}, t3} = MockPiGlow.next_event(mock)

      assert_in_delta t1, 200, 30
      assert_in_delta t2, 200, 30
      assert_in_delta t3, 200, 30
    end
  end

  defp start(_ctx) do
    {:ok, mock} = start_supervised(MockPiGlow)
    {:ok, pid} = start_supervised({PoliceBox.Lights, name: nil})
    [mock: mock, pid: pid]
  end

  defp begin_backup(%{pid: pid, mock: mock}) do
    Lights.update(true, 0.0, pid)
    Process.sleep(100)
    # Discard events:
    MockPiGlow.events_reversed(mock)
    []
  end

  defp compress_pulses(events) do
    {nil, nil, events} =
      events
      |> Enum.reduce({nil, nil, []}, &reduce_compress_pulses/2)

    events
  end

  defp reduce_compress_pulses({:set_power, 0}, {nil, nil, accum}) do
    {:rising, 0, accum}
  end

  defp reduce_compress_pulses({:set_power, b}, {:rising, a, accum}) when a <= b do
    case b do
      255 -> {:falling, b, accum}
      _ -> {:rising, b, accum}
    end
  end

  defp reduce_compress_pulses({:set_power, b}, {:falling, a, accum}) when a >= b do
    case b do
      0 -> {nil, nil, [:pulse | accum]}
      _ -> {:falling, b, accum}
    end
  end

  defp reduce_compress_pulses(other, {nil, nil, accum}) do
    {nil, nil, [other | accum]}
  end

  defp percent_leds_enabled(0), do: 0.0
  defp percent_leds_enabled(n) when is_integer(n), do: 1.0
  defp percent_leds_enabled(list), do: Enum.count(list, &(&1 > 0)) / Enum.count(list)

  defp ignore_flashes(events) do
    events
    |> Enum.reject(fn
      {:set_enable, _} -> true
      _ -> false
    end)
  end
end
