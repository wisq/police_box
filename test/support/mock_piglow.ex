defmodule MockPiGlow do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: PiGlow)
  end

  def events(pid) do
    events_reversed(pid)
    |> Enum.reverse()
  end

  def events_reversed(pid) do
    GenServer.call(pid, :events)
  end

  def next_event(pid) do
    {ms, {:ok, ev}} = :timer.tc(fn -> GenServer.call(pid, :next) end)
    {ev, div(ms, 1000)}
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_cast({op, binary}, events) when op in [:set_power, :set_enable] do
    ev = {op, compress_same_bytes(binary)}
    {:noreply, events |> add_event(ev)}
  end

  @impl true
  def handle_call(:events, _from, events) do
    {:reply, events, []}
  end

  @impl true
  def handle_call(:next, {_, _} = from, events) do
    case events do
      [] -> {:noreply, from}
      {_, _} -> {:reply, {:error, :already_waiting}}
      [_ | _] -> {:reply, {:error, :events_not_empty}}
    end
  end

  @impl true
  def handle_call(:wait, _from, events) do
    {:reply, :ok, events |> add_event(:wait)}
  end

  defp add_event(events, ev) when is_list(events), do: [ev | events]

  defp add_event({_, _} = from, ev) do
    GenServer.reply(from, {:ok, ev})
    []
  end

  defp compress_same_bytes(binary) do
    list = binary |> :erlang.binary_to_list()

    case Enum.uniq(list) do
      [value] -> value
      _ -> list
    end
  end
end
