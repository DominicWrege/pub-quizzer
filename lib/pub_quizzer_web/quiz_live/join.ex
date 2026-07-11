defmodule PubQuizzerWeb.QuizLive.Join do
  use PubQuizzerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(%{"code" => ""}))}
  end

  @impl true
  def handle_event("validate", %{"code" => code}, socket) do
    {:noreply, assign(socket, :form, to_form(%{"code" => code}))}
  end
end
