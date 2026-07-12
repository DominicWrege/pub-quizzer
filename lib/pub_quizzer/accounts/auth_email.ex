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
    |> text_body("Login-Link: #{url}\nDer Link ist 10 Minuten gültig.")
    |> Mailer.deliver()
  end

  defp from_email do
    email = Application.get_env(:pub_quizzer, :mailer, [])[:from_email]
    {"Kneipenquiz", email}
  end

  defp html_body(url) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; color: #333;">
      <h2 style="font-size: 22px; margin-bottom: 8px;">🍺 Kneipenquiz</h2>
      <p style="font-size: 16px; line-height: 1.5;">
        Moin! Schön, dass du da bist!<br>
        Klicke auf den Link, um dich anzumelden:
      </p>
      <p style="margin: 28px 0;">
        <a href="#{url}" style="display: inline-block; background: #B8860B; color: #fff; padding: 14px 36px; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 16px;">
          Anmelden
        </a>
      </p>
      <p style="color: #666; font-size: 14px; line-height: 1.5;">
        Der Link ist 10 Minuten gültig.<br>
        Falls du keinen Login angefordert hast, ignoriere diese E-Mail einfach.
      </p>
      <hr style="border: none; border-top: 1px solid #e5e5e5; margin: 28px 0;">
      <p style="color: #999; font-size: 12px; margin: 0;">
        Direkter Link: #{url}
      </p>
    </div>
    """
  end
end
