defmodule PiEx.Command.ClearQueue do
  @moduledoc false
  defstruct [:id]

  @type t :: %__MODULE__{id: String.t() | nil}
end
