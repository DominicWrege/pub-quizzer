defmodule PubQuizzer.Names do
  @moduledoc """
  Generates default team names: "Team 1", "Team 2", ... "Team N".
  Hosts can rename teams before the quiz starts.
  """

  @doc """
  Generate a team name based on how many already exist.
  """
  def generate(existing \\ MapSet.new()) do
    n = MapSet.size(existing) + 1
    "Team #{n}"
  end

  @doc """
  Generate N sequential team names: "Team 1" through "Team N".
  """
  def generate_many(n) do
    Enum.map(1..n, fn i -> "Team #{i}" end)
  end
end
