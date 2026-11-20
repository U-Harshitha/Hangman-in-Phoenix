defmodule HangmanWeb.Xray.Telemetry do
  @moduledoc """
  Feeds the X-ray Trace tab with server timings from the `:telemetry`
  events LiveView already emits for every event and render.

  Telemetry handlers run inside the process that emitted the event, which
  here is the player's own LiveView process. So the handler can stash the
  event timing in the process dictionary and, once the render that follows
  finishes, send both timings to itself. `GameLive.handle_info/2` pushes
  them to the browser. Nothing happens unless that player has X-ray open.
  """

  @events [
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :render, :stop]
  ]

  def attach, do: :telemetry.attach_many("xray-trace", @events, &__MODULE__.handle/4, nil)

  # xray:telemetry
  def handle([_, _, :handle_event, :stop], %{duration: d}, %{socket: socket, event: event}, _) do
    if watching?(socket), do: Process.put(:xray_event, {event, micros(d)})
  end

  def handle([_, _, :render, :stop], %{duration: d}, %{socket: socket}, _) do
    with true <- watching?(socket),
         {event, event_us} <- Process.delete(:xray_event) do
      send(self(), {:xray_trace, %{event: event, event_us: event_us, render_us: micros(d)}})
    end
  end

  # xray:end

  def handle(_event, _measurements, _metadata, _config), do: :ok

  defp watching?(%{view: HangmanWeb.GameLive, assigns: %{xray: true}}), do: true
  defp watching?(_), do: false

  defp micros(native), do: System.convert_time_unit(native, :native, :microsecond)
end
