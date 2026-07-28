defmodule PubQuizzerWeb.GuideController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Accounts

  def mark_seen(conn, _params) do
    user = conn.assigns.current_scope.user
    Accounts.mark_guide_seen(user)
    send_resp(conn, 200, "ok")
  end
end
