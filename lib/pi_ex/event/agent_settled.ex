defmodule PiEx.Event.AgentSettled do
  @moduledoc "Pi will not continue automatically through retries, compaction recovery, or queued messages."
  defstruct []
  @type t :: %__MODULE__{}
end
