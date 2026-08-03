defmodule PubQuizzer.AccountsTest do
  use PubQuizzer.DataCase, async: true

  alias PubQuizzer.Accounts

  describe "list_users/0" do
    test "returns users ordered by name" do
      created_names = ["Zoe", "Anna", "Max"]

      for n <- created_names do
        Accounts.create_user!(%{
          email: "#{String.downcase(n)}@test",
          name: n,
          role: "moderator"
        })
      end

      returned = Enum.map(Accounts.list_users(), & &1.name)

      created_sorted = Enum.sort(created_names)

      indices =
        Enum.map(created_sorted, fn n ->
          Enum.find_index(returned, &(&1 == n))
        end)

      assert indices == Enum.sort(indices)
    end

    test "orders users with the same name by email" do
      Accounts.create_user!(%{email: "b@x", name: "Same", role: "moderator"})
      Accounts.create_user!(%{email: "a@x", name: "Same", role: "moderator"})

      sames =
        Accounts.list_users()
        |> Enum.filter(&(&1.name == "Same"))

      emails = Enum.map(sames, & &1.email)
      assert emails == Enum.sort(emails)
      assert Enum.at(emails, 0) == "a@x"
      assert Enum.at(emails, 1) == "b@x"
    end
  end
end
