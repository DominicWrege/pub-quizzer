defmodule PubQuizzerWeb.DevAuthController do
  @moduledoc """
  Dev-only auth backdoor for E2E tests.

  Logs in as the user matching the given email, bypassing the magic-link
  email flow entirely. Only mounted when `:dev_routes` is enabled.
  """

  use PubQuizzerWeb, :controller

  alias PubQuizzer.Accounts
  alias PubQuizzer.Quiz

  def login_as(conn, %{"email" => email}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        conn
        |> put_flash(:error, "User not found: #{email}")
        |> redirect(to: "/admin/login")

      user ->
        {:ok, _} = Accounts.sign_in_user(user)

        user =
          if conn.params["reset_guide"] == "true" do
            Accounts.reset_guide_seen(user)
          else
            user
          end

        conn
        |> put_session(:user_id, user.id)
        |> redirect(to: "/admin/events")
    end
  end

  def cleanup_events(conn, _params) do
    Quiz.list_events()
    |> Enum.each(&Quiz.delete_event/1)

    json(conn, %{ok: true})
  end
end
