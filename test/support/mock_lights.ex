defmodule MockLights do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: PoliceBox.Lights)
  end

  def messages(pid) do
    GenServer.call(pid, :messages, 1000)
  end

  def next_message(pid) do
    GenServer.call(pid, :next_message, 1000)
  end

  defmodule State do
    @enforce_keys [:dummy]
    defstruct(
      dummy: nil,
      messages: :queue.new(),
      waiting: nil
    )
  end

  @impl true
  def init(_) do
    {:ok, %State{dummy: nil}}
  end

  @impl true
  def handle_cast(msg, state) do
    case state.waiting do
      nil ->
        {:noreply, %State{state | messages: :queue.in(msg, state.messages)}}

      {_, _} = from ->
        GenServer.reply(from, msg)
        {:noreply, %State{state | waiting: nil}}
    end
  end

  @impl true
  def handle_call(:messages, _from, state) do
    {:reply, :queue.to_list(state.messages), %State{state | messages: :queue.new()}}
  end

  @impl true
  def handle_call(:next_message, from, state) do
    case :queue.out(state.messages) do
      {{:value, msg}, rest} -> {:reply, msg, %State{state | messages: rest}}
      {:empty, _} -> {:noreply, %State{state | waiting: from}}
    end
  end
end
