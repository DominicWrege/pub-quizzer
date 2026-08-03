defmodule PubQuizzer.AccountsTest do
  use PubQuizzer.DataCase, async: true

  import Swoosh.TestAssertions

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

  describe "sign_in_user/1" do
    test "activates the user and stamps last_signed_in_at" do
      user =
        Accounts.create_user!(%{
          email: "fresh@test",
          name: "Fresh",
          role: "moderator",
          active: false
        })

      assert {:ok, updated} = Accounts.sign_in_user(user)
      assert updated.active
      refute is_nil(updated.last_signed_in_at)
    end

    test "notifies superadmins on a moderator's first login" do
      admin = Accounts.create_user!(%{email: "admin@test", name: "Ada", role: "superadmin"})
      moderator = Accounts.create_user!(%{email: "mod@test", name: "Mira", role: "moderator"})

      assert {:ok, _} = Accounts.sign_in_user(moderator)
      await_notice_tasks()

      assert_email_sent(to: [{admin.name, admin.email}])
    end

    test "sends no notice once the moderator has signed in before" do
      Accounts.create_user!(%{email: "admin@test", name: "Ada", role: "superadmin"})
      moderator = Accounts.create_user!(%{email: "mod@test", name: "Mira", role: "moderator"})

      assert {:ok, moderator} = Accounts.sign_in_user(moderator)
      await_notice_tasks()
      assert_email_sent()

      assert {:ok, _} = Accounts.sign_in_user(moderator)
      await_notice_tasks()
      refute_email_sent()
    end

    test "sends no notice on a superadmin's first login" do
      superadmin =
        Accounts.create_user!(%{email: "admin@test", name: "Ada", role: "superadmin"})

      assert {:ok, _} = Accounts.sign_in_user(superadmin)
      await_notice_tasks()
      refute_email_sent()
    end

    defp await_notice_tasks do
      PubQuizzer.TaskSupervisor
      |> Task.Supervisor.children()
      |> Enum.each(fn pid ->
        ref = Process.monitor(pid)

        assert_receive {:DOWN, ^ref, :process, ^pid, reason}
        assert reason in [:normal, :noproc]
      end)
    end
  end
end
