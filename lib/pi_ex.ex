defmodule PiEx do
  @moduledoc """
  Elixir client for the Pi coding agent RPC protocol.

  Spawns a `pi --mode rpc` process and communicates over JSON-over-stdin/stdout.
  Events are delivered to the calling process as `{:pi_event, id, event}` messages.

  ## Quick start

      {:ok, pid} = PiEx.Instance.start_link([])

      :ok = PiEx.prompt(pid, "Hello!")

      receive do
        {:pi_event, _, %PiEx.Event.MessageUpdate{type: :text_delta, text: text}} ->
          IO.write(text)
      end

  See `PiEx.Instance` for start options and `PiEx.Delta` for accumulating streamed
  responses.
  """

  @doc "Send a new prompt. Returns `{:error, :already_streaming}` if a response is in progress."
  @spec prompt(GenServer.server(), String.t(), keyword()) :: :ok | {:error, :already_streaming}
  defdelegate prompt(server, message, opts \\ []), to: PiEx.Instance

  @doc "Inject a steering message into the current conversation."
  @spec steer(GenServer.server(), String.t(), keyword()) :: :ok
  defdelegate steer(server, message, opts \\ []), to: PiEx.Instance

  @doc "Send a follow-up message."
  @spec follow_up(GenServer.server(), String.t(), keyword()) :: :ok
  defdelegate follow_up(server, message, opts \\ []), to: PiEx.Instance

  @doc "Abort the current streaming response."
  @spec abort(GenServer.server()) :: :ok
  defdelegate abort(server), to: PiEx.Instance

  @doc "Query Pi's current state. Blocks until Pi responds."
  @spec get_state(GenServer.server()) :: {:ok, PiEx.Response.t()} | {:error, term()}
  defdelegate get_state(server), to: PiEx.Instance

  @doc "Retrieve the conversation message history. Blocks until Pi responds."
  @spec get_messages(GenServer.server()) :: {:ok, PiEx.Response.t()} | {:error, term()}
  defdelegate get_messages(server), to: PiEx.Instance

  @doc "Switch the model provider and model ID."
  @spec set_model(GenServer.server(), String.t(), String.t()) :: {:ok, PiEx.Response.t()} | {:error, term()}
  defdelegate set_model(server, provider, model_id), to: PiEx.Instance

  @doc "Get session statistics (token usage, costs, etc.). Blocks until Pi responds."
  @spec get_session_stats(GenServer.server()) :: {:ok, PiEx.Response.t()} | {:error, term()}
  defdelegate get_session_stats(server), to: PiEx.Instance

  @doc "Execute a shell command via Pi. Blocks until Pi responds."
  @spec bash(GenServer.server(), String.t()) :: {:ok, PiEx.Response.t()} | {:error, term()}
  defdelegate bash(server, command), to: PiEx.Instance

  @doc "Respond to a UI request from Pi (select, confirm, input, etc.)."
  @spec respond_ui(GenServer.server(), String.t(), map()) :: :ok
  defdelegate respond_ui(server, request_id, response), to: PiEx.Instance

  @doc "Return the OS PID of the child process, or `nil` when it is unavailable."
  @spec os_pid(GenServer.server()) :: pos_integer() | nil
  defdelegate os_pid(server), to: PiEx.Instance

  @doc """
  Stop the child process and its instance.

  Closes the port, polls the child's OS process every 50 ms until it is gone or
  `timeout` ms pass, then stops the instance. Returns `{:error, :still_running}`
  when the child outlives the deadline. Stopping an already-stopped instance
  returns `:ok`.
  """
  @spec stop(GenServer.server(), pos_integer()) :: :ok | {:error, :still_running}
  def stop(server, timeout \\ 5_000) do
    os_pid = close_and_os_pid(server)

    gone? = is_nil(os_pid) or os_process_gone?(os_pid, System.monotonic_time(:millisecond) + timeout)

    stop_instance(server)
    if gone?, do: :ok, else: {:error, :still_running}
  end

  defp close_and_os_pid(server) do
    PiEx.Instance.close_port(server)
  catch
    # The instance is gone (e.g. it saw the child exit), so the child is gone too.
    :exit, {:noproc, _} -> nil
  end

  defp stop_instance(server) do
    GenServer.stop(server, :normal)
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp os_process_gone?(os_pid, deadline) do
    if os_process_alive?(os_pid) do
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(50)
        os_process_gone?(os_pid, deadline)
      end
    else
      true
    end
  end

  defp os_process_alive?(os_pid) do
    {_, exit_status} =
      System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)

    exit_status == 0
  end
end
