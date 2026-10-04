defmodule PiEx.Response do
  @moduledoc "Struct returned by correlated commands like `get_state/1` and `get_messages/1`."
  @enforce_keys [:command, :success]
  defstruct [:id, :command, :success, :error, :data]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          command: String.t(),
          success: boolean(),
          error: String.t() | nil,
          data: map() | nil
        }
end
