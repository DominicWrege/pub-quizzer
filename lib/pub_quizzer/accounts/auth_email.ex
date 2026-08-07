defmodule PubQuizzer.Accounts.AuthEmail do
  @moduledoc """
  Email composition and delivery for authentication (magic links)
  and account notifications (first moderator login).
  """

  import Swoosh.Email

  alias PubQuizzer.Accounts.User
  alias PubQuizzer.Mailer

  def deliver_magic_link(%User{} = user, url) do
    {name, email} = from_email()

    new()
    |> to({user.name, user.email})
    |> from({name, email})
    |> subject("Dein Quiz for a better life Login-Link")
    |> html_body(rendered_html(user.name, url))
    |> text_body(plain_text(user.name, url))
    |> Mailer.deliver()
  end

  def deliver_first_login_notice(%User{} = moderator, admins) do
    {name, email} = from_email()

    new()
    |> to(Enum.map(admins, &{&1.name, &1.email}))
    |> from({name, email})
    |> subject("#{moderator.name} hat sich zum ersten Mal angemeldet")
    |> html_body(notice_html(moderator))
    |> text_body(notice_text(moderator))
    |> Mailer.deliver()
  end

  defp from_email do
    email =
      Application.get_env(:pub_quizzer, :mailer, [])[:from_email]
      |> String.trim()

    {"Quiz for a better life", email}
  end

  defp rendered_html(name, url) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; color: #333;">
      <h2 style="font-size: 22px; margin-bottom: 8px;">🏆 Quiz for a better life</h2>
      <p style="font-size: 16px; line-height: 1.5;">
        Moin #{esc(name)}! Schön, dass du da bist!<br>
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

  defp notice_html(%User{} = moderator) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; color: #333;">
      <h2 style="font-size: 22px; margin-bottom: 8px;">🏆 Quiz for a better life</h2>
      <p style="font-size: 16px; line-height: 1.5;">
        Moin!<br>
        <strong>#{esc(moderator.name)}</strong> (#{esc(moderator.email)}) hat sich soeben
        zum ersten Mal als Moderator angemeldet.
      </p>
      <p style="color: #666; font-size: 14px; line-height: 1.5;">
        Diese Benachrichtigung geht an alle Administrator:innen,
        damit neue Moderatoren willkommen geheißen werden können.
      </p>
    </div>
    """
  end

  # The HTML email bodies are built by string concatenation (no auto-escaping),
  # and name/email are user-controlled — escape them there. The URL is trusted
  # (crypto-safe token + configured host) so it's left as-is.
  defp esc(string) when is_binary(string) do
    string
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp notice_text(%User{} = moderator) do
    "Moin!\n\n#{moderator.name} (#{moderator.email}) hat sich soeben zum ersten Mal als Moderator angemeldet."
  end
end
