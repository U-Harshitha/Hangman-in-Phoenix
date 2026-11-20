defmodule HangmanWeb.GameLiveTest do
  use HangmanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the bare host redirects to /hangman", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/hangman"
  end

  test "health check", %{conn: conn} do
    assert text_response(get(conn, "/hangman/health"), 200) == "ok"
  end

  test "pick a channel and difficulty, then play a full episode", %{conn: conn} do
    {:ok, view, html} = live(conn, "/hangman")
    assert html =~ "Sitcom"

    view |> element("button[phx-value-channel=big_bang]") |> render_click()
    view |> element("button[phx-value-difficulty=hard]") |> render_click()
    assert view |> element(".tv-lower-third") |> render() =~ "The Big Bang Theory"

    view |> element("#play") |> render_click()
    assert has_element?(view, "#word")
    assert has_element?(view, ".ep-show", "Big Bang Theory")
    assert has_element?(view, ".clue-text")
    assert has_element?(view, "#mascot[data-show=big_bang]")

    for letter <- Hangman.Game.alphabet() do
      render_keydown(view, "key", %{"key" => letter})
    end

    assert has_element?(view, "#result")
    assert has_element?(view, ".result-fact")

    render_keydown(view, "key", %{"key" => "Enter"})
    refute has_element?(view, "#result")
  end

  test "arrow keys flip channels on the TV guide", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    assert has_element?(view, ".guide-row.is-selected[data-show=friends]")
    render_keydown(view, "key", %{"key" => "ArrowRight"})
    assert has_element?(view, ".guide-row.is-selected[data-show=big_bang]")
    render_keydown(view, "key", %{"key" => "ArrowLeft"})
    render_keydown(view, "key", %{"key" => "ArrowLeft"})
    assert has_element?(view, ".guide-row.is-selected[data-show=surf]")
  end

  test "channel surfing plays a real show", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element("button[phx-value-channel=surf]") |> render_click()
    view |> element("#play") |> render_click()

    assert view |> element("#mascot") |> render() =~
             ~r/data-show="(friends|big_bang|modern_family|brooklyn_99)"/
  end

  test "x-ray mode shows the process, real code and lessons", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    refute has_element?(view, "#xray-panel")

    view |> element("#xray-toggle") |> render_click()
    assert has_element?(view, "#xray-panel")
    assert render(view) =~ "#PID&lt;"

    view |> element("#play") |> render_click()
    view |> element(".pin[phx-value-section=word]") |> render_click()
    assert has_element?(view, ".xp-code", "def tiles")

    view |> element(".xp-tabs button[phx-value-tab=lessons]") |> render_click()
    assert has_element?(view, ".lesson")

    render_keydown(view, "key", %{"key" => "Escape"})
    refute has_element?(view, "#xray-panel")
  end

  test "stats are restored from connect params", %{conn: conn} do
    conn = put_connect_params(conn, %{"stats" => %{"played" => 4, "wins" => 3, "score" => 900}})
    {:ok, view, _html} = live(conn, "/hangman")
    assert view |> element("[data-stat=score]") |> render() =~ "900"
    assert render(view) =~ "75%"
  end

  test "clicking keys guesses letters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element("#play") |> render_click()
    view |> element("button[data-key=e]") |> render_click()
    assert view |> element("button[data-key=e]") |> render() =~ "disabled"
  end

  test "the TV dial flips channels", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element(".tv-dial[phx-value-dir='1']") |> render_click()
    assert has_element?(view, ".guide-row.is-selected[data-show=big_bang]")
    view |> element(".tv-dial[phx-value-dir='-1']") |> render_click()
    view |> element(".tv-dial[phx-value-dir='-1']") |> render_click()
    assert has_element?(view, ".guide-row.is-selected[data-show=surf]")
  end

  test "answers are grouped by word", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element("#play") |> render_click()
    assert has_element?(view, "#word .word-group .tile")
  end

  test "x-ray trace and why-phoenix tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element("#xray-toggle") |> render_click()

    view |> element(".xp-tabs button[phx-value-tab=trace]") |> render_click()
    assert has_element?(view, "#trace .trace-step", "It lands in your process")

    view |> element(".xp-tabs button[phx-value-tab=phoenix]") |> render_click()
    assert has_element?(view, ".spec", "Let it crash")
    assert has_element?(view, ".tree", "LiveView process")
    assert has_element?(view, "#crash")
    assert has_element?(view, ".compare")
  end

  test "with x-ray on, LiveView telemetry timings are pushed to the browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/hangman")
    view |> element("#play") |> render_click()
    view |> element("#xray-toggle") |> render_click()
    view |> element("button[data-key=e]") |> render_click()
    assert_push_event(view, "xray_trace", %{event: "guess", event_us: us, render_us: _})
    assert is_integer(us)
  end

  test "after the crash demo, the new process explains what happened", %{conn: conn} do
    conn = put_connect_params(conn, %{"crash" => %{"pid" => "#PID<0.1.0>", "ms" => 840}})
    {:ok, view, _html} = live(conn, "/hangman")
    assert has_element?(view, "#recovered", "840 ms")
    assert has_element?(view, ".xp-tabs button.is-active", "Why Phoenix")
  end

  test "bogus crash params are ignored", %{conn: conn} do
    conn = put_connect_params(conn, %{"crash" => %{"pid" => "<script>", "ms" => "x"}})
    {:ok, view, _html} = live(conn, "/hangman")
    refute has_element?(view, "#xray-panel")
  end
end
