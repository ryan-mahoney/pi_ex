defmodule PiEx.InstanceTest do
  use ExUnit.Case, async: true

  # Helper: start an Instance with a fake port ref and writer function injected.
  # The Instance skips Port.open when :port is provided.
  # The writer sends {:port_write, data} to the test process for assertions.
  alias PiEx.Command.ClearQueue
  alias PiEx.Command.GetEntries
  alias PiEx.Event.AgentStart
  alias PiEx.Event.UIRequest

  defp start_instance(opts \\ []) do
    test_pid = self()
    fake_port = Keyword.get_lazy(opts, :port, &make_ref/0)
    writer = Keyword.get(opts, :writer, fn _port, data -> send(test_pid, {:port_write, data}) end)
    opts = opts |> Keyword.put(:port, fake_port) |> Keyword.put(:writer, writer)
    {:ok, pid} = PiEx.Instance.start_link(opts)
    %{pid: pid, port: fake_port}
  end

  # Helper: simulate a line arriving from the port
  defp send_line(%{pid: pid, port: port}, json) do
    send(pid, {port, {:data, {:eol, json}}})
  end

  describe "start_link/1" do
    test "starts with a fake port" do
      %{pid: pid} = start_instance()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "infers id from atom name" do
      %{pid: pid} = start_instance(name: :test_agent_infer_id)
      state = :sys.get_state(pid)
      assert state.id == :test_agent_infer_id
      GenServer.stop(pid, :normal)
    end

    test "uses explicit id over name" do
      %{pid: pid} = start_instance(id: "custom_id")
      state = :sys.get_state(pid)
      assert state.id == "custom_id"
      GenServer.stop(pid, :normal)
    end
  end

  describe "start_link validation" do
    test "missing executable returns {:error, {:executable_not_found, path}} and the caller survives" do
      missing = "pi-ex-missing-#{System.unique_integer([:positive])}"

      assert {:error, {:executable_not_found, ^missing}} =
               PiEx.Instance.start_link(pi_path: missing)

      assert Process.alive?(self())
    end

    test "missing cd directory returns {:error, {:invalid_cd, path}} and the caller survives" do
      stub = Path.expand("../support/stub_pi.sh", __DIR__)
      missing = Path.join(System.tmp_dir!(), "pi-ex-missing-#{System.unique_integer([:positive])}")

      assert {:error, {:invalid_cd, ^missing}} =
               PiEx.Instance.start_link(pi_path: stub, cd: missing)

      assert Process.alive?(self())
    end
  end

  describe "os_pid" do
    test "a fake-port instance has no OS PID" do
      ctx = start_instance()
      assert is_nil(PiEx.Instance.os_pid(ctx.pid))
      GenServer.stop(ctx.pid, :normal)
    end
  end

  describe "stop/2" do
    test "returns :ok when the instance exits while the close call is in flight" do
      ctx = start_instance()
      :sys.suspend(ctx.pid)

      task =
        Task.async(fn ->
          # One sender, so the instance handles the exit before the close call.
          send(ctx.pid, {ctx.port, {:exit_status, 0}})
          PiEx.stop(ctx.pid)
        end)

      # Both messages wait behind the suspension; resuming exits the instance
      # with :normal before it can answer the close call.
      Process.sleep(50)
      :sys.resume(ctx.pid)

      assert :ok = Task.await(task, 5_000)
      refute Process.alive?(ctx.pid)
    end
  end

  describe "event dispatch" do
    test "dispatches events to owner process by default" do
      ctx = start_instance()
      send_line(ctx, ~s|{"type":"agent_start"}|)

      assert_receive {:pi_event, _, %AgentStart{}}
      GenServer.stop(ctx.pid, :normal)
    end

    test "dispatches events via broadcast function when provided" do
      test_pid = self()

      broadcast = fn id, event ->
        send(test_pid, {:broadcast, id, event})
      end

      ctx = start_instance(id: :my_agent, broadcast: broadcast)
      send_line(ctx, ~s|{"type":"agent_start"}|)

      assert_receive {:broadcast, :my_agent, %AgentStart{}}
      GenServer.stop(ctx.pid, :normal)
    end
  end

  describe "uncorrelated response" do
    test "dispatches response as event when no pending call matches" do
      ctx = start_instance()

      response =
        ~s|{"type":"response","command":"prompt","success":true,"id":"no-match","data":null}|

      send_line(ctx, response)

      assert_receive {:pi_event, _, %PiEx.Response{command: "prompt", success: true}}
      GenServer.stop(ctx.pid, :normal)
    end
  end

  describe "correlated commands" do
    test "get_state sends command and returns response when response arrives" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.Instance.get_state(ctx.pid) end)

      # Wait for the GenServer to process the call and park the caller
      assert_receive {:port_write, _}

      # Extract the pending call id from state to send a matching response
      state = :sys.get_state(ctx.pid)
      [{id, _from}] = Map.to_list(state.pending_calls)

      response =
        ~s|{"type":"response","command":"get_state","success":true,"id":"#{id}","data":{"isStreaming":false}}|

      send_line(ctx, response)

      assert {:ok, %PiEx.Response{success: true}} = Task.await(task)
      GenServer.stop(ctx.pid, :normal)
    end

    test "prompt writes command to port and returns :ok" do
      ctx = start_instance()
      assert :ok = PiEx.Instance.prompt(ctx.pid, "hello")
      assert_receive {:port_write, data}
      decoded = JSON.decode!(String.trim_trailing(data, "\n"))
      assert decoded["type"] == "prompt"
      assert decoded["message"] == "hello"
      GenServer.stop(ctx.pid, :normal)
    end
  end

  describe "command/3" do
    test "writes the generated id and does not return while only a different id has arrived" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.command(ctx.pid, %GetEntries{since: "abc"}, 5_000) end)
      assert_receive {:port_write, data}

      decoded = JSON.decode!(String.trim_trailing(data, "\n"))
      assert decoded["type"] == "get_entries"
      assert decoded["since"] == "abc"
      id = decoded["id"]

      assert is_binary(id) and id != ""

      send_line(ctx, ~s|{"type":"response","command":"get_entries","success":true,"id":"other","data":{}}|)
      assert_receive {:pi_event, _, %PiEx.Response{id: "other"}}

      assert nil == Task.yield(task, 100)

      send_line(
        ctx,
        ~s|{"type":"response","command":"get_entries","success":true,"id":"#{id}","data":{"leafId":"abc"}}|
      )

      assert {:ok, %PiEx.Response{id: ^id, command: "get_entries", success: true}} = Task.await(task)
      GenServer.stop(ctx.pid, :normal)
    end

    test "a success: false response with the matching id returns the error response" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.command(ctx.pid, %ClearQueue{}, 5_000) end)
      assert_receive {:port_write, data}
      id = JSON.decode!(String.trim_trailing(data, "\n"))["id"]

      send_line(
        ctx,
        ~s|{"type":"response","command":"clear_queue","success":false,"id":"#{id}","error":"no session"}|
      )

      assert {:error, %PiEx.Response{success: false, error: "no session"}} = Task.await(task)
      GenServer.stop(ctx.pid, :normal)
    end

    test "returns {:error, :timeout} at the deadline, clears the entry, and the late response reaches the owner" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.command(ctx.pid, %GetEntries{}, 100) end)
      assert_receive {:port_write, data}
      id = JSON.decode!(String.trim_trailing(data, "\n"))["id"]

      assert {:error, :timeout} = Task.await(task)

      state = :sys.get_state(ctx.pid)
      assert state.pending_calls == %{}

      send_line(
        ctx,
        ~s|{"type":"response","command":"get_entries","success":true,"id":"#{id}","data":{}}|
      )

      assert_receive {:pi_event, _, %PiEx.Response{id: ^id}}
      assert Process.alive?(ctx.pid)
      GenServer.stop(ctx.pid, :normal)
    end

    test "a response before the deadline cancels it: no stray timeout reply reaches the caller" do
      test_pid = self()

      helper =
        spawn(fn ->
          receive do
            {:go, instance, port} ->
              receive do
                {:written, data} ->
                  id = JSON.decode!(String.trim_trailing(data, "\n"))["id"]
                  Process.sleep(20)

                  line =
                    ~s|{"type":"response","command":"get_entries","success":true,"id":"#{id}","data":{}}|

                  send(instance, {port, {:data, {:eol, line}}})
                  send(test_pid, :injected)
              end
          end
        end)

      ctx = start_instance(writer: fn _port, data -> send(helper, {:written, data}) end)
      send(helper, {:go, ctx.pid, ctx.port})

      assert {:ok, %PiEx.Response{}} = PiEx.command(ctx.pid, %GetEntries{}, 100)
      assert_receive :injected

      refute_receive _, 250
      GenServer.stop(ctx.pid, :normal)
    end

    test "Pi exiting while a call is pending returns {:error, {:pi_exited, code}}" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.command(ctx.pid, %GetEntries{}, 5_000) end)
      assert_receive {:port_write, _}

      send(ctx.pid, {ctx.port, {:exit_status, 3}})

      assert {:error, {:pi_exited, 3}} = Task.await(task)
    end

    test "a writer that raises ArgumentError makes the call return {:error, :port_closed} with no pending entry" do
      ctx = start_instance(writer: fn _port, _data -> raise ArgumentError, "closed port" end)

      assert {:error, :port_closed} = PiEx.command(ctx.pid, %GetEntries{}, 5_000)

      state = :sys.get_state(ctx.pid)
      assert state.pending_calls == %{}
      GenServer.stop(ctx.pid, :normal)
    end
  end

  # --- Task 9: Line Buffering and Exit Handling ---

  describe "line buffering" do
    test "accumulates noeol chunks and decodes on eol" do
      ctx = start_instance()

      chunk1 = ~s|{"type":"agent|
      chunk2 = ~s|_start"}|

      send(ctx.pid, {ctx.port, {:data, {:noeol, chunk1}}})
      refute_receive {:pi_event, _, _}, 50

      send(ctx.pid, {ctx.port, {:data, {:eol, chunk2}}})
      assert_receive {:pi_event, _, %AgentStart{}}

      GenServer.stop(ctx.pid, :normal)
    end
  end

  describe "exit handling" do
    test "replies error to pending calls on exit" do
      ctx = start_instance()

      task = Task.async(fn -> PiEx.Instance.get_state(ctx.pid) end)

      # Wait for the command to be written
      assert_receive {:port_write, _}

      send(ctx.pid, {ctx.port, {:exit_status, 1}})

      assert {:error, {:pi_exited, 1}} = Task.await(task)
    end

    test "dispatches Exited event on exit" do
      ctx = start_instance()
      send(ctx.pid, {ctx.port, {:exit_status, 0}})

      assert_receive {:pi_event, _, %PiEx.Event.Exited{code: 0}}
    end
  end

  # --- Task 10: Extension UI Protocol ---

  describe "extension UI protocol" do
    test "dispatches UIRequest event and parks timer" do
      ctx = start_instance()

      json =
        ~s|{"type":"extension_ui_request","id":"ui-1","method":"select","title":"Pick","options":["a","b"]}|

      send_line(ctx, json)

      assert_receive {:pi_event, _, %UIRequest{id: "ui-1", method: :select}}

      state = :sys.get_state(ctx.pid)
      assert Map.has_key?(state.pending_ui, "ui-1")

      GenServer.stop(ctx.pid, :normal)
    end

    test "respond_ui clears timer and writes to port" do
      ctx = start_instance()

      json =
        ~s|{"type":"extension_ui_request","id":"ui-1","method":"select","title":"Pick","options":["a","b"]}|

      send_line(ctx, json)
      assert_receive {:pi_event, _, %UIRequest{}}

      PiEx.Instance.respond_ui(ctx.pid, "ui-1", %{value: "a"})

      assert_receive {:port_write, _}

      state = :sys.get_state(ctx.pid)
      refute Map.has_key?(state.pending_ui, "ui-1")

      GenServer.stop(ctx.pid, :normal)
    end

    test "respond_ui ignores unknown request_id" do
      ctx = start_instance()

      PiEx.Instance.respond_ui(ctx.pid, "unknown-id", %{value: "a"})

      # Give the cast time to process
      _ = :sys.get_state(ctx.pid)

      # No write should have happened - unknown IDs are silently dropped
      refute_receive {:port_write, _}

      GenServer.stop(ctx.pid, :normal)
    end

    test "auto-cancels UI request on timeout" do
      ctx = start_instance(ui_timeout: 100)

      json =
        ~s|{"type":"extension_ui_request","id":"ui-1","method":"select","title":"Pick","options":["a"]}|

      send_line(ctx, json)
      assert_receive {:pi_event, _, %UIRequest{}}

      # Wait for the auto-cancel response to be written to port
      assert_receive {:port_write, _}, 500

      state = :sys.get_state(ctx.pid)
      refute Map.has_key?(state.pending_ui, "ui-1")

      GenServer.stop(ctx.pid, :normal)
    end
  end

  # --- Task 11: Streaming Behavior Guard ---

  describe "streaming guard" do
    test "rejects prompt while streaming" do
      ctx = start_instance()

      # First prompt succeeds
      assert :ok = PiEx.Instance.prompt(ctx.pid, "first")
      assert_receive {:port_write, _}

      # Simulate Pi starting to stream
      send_line(ctx, ~s|{"type":"agent_start"}|)
      assert_receive {:pi_event, _, %AgentStart{}}

      # Second prompt should be rejected
      assert {:error, :already_streaming} = PiEx.Instance.prompt(ctx.pid, "second")

      GenServer.stop(ctx.pid, :normal)
    end

    test "steer succeeds during streaming" do
      ctx = start_instance()

      # Enter streaming state
      assert :ok = PiEx.Instance.prompt(ctx.pid, "first")
      assert_receive {:port_write, _}
      send_line(ctx, ~s|{"type":"agent_start"}|)
      assert_receive {:pi_event, _, %AgentStart{}}

      # Steer should work even while streaming
      assert :ok = PiEx.Instance.steer(ctx.pid, "focus on tests")
      assert_receive {:port_write, _}

      GenServer.stop(ctx.pid, :normal)
    end

    test "follow_up succeeds during streaming" do
      ctx = start_instance()

      # Enter streaming state
      assert :ok = PiEx.Instance.prompt(ctx.pid, "first")
      assert_receive {:port_write, _}
      send_line(ctx, ~s|{"type":"agent_start"}|)
      assert_receive {:pi_event, _, %AgentStart{}}

      # follow_up should work even while streaming
      assert :ok = PiEx.Instance.follow_up(ctx.pid, "also do this")
      assert_receive {:port_write, _}

      GenServer.stop(ctx.pid, :normal)
    end

    test "allows prompt after streaming ends" do
      ctx = start_instance()

      assert :ok = PiEx.Instance.prompt(ctx.pid, "first")
      assert_receive {:port_write, _}

      send_line(ctx, ~s|{"type":"agent_start"}|)
      send_line(ctx, ~s|{"type":"agent_end","messages":[]}|)
      assert_receive {:pi_event, _, %PiEx.Event.AgentEnd{}}

      assert :ok = PiEx.Instance.prompt(ctx.pid, "second")
      assert_receive {:port_write, _}

      GenServer.stop(ctx.pid, :normal)
    end
  end
end
