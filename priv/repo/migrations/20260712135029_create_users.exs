defmodule PubQuizzer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :role, :string, null: false, default: "moderator"
      add :active, :boolean, null: false, default: true
      add :magic_link_token, :string
      add :magic_link_sent_at, :utc_datetime
      add :last_signed_in_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:magic_link_token])
  end
end
