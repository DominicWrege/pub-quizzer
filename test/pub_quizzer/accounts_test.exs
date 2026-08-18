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

  describe "login codes" do
    setup do
      user =
        Accounts.create_user!(%{email: "coder@test", name: "Coder", role: "moderator"})

      %{user: user}
    end

    test "generate_login_code/1 returns a 6-char code from the safe alphabet", %{user: user} do
      assert {:ok, code, returned_user} = Accounts.generate_login_code(user.email)
      assert returned_user.id == user.id
      assert String.length(code) == 6
      assert code =~ ~r/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/
    end

    test "generate_login_code/1 returns :not_found for unknown email" do
      assert {:error, :not_found} = Accounts.generate_login_code("ghost@test")
    end

    test "verify_login_code/2 succeeds with the right code and clears it", %{user: user} do
      {:ok, code} = Accounts.generate_login_code_for(user)

      assert {:ok, verified} = Accounts.verify_login_code(user.email, code)
      assert verified.id == user.id

      reloaded = Accounts.get_user!(user.id)
      assert is_nil(reloaded.login_code_hash)
      assert is_nil(reloaded.login_code_sent_at)
      assert reloaded.login_code_attempts == 0
    end

    test "verify_login_code/2 is case-insensitive and trims whitespace", %{user: user} do
      {:ok, code} = Accounts.generate_login_code_for(user)
      assert {:ok, _} = Accounts.verify_login_code(user.email, "  #{String.downcase(code)}  ")
    end

    test "verify_login_code/2 rejects a wrong code and counts the attempt", %{user: user} do
      {:ok, _code} = Accounts.generate_login_code_for(user)

      assert {:error, :invalid} = Accounts.verify_login_code(user.email, "ZZZZZZ")
      assert Accounts.get_user!(user.id).login_code_attempts == 1
    end

    test "verify_login_code/2 rejects an unknown email" do
      assert {:error, :invalid} = Accounts.verify_login_code("ghost@test", "ABC123")
    end

    test "verify_login_code/2 rejects an expired code", %{user: user} do
      {:ok, code} = Accounts.generate_login_code_for(user)

      eleven_min_ago =
        DateTime.utc_now()
        |> DateTime.add(-11, :minute)
        |> DateTime.truncate(:second)

      {:ok, _} =
        user
        |> Ecto.Changeset.change(%{login_code_sent_at: eleven_min_ago})
        |> PubQuizzer.Repo.update()

      assert {:error, :expired} = Accounts.verify_login_code(user.email, code)
    end

    test "verify_login_code/2 locks out after 5 failed attempts", %{user: user} do
      {:ok, code} = Accounts.generate_login_code_for(user)

      for _ <- 1..5 do
        assert {:error, :invalid} = Accounts.verify_login_code(user.email, "ZZZZZZ")
      end

      assert {:error, :too_many_attempts} = Accounts.verify_login_code(user.email, code)
    end

    test "generating a new code resets attempts and replaces the old code", %{user: user} do
      {:ok, old_code} = Accounts.generate_login_code_for(user)
      assert {:error, :invalid} = Accounts.verify_login_code(user.email, "ZZZZZZ")
      assert Accounts.get_user!(user.id).login_code_attempts == 1

      {:ok, new_code} = Accounts.generate_login_code_for(user)
      assert Accounts.get_user!(user.id).login_code_attempts == 0

      assert {:error, :invalid} = Accounts.verify_login_code(user.email, old_code)
      assert {:ok, _} = Accounts.verify_login_code(user.email, new_code)
    end
  end
end
