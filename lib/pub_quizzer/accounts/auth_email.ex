defmodule PubQuizzer.Accounts.AuthEmail do
  @moduledoc """
  Email composition and delivery for authentication (one-time login codes)
  and account notifications (first moderator login).
  """

  import Swoosh.Email

  alias PubQuizzer.Accounts.User
  alias PubQuizzer.Mailer

  def deliver_login_code(%User{} = user, code) do
    {name, email} = from_email()

    new()
    |> to({user.name, user.email})
    |> from({name, email})
    |> subject("Dein Quiz for a better life Login-Code")
    |> html_body(code_html(user.name, code, "deinen Login"))
    |> text_body(code_text(user.name, code))
    |> Mailer.deliver()
  end

  def deliver_invite_code(%User{} = user, code) do
    {name, email} = from_email()

    new()
    |> to({user.name, user.email})
    |> from({name, email})
    |> subject("Deine Einladung zu Quiz for a better life")
    |> html_body(code_html(user.name, code, "deine Anmeldung"))
    |> text_body(code_text(user.name, code))
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

  defp code_html(name, code, context) do
    """
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; color: #333;">
      <h2 style="font-size: 22px; margin-bottom: 8px;">🏆 Quiz for a better life</h2>
      <p style="font-size: 16px; line-height: 1.5;">
        Moin #{esc(name)}! Schön, dass du da bist!<br>
        Hier ist der Code für #{esc(context)}:
      </p>
      <p style="margin: 28px 0; text-align: center;">
        <span style="display: inline-block; background: #f5f0e6; color: #333; padding: 16px 28px; border-radius: 8px; font-family: monospace; font-weight: bold; font-size: 32px; letter-spacing: 10px;">
          #{esc(code)}
        </span>
      </p>
      <p style="color: #666; font-size: 14px; line-height: 1.5;">
        Gib diesen Code auf der Login-Seite ein.<br>
        Der Code ist 10 Minuten gültig und kann nur einmal verwendet werden.<br>
        Falls du keinen Login angefordert hast, ignoriere diese E-Mail einfach.
      </p>
    </div>
    """
  end

  defp code_text(name, code) do
    "Moin #{name}!\n\nDein Login-Code: #{code}\nDer Code ist 10 Minuten gültig und kann nur einmal verwendet werden."
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
