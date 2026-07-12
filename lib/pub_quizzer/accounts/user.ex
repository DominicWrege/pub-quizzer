defmodule PubQuizzer.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, :string, default: "moderator"
    field :active, :boolean, default: false
    field :magic_link_token, :string
    field :magic_link_sent_at, :utc_datetime
    field :last_signed_in_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :role,
      :active,
      :magic_link_token,
      :magic_link_sent_at,
      :last_signed_in_at
    ])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, ["superadmin", "moderator"])
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
