defmodule PubQuizzer.Repo.Migrations.RenameMagicLinkToLoginCode do
  use Ecto.Migration

  def change do
    drop index(:users, [:magic_link_token])

    rename table(:users), :magic_link_token, to: :login_code_hash
    rename table(:users), :magic_link_sent_at, to: :login_code_sent_at

    alter table(:users) do
      add :login_code_attempts, :integer, null: false, default: 0
    end

    create index(:users, [:login_code_hash])
  end
end
