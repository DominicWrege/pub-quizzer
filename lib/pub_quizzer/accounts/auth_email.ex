defmodule PubQuizzer.Accounts.AuthEmail do
  @moduledoc """
  Email composition and delivery for authentication (magic links).
  """

  import Swoosh.Email

  alias PubQuizzer.Accounts.User
  alias PubQuizzer.Mailer

  def deliver_magic_link(%User{} = user, url) do
    new()
    |> to({user.name, user.email})
    |> from(from_email())
    |> subject("Dein Quiz for a better life Login-Link")
    |> html_body(rendered_html(user.name, url))
    |> text_body(plain_text(user.name, url))
    |> Mailer.deliver()
  end

  defp from_email do
    Application.get_env(:pub_quizzer, :mailer, [])[:from_email]
    |> String.trim()
  end

  defp rendered_html(name, url) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; color: #333;">
      <h2 style="font-size: 22px; margin-bottom: 8px;">🏆 Quiz for a better life</h2>
      <p style="font-size: 16px; line-height: 1.5;">
        Moin #{name}! Schön, dass du da bist!<br>
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

  defp plain_text(name, url) do
    "Moin #{name}!\n\nLogin-Link: #{url}\nDer Link ist 10 Minuten gültig."
  end
end
