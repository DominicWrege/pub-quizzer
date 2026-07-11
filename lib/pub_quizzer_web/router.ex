defmodule PubQuizzerWeb.Router do
  use PubQuizzerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PubQuizzerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin_auth do
    plug PubQuizzerWeb.AdminAuth
  end

  scope "/", PubQuizzerWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Admin session (login/logout)
    get "/admin/login", AdminSessionController, :new
    post "/admin/login", AdminSessionController, :create
    get "/admin/logout", AdminSessionController, :delete

    # Team join (controller sets session cookie)
    post "/quiz/join", QuizJoinController, :join
    get "/quiz/join/:code", QuizJoinController, :join_with_code

    live_session :quiz do
      live "/join", QuizLive.Join, :index
      live "/quiz/:code/lobby", QuizLive.TeamLobby, :index
      live "/quiz/:code/host", QuizLive.HostLobby, :index
    end
  end

  # Admin panel — requires session
  scope "/admin", PubQuizzerWeb.Admin do
    pipe_through [:browser, :admin_auth]

    live_session :admin,
      on_mount: [{PubQuizzerWeb.AdminAuth, :mount_current_scope}] do
      live "/topics", TopicLive, :index

      live "/topics/:topic_id/questions", QuestionLive, :index

      live "/events", EventLive, :index
      live "/events/new", EventLive, :new
      live "/events/:id", EventLive, :show
    end
  end

  if Application.compile_env(:pub_quizzer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PubQuizzerWeb.Telemetry
    end
  end

  # Catch-all — silent 404 for unmatched routes (e.g. Chrome DevTools probes)
  scope "/", PubQuizzerWeb do
    pipe_through :browser
    get "/*path", PageController, :not_found
  end
end
