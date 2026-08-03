defmodule PubQuizzer.Repo.Migrations.RenumberQuestionPositions do
  use Ecto.Migration

  def up do
    execute """
    UPDATE questions AS q
    SET position = numbered.new_position
    FROM (
      SELECT id,
             ROW_NUMBER() OVER (PARTITION BY topic_id ORDER BY position, id) - 1 AS new_position
      FROM questions
    ) AS numbered
    WHERE q.id = numbered.id
    """
  end

  def down do
    execute "UPDATE questions SET position = 0"
  end
end
