defmodule PiEx.Event.MessageEnd do
  @moduledoc """
  Emitted at the end of an assistant message within a turn.

  `raw` holds the full decoded event map, including the authoritative
  final `message` payload.
  """
  defstruct [:raw]
  @type t :: %__MODULE__{raw: map() | nil}
end
