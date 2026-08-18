defmodule PubQuizzer.Accounts do
  @moduledoc """
  The Accounts context for managing users (superadmins and moderators)
  with one-time login code authentication.
  """

  import Ecto.Query
  require Logger
  alias PubQuizzer.Accounts.{User, AuthEmail}
  alias PubQuizzer.Repo

  @login_code_expiry_minutes 10
  @login_code_length 6
  @max_login_code_attempts 5
  # Unambiguous alphabet: no 0/O, 1/I/L to avoid transcription errors.
  @code_alphabet String.codepoints("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

  # --- Queries ---

  def list_users do
    User
    |> order_by(asc: :name, asc: :email)
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

  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def update_user_by_admin(%User{} = user, attrs) do
    user
    |> User.admin_edit_changeset(attrs)
    |> Repo.update()
  end

  def change_user(%User{} = user) do
    User.changeset(user, %{})
  end

  # --- Login codes ---

  @doc """
  Generates a one-time login code for the user with the given email.
  Returns the raw (unhashed) code so it can be delivered out-of-band.
  """
  def generate_login_code(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, code} = do_generate_login_code(user)
        {:ok, code, user}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Generates a one-time login code for an already-loaded user (invites, setup)."
  def generate_login_code_for(%User{} = user) do
    do_generate_login_code(user)
  end

  defp do_generate_login_code(%User{id: id}) do
    # Re-fetch so the changeset diffs against fresh DB state (a stale struct
    # could otherwise make cast/2 skip the attempts reset).
    user = Repo.get!(User, id)
    code = generate_code()
    code_hash = hash_code(code)

    {:ok, _} =
      user
      |> User.changeset(%{
        login_code_hash: code_hash,
        login_code_sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
        login_code_attempts: 0
      })
      |> Repo.update()

    {:ok, code}
  end

  @doc """
  Verifies a login code for the given email. On success the code is cleared and
  the (updated) user returned. Wrong codes increment an attempt counter; after
  #{@max_login_code_attempts} failures the code is invalidated.
  """
  def verify_login_code(email, code) when is_binary(email) and is_binary(code) do
    normalized = normalize_code(code)

    case get_user_by_email(email) do
      %User{login_code_hash: hash, login_code_sent_at: sent_at} = user
      when not is_nil(hash) and not is_nil(sent_at) ->
        cond do
          not within_expiry?(sent_at) ->
            {:ok, _} = clear_login_code(user)
            {:error, :expired}

          user.login_code_attempts >= @max_login_code_attempts ->
            {:ok, _} = clear_login_code(user)
            {:error, :too_many_attempts}

          hash_code(normalized) == hash ->
            {:ok, updated} = clear_login_code(user)
            {:ok, updated}

          true ->
            {:ok, _} = record_failed_attempt(user)
            {:error, :invalid}
        end

      _ ->
        {:error, :invalid}
    end
  end

  def verify_login_code(_, _), do: {:error, :invalid}

  defp clear_login_code(%User{} = user) do
    user
    |> User.changeset(%{login_code_hash: nil, login_code_sent_at: nil, login_code_attempts: 0})
    |> Repo.update()
  end

  defp record_failed_attempt(%User{} = user) do
    user
    |> User.changeset(%{login_code_attempts: user.login_code_attempts + 1})
    |> Repo.update()
  end

  defp within_expiry?(sent_at) do
    diff = DateTime.diff(DateTime.utc_now(), sent_at, :second)
    diff < @login_code_expiry_minutes * 60
  end

  defp normalize_code(code) do
    code |> String.trim() |> String.upcase()
  end

  defp generate_code do
    alphabet_size = length(@code_alphabet)

    for _ <- 1..@login_code_length, into: "" do
      Enum.at(@code_alphabet, random_index(alphabet_size))
    end
  end

  # Rejection sampling over crypto-random bytes to avoid modulo bias.
  defp random_index(size) do
    limit = 256 - rem(256, size)
    <<byte, _rest::binary>> = :crypto.strong_rand_bytes(1)

    if byte < limit do
      rem(byte, size)
    else
      random_index(size)
    end
  end

  defp hash_code(code) do
    :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
  end

  # --- Auth helpers ---

  def sign_in_user(%User{} = user) do
    first_login? = is_nil(user.last_signed_in_at)

    result =
      user
      |> User.changeset(%{
        active: true,
        last_signed_in_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    if first_login? and user.role == "moderator" do
      with {:ok, updated} <- result do
        notify_admins_of_first_moderator_login(updated)
      end
    end

    result
  end

  def list_superadmins do
    Repo.all(from u in User, where: u.role == "superadmin")
  end

  defp notify_admins_of_first_moderator_login(%User{} = moderator) do
    admins = list_superadmins()

    if admins != [] do
      Task.Supervisor.start_child(PubQuizzer.TaskSupervisor, fn ->
        case AuthEmail.deliver_first_login_notice(moderator, admins) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to deliver first-login notice for #{moderator.email}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
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

  @doc """
  Generates a login code for the given email and delivers it asynchronously.
  Returns `{:ok, code}` (the raw code, for dev/test visibility) or
  `{:error, :not_found}` if no user matches.
  """
  def deliver_login_code(email) do
    case generate_login_code(email) do
      {:ok, code, user} ->
        deliver_code_async(user, code, email)
        {:ok, code}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp deliver_code_async(user, code, email) do
    Task.Supervisor.start_child(PubQuizzer.TaskSupervisor, fn ->
      case AuthEmail.deliver_login_code(user, code) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to deliver login code to #{email}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Generates a login code for an invited/created user and emails it to them.
  """
  def deliver_invite_code(%User{} = user) do
    {:ok, code} = generate_login_code_for(user)

    case AuthEmail.deliver_invite_code(user, code) do
      {:ok, _} ->
        {:ok, code}

      {:error, reason} ->
        Logger.error("Failed to deliver invite code to #{user.email}: #{inspect(reason)}")
        {:error, :delivery_failed}
    end
  end
end
