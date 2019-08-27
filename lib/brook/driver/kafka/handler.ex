defmodule Brook.Driver.Kafka.Handler do
  @moduledoc """
  Implements the Elsa message handler behaviour for
  the Brook Kafka driver.
  """
  use Elsa.Consumer.MessageHandler
  require Logger

  @doc """
  Takes a list of Kafka messages consumed by Elsa and
  processes each with Brook.
  """
  @spec handle_messages([term()]) :: :ack
  def handle_messages(messages) do
    messages
    |> Enum.map(fn message -> message.value end)
    |> Enum.each(&Brook.Event.process/1)

    :ack
  end
end
