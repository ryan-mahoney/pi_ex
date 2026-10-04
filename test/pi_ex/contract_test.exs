defmodule PiEx.ContractTest do
  use ExUnit.Case

  alias PiEx.Event.AgentEnd
  alias PiEx.Event.MessageUpdate
  alias PiEx.Response

  @moduletag :contract

  @stub_pi Path.expand("../support/stub_pi.sh", __DIR__)

  setup do
    {:ok, pid} = PiEx.Instance.start_link(pi_path: @stub_pi)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end)

    {:ok, pid: pid}
  end

  test "full prompt lifecycle", %{pid: pid} do
    PiEx.prompt(pid, "hello")

    assert_receive {:pi_event, _, %PiEx.Event.AgentStart{}}, 5000

    assert_receive {:pi_event, _, %MessageUpdate{type: :text_delta, text: "Hello from contract pi"}},
                   5000

    assert_receive {:pi_event, _, %AgentEnd{}}, 5000
  end

  test "query APIs return expected response envelopes", %{pid: pid} do
    cases = [
      %{
        command: "get_state",
        call: fn -> PiEx.get_state(pid) end,
        validate_data: fn data ->
          assert data == %{"isStreaming" => false}
        end
      },
      %{
        command: "get_messages",
        call: fn -> PiEx.get_messages(pid) end,
        validate_data: fn data ->
          assert is_list(data["messages"])
          assert Enum.any?(data["messages"], fn message -> message["role"] == "assistant" end)
        end
      },
      %{
        command: "get_session_stats",
        call: fn -> PiEx.get_session_stats(pid) end,
        validate_data: fn data ->
          assert is_map(data["totals"])
          assert is_number(data["totals"]["inputTokens"])
          assert is_map(data["cost"])
          assert is_number(data["cost"]["usd"])
        end
      },
      %{
        command: "bash",
        call: fn -> PiEx.bash(pid, "echo hello") end,
        validate_data: fn data ->
          assert data["stdout"] == "hello"
          assert data["stderr"] == ""
          assert data["exitCode"] == 0
        end
      },
      %{
        command: "set_model",
        call: fn -> PiEx.set_model(pid, "openai-codex", "gpt-5.3-codex") end,
        validate_data: fn data ->
          assert data["provider"] == "openai-codex"
          assert data["modelId"] == "gpt-5.3-codex"
          assert data["applied"] == true
        end
      }
    ]

    for %{command: expected_command, call: call, validate_data: validate_data} <- cases do
      assert {:ok, %Response{command: ^expected_command, success: true, error: nil, data: data}} = call.()
      validate_data.(data)
    end
  end

  test "delta accumulation over full stream", %{pid: pid} do
    PiEx.prompt(pid, "hello")

    delta = collect_delta(PiEx.Delta.new())
    assert PiEx.Delta.text(delta) == "Hello from contract pi"
    assert PiEx.Delta.done?(delta)
  end

  describe "start options, os_pid and stop" do
    @describetag :tmp_dir

    test "starts the child in the given cd with the given env", %{tmp_dir: tmp_dir} do
      {:ok, pid} =
        PiEx.Instance.start_link(
          pi_path: @stub_pi,
          cd: tmp_dir,
          env: [{'PI_EX_STUB_REPORT', 'marker-1'}]
        )

      assert_receive {:pi_event, _, %PiEx.Event.Unknown{type: "stub_report", data: data}}, 5000
      assert data["cwd"] == physical_path(tmp_dir)
      assert data["env"] == "marker-1"

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end)
    end

    test "os_pid/1 returns a live OS PID while the instance runs", %{tmp_dir: tmp_dir} do
      {:ok, pid} = PiEx.Instance.start_link(pi_path: @stub_pi, cd: tmp_dir)
      os_pid = PiEx.os_pid(pid)

      assert is_integer(os_pid) and os_pid > 0
      assert os_process_alive?(os_pid)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end)
    end

    test "stop/2 returns :ok once the OS process is gone", %{tmp_dir: tmp_dir} do
      {:ok, pid} = PiEx.Instance.start_link(pi_path: @stub_pi, cd: tmp_dir)
      os_pid = PiEx.os_pid(pid)

      assert :ok = PiEx.stop(pid)
      refute os_process_alive?(os_pid)
      refute Process.alive?(pid)
    end

    test "stop/2 returns {:error, :still_running} when the child outlives the deadline", %{
      tmp_dir: tmp_dir
    } do
      {:ok, pid} =
        PiEx.Instance.start_link(
          pi_path: @stub_pi,
          cd: tmp_dir,
          env: [{"PI_EX_STUB_LINGER", "30"}]
        )

      os_pid = PiEx.os_pid(pid)

      assert {:error, :still_running} = PiEx.stop(pid, 200)
      assert os_process_alive?(os_pid)

      on_exit(fn ->
        System.cmd("kill", [Integer.to_string(os_pid)], stderr_to_stdout: true)
      end)
    end

    test "stop/2 on an already-stopped instance returns :ok", %{tmp_dir: tmp_dir} do
      {:ok, pid} = PiEx.Instance.start_link(pi_path: @stub_pi, cd: tmp_dir)

      assert :ok = PiEx.stop(pid)
      assert :ok = PiEx.stop(pid)
    end
  end

  defp physical_path(path) do
    {cwd, 0} = System.cmd("pwd", ["-P"], cd: path)
    String.trim(cwd)
  end

  defp os_process_alive?(os_pid) do
    {_, status} = System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)
    status == 0
  end

  defp collect_delta(delta) do
    receive do
      {:pi_event, _, %MessageUpdate{} = event} ->
        delta = PiEx.Delta.apply_event(delta, event)
        collect_delta(delta)

      {:pi_event, _, %AgentEnd{} = event} ->
        PiEx.Delta.apply_event(delta, event)

      {:pi_event, _, _} ->
        collect_delta(delta)
    after
      5000 -> delta
    end
  end
end