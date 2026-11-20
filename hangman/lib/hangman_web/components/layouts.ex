defmodule HangmanWeb.Layouts do
  @moduledoc "The root HTML document and the in-LiveView app shell."
  use HangmanWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc """
  App shell: the Three.js ember field behind everything, plus flash
  notices. Rendered inside the LiveView so the `Scene` hook can mount.
  """
  def app(assigns) do
    ~H"""
    <div
      id="scene"
      phx-hook="Scene"
      phx-update="ignore"
      class="pointer-events-none fixed inset-0 -z-10"
      aria-hidden="true"
    >
    </div>
    <div class="grain pointer-events-none fixed inset-0 -z-10" aria-hidden="true"></div>
    <div class="relative flex min-h-dvh flex-col">
      {render_slot(@inner_block)}
    </div>
    <.flash_group flash={@flash} />
    """
  end
end
