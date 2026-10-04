defmodule PiEx.Event.MessageStart do
  @moduledoc """
  Emitted at the start of an assistant message within a turn.

  `raw` holds the full decoded event map, including the `message` payload.
  """
  defstruct [:raw]
  @type t :: %__MODULE__{raw: map() | nil}
end
