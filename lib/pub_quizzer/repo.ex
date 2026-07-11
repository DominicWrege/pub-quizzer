defmodule PubQuizzer.Repo do
  use Ecto.Repo,
    otp_app: :pub_quizzer,
    adapter: Ecto.Adapters.SQLite3
end
