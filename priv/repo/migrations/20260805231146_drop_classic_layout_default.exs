defmodule PubQuizzer.Repo.Migrations.DropClassicLayoutDefault do
  use Ecto.Migration

  def up do
    # "classic" layout is removed — existing values become "image_side" (which
    # renders as plain text when no images are present). New rows already use
    # "image_side" as their default via the schema-level default in
    # Question; exqlite does not support ALTER COLUMN ... SET DEFAULT, so we
    # only rewrite the existing rows here.
    execute "UPDATE questions SET layout = 'image_side' WHERE layout = 'classic'"
    execute "UPDATE question_versions SET layout = 'image_side' WHERE layout = 'classic'"
  end

  def down do
    # No-op: cannot reliably reverse the default with exqlite.
  end
end
