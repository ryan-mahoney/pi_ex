defmodule PiEx.Command.GetEntries do
  @moduledoc false
  defstruct [:id, :since]

  @type t :: %__MODULE__{id: String.t() | nil, since: String.t() | nil}
end
