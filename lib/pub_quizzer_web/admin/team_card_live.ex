defmodule PubQuizzerWeb.Admin.TeamCardLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  embed_templates "team_card_live/*"

  @impl true
  def render(assigns) do
    team_cards(assigns)
  end

  @impl true
  def mount(_params, _session, socket) do
    # page_title intentionally nil: @page margin:0 suppresses the browser's
    # print header/footer anyway, and we don't want "Team-Karten" showing up
    # on the printed A5 sheet or in the tab title.
    {:ok, assign(socket, page_title: nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, url, socket) do
    event = Quiz.get_event_with_teams!(id)
    base = base_url_from_request(url)

    cards =
      event.teams
      |> Enum.sort_by(& &1.slot_index)
      |> Enum.map(fn team ->
        slot = team.slot_index + 1
        card_url = "#{base}#{~p"/quiz/join/#{event.code}/#{slot}"}"

        svg =
          card_url
          |> EQRCode.encode()
          |> EQRCode.svg(color: "#1e40af", background: "#ffffff", width: 400)

        %{team: team, slot: slot, url: card_url, svg: svg}
      end)

    {:noreply, assign(socket, event: event, cards: cards)}
  end

  # Mirror of EventLive's helper — same default-port omission so QR URLs are
  # clean ("https://host") in prod and reachable (with port) on dev/LAN.
  defp base_url_from_request(url) do
    uri = URI.parse(url)

    case {uri.scheme, uri.port} do
      {"https", 443} -> "https://#{uri.host}"
      {"http", 80} -> "http://#{uri.host}"
      {scheme, port} -> "#{scheme}://#{uri.host}:#{port}"
    end
  end
end
