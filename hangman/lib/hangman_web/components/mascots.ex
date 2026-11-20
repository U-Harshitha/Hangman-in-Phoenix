defmodule HangmanWeb.Mascots do
  @moduledoc """
  One original SVG "set" per show, standing in for the classic gallows.

  Each drawing has:
    * `[data-frame]` — set dressing, drawn in when a round starts
    * `[data-part="0".."5"]` — six groups revealed one per mistake
    * `.fx-win` / `.fx-lose` — extras the Mascot hook reveals at the end

  The Mascot hook (assets/js/hooks/board.js) owns all animation; the server
  only sets `data-mistakes` and `data-status` on the wrapper.
  """
  use Phoenix.Component

  attr :show, :atom, required: true
  attr :preview, :boolean, default: false, doc: "fully drawn, static (menu thumbnails)"
  attr :class, :string, default: nil

  def set(assigns) do
    ~H"""
    <svg
      viewBox="0 0 240 280"
      class={["mascot-svg", @preview && "is-preview", @class]}
      role="img"
      aria-label={label(@show)}
    >
      {scene(%{show: @show, uid: if(@preview, do: "p-#{@show}", else: "m-#{@show}")})}
    </svg>
    """
  end

  def label(:friends), do: "Marcel the monkey hanging from a rope in front of a purple wall"
  def label(:big_bang), do: "An unstable atom drawn on a whiteboard"
  def label(:modern_family), do: "Fizbo the clown on a sunny suburban lawn"
  def label(:brooklyn_99), do: "Cheddar the corgi standing in a police lineup"

  # ── Friends: Marcel ────────────────────────────────────────────────────
  defp scene(%{show: :friends} = assigns) do
    ~H"""
    <rect width="240" height="280" fill="#5d3f8c" />
    <path d="M0 0h240v280H0z" fill={"url(##{@uid}-wall)"} opacity=".5" />
    <defs>
      <radialGradient id={"#{@uid}-wall"} cx=".5" cy=".3" r=".8">
        <stop offset="0" stop-color="#8a67c4" />
        <stop offset="1" stop-color="#3c2463" />
      </radialGradient>
    </defs>
    <%!-- the yellow peephole frame, on the wall behind --%>
    <g opacity=".85" fill="none" stroke="#f2c94c" stroke-width="5">
      <ellipse cx="62" cy="150" rx="26" ry="34" />
      <ellipse cx="62" cy="150" rx="17" ry="24" stroke-width="2" />
    </g>
    <%!-- the orange couch --%>
    <g>
      <rect x="18" y="214" width="204" height="40" rx="12" fill="#d9622b" />
      <rect x="10" y="226" width="26" height="40" rx="10" fill="#c4521f" />
      <rect x="204" y="226" width="26" height="40" rx="10" fill="#c4521f" />
      <rect x="34" y="240" width="172" height="22" rx="8" fill="#e8743a" />
      <rect x="0" y="266" width="240" height="14" fill="#3a2418" />
    </g>
    <path data-frame d="M14 24 H226" class="ink" stroke="#7a4e2d" stroke-width="7" />
    <path data-frame d="M118 24 V62" class="ink" stroke="#e9d5a8" stroke-width="3" />

    <g class="figure">
      <g data-part="0">
        <circle cx="139" cy="94" r="9" fill="#2e211b" class="ink" />
        <circle cx="173" cy="94" r="9" fill="#2e211b" class="ink" />
        <circle cx="156" cy="98" r="19" fill="#2e211b" class="ink" />
      </g>
      <g data-part="1">
        <ellipse cx="156" cy="103" rx="13" ry="12" fill="#f0d9b5" class="ink" />
        <circle cx="151" cy="100" r="2.4" fill="#1b1310" />
        <circle cx="161" cy="100" r="2.4" fill="#1b1310" />
        <path d="M151 108 q5 4 10 0" class="ink" stroke-width="2" />
      </g>
      <g data-part="2">
        <ellipse cx="156" cy="142" rx="16" ry="23" fill="#2e211b" class="ink" />
        <ellipse cx="156" cy="146" rx="9" ry="13" fill="#f0d9b5" />
      </g>
      <g data-part="3">
        <path d="M147 128 C138 112 125 90 119 66" class="ink limb" stroke="#2e211b" />
        <circle cx="119" cy="64" r="5" fill="#f0d9b5" class="ink" />
        <path d="M166 128 C178 136 182 150 178 162" class="ink limb" stroke="#2e211b" />
        <circle cx="177" cy="164" r="5" fill="#f0d9b5" class="ink" />
      </g>
      <g data-part="4">
        <path d="M149 160 C146 172 142 182 140 194" class="ink limb" stroke="#2e211b" />
        <ellipse cx="139" cy="197" rx="6" ry="4" fill="#f0d9b5" class="ink" />
        <path d="M163 160 C166 172 170 182 172 194" class="ink limb" stroke="#2e211b" />
        <ellipse cx="173" cy="197" rx="6" ry="4" fill="#f0d9b5" class="ink" />
      </g>
      <g data-part="5">
        <path
          d="M168 154 C196 160 206 190 192 204 C182 212 172 202 181 196"
          class="ink limb"
          stroke="#2e211b"
          stroke-width="5"
        />
      </g>
    </g>
    <g class="fx-lose">
      <rect
        x="40"
        y="108"
        width="160"
        height="44"
        rx="6"
        fill="#f7efe1"
        stroke="#2e211b"
        stroke-width="3"
      />
      <text x="120" y="127" text-anchor="middle" class="sign-text">THIS WAY TO THE</text>
      <text x="120" y="144" text-anchor="middle" class="sign-text sign-strong">SAN DIEGO ZOO →</text>
    </g>
    """
  end

  # ── The Big Bang Theory: an unstable atom on the whiteboard ────────────
  defp scene(%{show: :big_bang} = assigns) do
    ~H"""
    <rect width="240" height="280" fill="#1d2a3a" />
    <path d="M40 228 L26 278 M200 228 L214 278" stroke="#7d8a99" stroke-width="5" />
    <rect x="12" y="16" width="216" height="210" rx="6" fill="#f5f7f9" />
    <path data-frame d="M12 16 H228 V226 H12 Z" class="ink" stroke="#8d99a6" stroke-width="5" />
    <rect x="20" y="226" width="200" height="8" rx="2" fill="#aeb8c2" />
    <g class="marker-faint">
      <text x="24" y="44">E = mc²</text>
      <text x="150" y="44">∂ψ/∂t = Ĥψ</text>
      <text x="24" y="214">Σ F = ma</text>
      <text x="164" y="214">ħ = h/2π</text>
    </g>
    <g class="figure">
      <g data-part="0">
        <circle cx="120" cy="122" r="12" fill="#e63946" class="ink" stroke="#8d1b24" />
        <circle cx="115" cy="118" r="4.5" fill="#457b9d" />
        <circle cx="125" cy="126" r="4.5" fill="#457b9d" />
        <circle cx="124" cy="116" r="3.5" fill="#f1faee" />
      </g>
      <g data-part="1" class="orbit">
        <ellipse cx="120" cy="122" rx="66" ry="21" class="ink" stroke="#2b5fad" stroke-width="3" />
      </g>
      <g data-part="2" class="orbit">
        <ellipse
          cx="120"
          cy="122"
          rx="66"
          ry="21"
          transform="rotate(60 120 122)"
          class="ink"
          stroke="#2b5fad"
          stroke-width="3"
        />
      </g>
      <g data-part="3" class="orbit">
        <ellipse
          cx="120"
          cy="122"
          rx="66"
          ry="21"
          transform="rotate(-60 120 122)"
          class="ink"
          stroke="#2b5fad"
          stroke-width="3"
        />
      </g>
      <g data-part="4">
        <circle cx="186" cy="122" r="6" fill="#2b5fad" />
        <circle cx="153" cy="179" r="6" fill="#2b5fad" />
        <circle cx="87" cy="65" r="6" fill="#2b5fad" />
      </g>
      <g data-part="5">
        <circle
          cx="120"
          cy="122"
          r="86"
          class="ink"
          stroke="#d62828"
          stroke-width="2.5"
          stroke-dasharray="6 7"
        />
        <text x="36" y="70" class="marker-red">critical mass!</text>
      </g>
    </g>
    <g class="fx-lose">
      <circle cx="120" cy="126" r="110" fill="#fff4d6" class="burst" />
      <text x="120" y="142" text-anchor="middle" class="bang-text">BANG!</text>
    </g>
    """
  end

  # ── Modern Family: Fizbo on the lawn ───────────────────────────────────
  defp scene(%{show: :modern_family} = assigns) do
    ~H"""
    <defs>
      <linearGradient id={"#{@uid}-sky"} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#7cc6f2" />
        <stop offset="1" stop-color="#d8f1ff" />
      </linearGradient>
    </defs>
    <rect width="240" height="280" fill={"url(##{@uid}-sky)"} />
    <circle cx="200" cy="44" r="20" fill="#ffd166" />
    <path d="M0 236 Q120 222 240 236 V280 H0 Z" fill="#5cb85c" />
    <path d="M0 250 Q120 238 240 250 V280 H0 Z" fill="#4aa64a" />
    <g data-frame class="ink" stroke="#ffffff" stroke-width="4">
      <path d="M8 222 H232" />
      <path d="M8 236 H232" />
    </g>
    <g data-frame class="ink" stroke="#ffffff" stroke-width="6">
      <path d="M20 248 V214 M44 248 V214 M68 248 V214 M172 248 V214 M196 248 V214 M220 248 V214" />
    </g>
    <g class="figure">
      <g data-part="0">
        <circle cx="120" cy="134" r="46" fill="#fff4e6" class="ink" stroke="#3a2a2a" />
      </g>
      <g data-part="1">
        <circle cx="70" cy="112" r="15" fill="#ef476f" class="ink" stroke="#3a2a2a" />
        <circle cx="64" cy="134" r="14" fill="#ffd166" class="ink" stroke="#3a2a2a" />
        <circle cx="72" cy="155" r="12" fill="#118ab2" class="ink" stroke="#3a2a2a" />
        <circle cx="170" cy="112" r="15" fill="#118ab2" class="ink" stroke="#3a2a2a" />
        <circle cx="176" cy="134" r="14" fill="#ef476f" class="ink" stroke="#3a2a2a" />
        <circle cx="168" cy="155" r="12" fill="#ffd166" class="ink" stroke="#3a2a2a" />
      </g>
      <g data-part="2">
        <path d="M96 108 l8 -12 l8 12 Z M128 108 l8 -12 l8 12 Z" fill="#118ab2" />
        <ellipse cx="104" cy="120" rx="8" ry="10" fill="#fff" class="ink" stroke="#3a2a2a" />
        <ellipse cx="136" cy="120" rx="8" ry="10" fill="#fff" class="ink" stroke="#3a2a2a" />
        <circle cx="105" cy="122" r="3.5" fill="#3a2a2a" />
        <circle cx="137" cy="122" r="3.5" fill="#3a2a2a" />
      </g>
      <g data-part="3">
        <circle cx="120" cy="140" r="11" fill="#e63946" class="ink" stroke="#8d1b24" />
        <circle cx="116" cy="136" r="3" fill="#fff" opacity=".8" />
      </g>
      <g data-part="4" class="mouth">
        <path
          d="M92 152 Q120 190 148 152 Q120 168 92 152 Z"
          fill="#e63946"
          class="ink"
          stroke="#8d1b24"
        />
      </g>
      <g data-part="5" class="hat">
        <path d="M100 92 L140 92 L134 64 L106 64 Z" fill="#6a4c93" class="ink" stroke="#3a2a2a" />
        <path d="M92 92 H148" class="ink" stroke="#3a2a2a" stroke-width="5" />
        <circle cx="132" cy="72" r="6" fill="#ffd166" />
      </g>
    </g>
    <g class="fx-lose">
      <text x="120" y="40" text-anchor="middle" class="honk-text">HONK!</text>
    </g>
    """
  end

  # ── Brooklyn Nine-Nine: Cheddar in the lineup ──────────────────────────
  defp scene(%{show: :brooklyn_99} = assigns) do
    ~H"""
    <rect width="240" height="280" fill="#d9dee5" />
    <g data-frame class="ink" stroke="#7b8796" stroke-width="2">
      <path d="M0 40 H240 M0 82 H240 M0 124 H240 M0 166 H240 M0 208 H240" />
    </g>
    <g class="lineup-label">
      <text x="230" y="36" text-anchor="end">6'</text>
      <text x="230" y="78" text-anchor="end">5'</text>
      <text x="230" y="120" text-anchor="end">4'</text>
      <text x="230" y="162" text-anchor="end">3'</text>
      <text x="230" y="204" text-anchor="end">2'</text>
    </g>
    <rect x="0" y="232" width="240" height="48" fill="#3b4656" />
    <g class="figure">
      <g data-part="0">
        <ellipse cx="110" cy="192" rx="46" ry="22" fill="#e39b52" class="ink" stroke="#5a3415" />
        <ellipse cx="112" cy="203" rx="30" ry="9" fill="#fff4e4" />
      </g>
      <g data-part="1">
        <circle cx="160" cy="168" r="21" fill="#e39b52" class="ink" stroke="#5a3415" />
        <ellipse cx="173" cy="177" rx="11" ry="8" fill="#fff4e4" />
        <path d="M152 172 Q156 160 160 150 Q166 162 162 176 Z" fill="#fff4e4" />
      </g>
      <g data-part="2">
        <path d="M148 154 L141 126 L162 146 Z" fill="#e39b52" class="ink" stroke="#5a3415" />
        <path d="M149 147 L145 133 L156 144 Z" fill="#f7c99b" />
        <path d="M166 148 L174 122 L180 150 Z" fill="#e39b52" class="ink" stroke="#5a3415" />
        <path d="M170 145 L174 131 L177 146 Z" fill="#f7c99b" />
      </g>
      <g data-part="3">
        <rect
          x="78"
          y="204"
          width="11"
          height="26"
          rx="4"
          fill="#e39b52"
          class="ink"
          stroke="#5a3415"
        />
        <rect
          x="95"
          y="208"
          width="11"
          height="24"
          rx="4"
          fill="#e39b52"
          class="ink"
          stroke="#5a3415"
        />
        <rect
          x="122"
          y="208"
          width="11"
          height="24"
          rx="4"
          fill="#e39b52"
          class="ink"
          stroke="#5a3415"
        />
        <rect
          x="138"
          y="204"
          width="11"
          height="26"
          rx="4"
          fill="#e39b52"
          class="ink"
          stroke="#5a3415"
        />
      </g>
      <g data-part="4" class="tail">
        <ellipse
          cx="64"
          cy="184"
          rx="11"
          ry="7"
          transform="rotate(-25 64 184)"
          fill="#e39b52"
          class="ink"
          stroke="#5a3415"
        />
      </g>
      <g data-part="5">
        <circle cx="163" cy="163" r="3" fill="#1d1d1d" />
        <circle cx="183" cy="173" r="3.5" fill="#1d1d1d" />
        <path d="M172 182 q5 3 10 -1" class="ink" stroke="#5a3415" stroke-width="2" />
      </g>
    </g>
    <g class="fx-lose">
      <rect x="62" y="236" width="116" height="38" rx="3" fill="#111827" />
      <text x="120" y="252" text-anchor="middle" class="placard-text">99TH PRECINCT</text>
      <text x="120" y="268" text-anchor="middle" class="placard-text placard-strong">
        CHEDDAR · 0099
      </text>
    </g>
    """
  end
end
