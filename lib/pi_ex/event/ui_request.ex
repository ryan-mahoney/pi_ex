defmodule PiEx.Event.UIRequest do
  @moduledoc """
  A UI prompt sent by Pi requesting user interaction.

  The `method` field indicates the kind of prompt (`:select`, `:confirm`,
  `:input`, etc.). Dialog methods are answered with `PiEx.respond_ui/3`;
  fire-and-forget methods (`:notify`, `:set_status`, `:set_widget`,
  `:set_title`, `:set_editor_text`) expect no response. `raw` holds the full
  decoded event map; the widget, status and notify fields keep the
  extension-specific payloads (`widgetKey`, `widgetLines`, `notifyType`,
  `statusKey`, `statusText` on the wire).
  """

  defstruct [
    :id,
    :method,
    :title,
    :options,
    :message,
    :placeholder,
    :prefill,
    :timeout,
    :raw,
    :widget_key,
    :widget_lines,
    :notify_type,
    :status_key,
    :status_text
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          method:
            :select
            | :confirm
            | :input
            | :editor
            | :notify
            | :set_status
            | :set_widget
            | :set_title
            | :set_editor_text
            | :unknown,
          title: String.t() | nil,
          options: [String.t()] | nil,
          message: String.t() | nil,
          placeholder: String.t() | nil,
          prefill: String.t() | nil,
          timeout: pos_integer() | nil,
          raw: map() | nil,
          widget_key: String.t() | nil,
          widget_lines: [String.t()] | nil,
          notify_type: String.t() | nil,
          status_key: String.t() | nil,
          status_text: String.t() | nil
        }
end
