defmodule Brook.Driver.Test do
  @behaviour Brook.Driver
  use GenServer
  require Logger

  def send_event(_type, event) do
    GenServer.call(via(), {:send, event})
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: via())
  end

  def init([]) do
    {:ok, %{}}
  end

  def handle_cast({:register, pid}, state) do
    {:noreply, Map.put(state, :pid, pid)}
  end

  def handle_call({:send, event}, _from, %{pid: pid} = state) do
    case Brook.Deserializer.deserialize(struct(Brook.Event), event) do
      {:ok, brook_event} ->
        send(pid, {:brook_event, brook_event})

      {:error, reason} ->
        Logger.error("Unable to deserialize event: #{inspect(event)}, error reason: #{inspect(reason)}")
    end

    {:reply, :ok, state}
  end

  def handle_call({:send, _event}, _from, state) do
    Logger.error("#{__MODULE__}: No pid available to send brook event to. Brook.Test.register/1 must be called first.")
    {:stop, :no_pid, state}
  end

  def handle_call(message, _from, state) do
    Logger.error("#{__MODULE__}: invalid message #{inspect(message)} with state #{inspect(state)}")
    {:stop, :invalid_call, state}
  end

  def via() do
    {:via, Registry, {Brook.Registry, __MODULE__}}
  end
end