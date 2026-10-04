defmodule PiEx.Event do
  @moduledoc """
  Events emitted by a `PiEx.Instance` during a Pi session.

  Events are delivered to the owner process as `{:pi_event, id, event}` messages,
  where `event` is one of the structs listed below.

  ## Lifecycle

  A typical prompt cycle emits events in this order:

      AgentStart -> TurnStart -> MessageStart -> MessageUpdate* -> MessageEnd -> TurnEnd -> AgentEnd -> AgentSettled

  Tool use adds `ToolExecutionStart`, `ToolExecutionUpdate`, and
  `ToolExecutionEnd` events within a turn. Multiple turns may occur when the
  agent loops through tool calls. `AgentEnd` closes one low-level agent run;
  retries, compaction recovery, steering or follow-up work may still continue.
  `AgentSettled` means Pi will not continue automatically for this session-level run.

  ## Streaming content

  `PiEx.Event.MessageUpdate` carries the streaming deltas - text fragments,
  thinking fragments, and tool-call fragments. Use `PiEx.Delta` to accumulate
  these into a complete response.

  ## Other events

  * `PiEx.Event.UIRequest` - Pi is asking for user interaction (select, confirm, input, etc.)
  * `PiEx.Event.AutoCompactionStart` / `PiEx.Event.AutoCompactionEnd` - conversation compaction
  * `PiEx.Event.AutoRetryStart` / `PiEx.Event.AutoRetryEnd` - automatic retry after transient errors
  * `PiEx.Event.ExtensionError` - an extension encountered an error
  * `PiEx.Event.Exited` - the Pi OS process exited
  * `Unknown` - an unrecognized event type (forward-compatibility)
  """
end
