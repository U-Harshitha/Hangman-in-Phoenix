defmodule HangmanWeb.GameLiveTest do
  use HangmanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the bare host redirects to /hangman", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/hangman"
  end

  test "health check", %{conn: conn} do
    assert text_response(get(conn, "/hangman/health"), 200) == "ok"
  end

  test "pick a category and difficulty, then play a full round", %{conn: conn} do
    {:ok, view, html} = live(conn, "/hangman")
    assert html =~ "Choose a category"

    view |> element("button[phx-value-category=space]") |> render_click()
    view |> element("button[phx-value-difficulty=hard]") |> render_click()
    assert view |> element("#play") |> render() =~ "Play Space"

    view |> element("#play") |> render_click()
    assert has_element?(view, "#word")
    assert has_element?(view, ".chip", "Space")

    # Guess every letter of the alphabet via the physical keyboard handler;
    # the round must end (won or lost) and show the result dialog.
    for letter <- Hangman.Game.alphabet() do
      render_keydown(view, "key", %{"key" => letter})
    end

    assert has_element?(view, "#result")
    assert has_element?(view, "#stats-bar [data-stat=score]")

    # Enter starts the next round.
    render_keydown(view, "key", %{"key" => "Enter"})
    refute has_element?(view, "#result")
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
end
