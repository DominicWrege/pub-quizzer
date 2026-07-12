defmodule PubQuizzer.Accounts.AuthEmail do
  @moduledoc """
  Email composition and delivery for authentication (magic links).
  """

  import Swoosh.Email

  alias PubQuizzer.Mailer

  def deliver_magic_link(to_email, url) do
    {name, email} = from_email()

    new()
    |> to(to_email)
    |> from({name, email})
    |> subject("Dein Kneipenquiz Login-Link")
    |> html_body(html_body(url))
    |> text_body("Login-Link: #{url}\nDer Link ist 15 Minuten gültig.")
    |> Mailer.deliver()
  end

  defp from_email do
    email = Application.get_env(:pub_quizzer, :mailer, [])[:from_email]
    {"Kneipenquiz", email}
  end

  defp html_body(url) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
      <h2>Kneipenquiz</h2>
      <p>Klicke auf den folgenden Link, um dich anzumelden:</p>
      <p style="margin: 24px 0;">
        <a href="#{url}" style="display: inline-block; background: #1e40af; color: #fff; padding: 12px 32px; border-radius: 8px; text-decoration: none; font-weight: bold;">
          Anmelden
        </a>
      </p>
      <p style="color: #666; font-size: 14px;">
        Der Link ist 15 Minuten gültig.<br>
        Falls du keinen Login angefordert hast, ignoriere diese E-Mail.
      </p>
      <p style="color: #999; font-size: 12px; margin-top: 24px;">
        Direkter Link: #{url}
      </p>
    </div>
    """
  end
end
