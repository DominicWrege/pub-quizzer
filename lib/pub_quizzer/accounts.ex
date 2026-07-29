defmodule PubQuizzer.Accounts do
  @moduledoc """
  The Accounts context for managing users (superadmins and moderators)
  with magic link authentication.
  """

  import Ecto.Query
  require Logger
  alias PubQuizzer.Accounts.{User, AuthEmail}
  alias PubQuizzer.Repo

  @magic_link_expiry_minutes 10

  # --- Queries ---

  def list_users do
    User
    |> order_by(asc: :email)
    |> Repo.all()
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def has_users? do
    Repo.exists?(User)
  end

  # --- CRUD ---

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def create_user!(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def toggle_active(%User{} = user) do
    user
    |> User.changeset(%{active: !user.active})
    |> Repo.update()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def change_user(%User{} = user) do
    User.changeset(user, %{})
  end

  # --- Magic Link ---

  def generate_magic_link(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, raw_token} = do_generate_magic_link(user)
        {:ok, raw_token, user}

      nil ->
        {:error, :not_found}
    end
  end

  def generate_invite_link(%User{} = user) do
    do_generate_magic_link(user)
  end

  defp do_generate_magic_link(user) do
    raw_token = generate_token()
    token_hash = hash_token(raw_token)

    {:ok, _} =
      user
      |> User.changeset(%{
        magic_link_token: token_hash,
        magic_link_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    {:ok, raw_token}
  end

  def verify_magic_link(raw_token) when is_binary(raw_token) do
    token_hash = hash_token(raw_token)

    case Repo.get_by(User, magic_link_token: token_hash) do
      %User{magic_link_sent_at: sent_at} = user
      when not is_nil(sent_at) ->
        if within_expiry?(sent_at) do
          {:ok, updated} = clear_magic_link(user)

          {:ok, updated}
        else
          {:ok, _} = clear_magic_link(user)
          {:error, :expired}
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp clear_magic_link(%User{} = user) do
    user
    |> User.changeset(%{magic_link_token: nil, magic_link_sent_at: nil})
    |> Repo.update()
  end

  defp within_expiry?(sent_at) do
    diff = DateTime.diff(DateTime.utc_now(), sent_at, :second)
    diff < @magic_link_expiry_minutes * 60
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  # --- Auth helpers ---

  def sign_in_user(%User{} = user) do
    user
    |> User.changeset(%{
      active: true,
      last_signed_in_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def mark_guide_seen(%User{} = user) do
    user
    |> User.changeset(%{guide_seen: true})
    |> Repo.update()
  end

  def reset_guide_seen(%User{} = user) do
    user
    |> User.changeset(%{guide_seen: false})
    |> Repo.update!()
  end

  def can_manage_users?(%User{role: "superadmin"}), do: true
  def can_manage_users?(_), do: false

  # --- Email delivery ---

  def deliver_magic_link(email, base_url) do
    case generate_magic_link(email) do
      {:ok, raw_token, user} ->
        url = "#{base_url}/admin/magic?token=#{raw_token}"

        case AuthEmail.deliver_magic_link(user, url) do
          {:ok, _} ->
            {:ok, url}

          {:error, reason} ->
            Logger.error("Failed to deliver magic link to #{email}: #{inspect(reason)}")
            {:error, :delivery_failed}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def deliver_invite_link(%User{} = user, base_url) do
    {:ok, raw_token} = generate_invite_link(user)
    url = "#{base_url}/admin/magic?token=#{raw_token}"

    case AuthEmail.deliver_magic_link(user, url) do
      {:ok, _} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to deliver invite link to #{user.email}: #{inspect(reason)}")
        {:error, :delivery_failed}
    end
  end
end
