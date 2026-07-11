defmodule PubQuizzerWeb.ErrorJSONTest do
  use PubQuizzerWeb.ConnCase, async: true

  test "renders 404" do
    assert PubQuizzerWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert PubQuizzerWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
