defmodule PubQuizzer.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, :string, default: "moderator"
    field :active, :boolean, default: false
    field :login_code_hash, :string
    field :login_code_sent_at, :utc_datetime
    field :login_code_attempts, :integer, default: 0
    field :last_signed_in_at, :utc_datetime
    field :guide_seen, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :role,
      :active,
      :guide_seen,
      :login_code_hash,
      :login_code_sent_at,
      :login_code_attempts,
      :last_signed_in_at
    ])
    |> validate_required([:email, :name, :role])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, ["superadmin", "moderator"])
    |> normalize_email()
    |> unique_constraint(:email)
  end

  # Restricted changesets for user-driven edits. The full changeset above casts
  # :role and :active (needed for setup/invite/programmatic updates); exposing
  # those to form params would let a client set its own role. These only accept
  # the fields the corresponding UI actually edits.

  @doc "Changeset for a user editing their own profile (name only)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end

  @doc "Changeset for a superadmin editing another user's name/email."
  def admin_edit_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> normalize_email()
    |> unique_constraint(:email)
  end

  defp normalize_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email, String.downcase(email))
    end
  end
end
