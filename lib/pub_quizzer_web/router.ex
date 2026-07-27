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

  pipeline :moderator_auth do
    plug PubQuizzerWeb.AdminAuth, required_role: :moderator
  end

  scope "/", PubQuizzerWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Admin session (login/logout)
    get "/admin/login", AdminSessionController, :new
    post "/admin/login", AdminSessionController, :create
    get "/admin/logout", AdminSessionController, :delete

    # Magic link
    get "/admin/magic", MagicLinkController, :show

    # First-run setup
    live "/setup", SetupLive, :index

    # Team join (controller sets session cookie)
    post "/quiz/join", QuizJoinController, :join
    get "/quiz/join/:code", QuizJoinController, :join_with_code

    # Public quiz live session (team lobby only)
    live_session :team_quiz do
      live "/quiz/:code/lobby", QuizLive.TeamLobby, :index
    end
  end

  # Host lobby — requires moderator auth
  scope "/", PubQuizzerWeb do
    pipe_through [:browser, :moderator_auth]

    live_session :host,
      on_mount: [{PubQuizzerWeb.AdminAuth, :mount_current_scope}] do
      live "/quiz/:code/host", QuizLive.HostLobby, :index
    end
  end

  # Admin panel — requires authenticated user (moderator+)
  # All admin routes share one live_session so navigation between
  # pages stays in the same LiveView process (no layout flicker).
  # The superadmin-only /users route enforces its role in UserLive.
  scope "/admin", PubQuizzerWeb.Admin do
    pipe_through [:browser, :moderator_auth]

    live_session :admin,
      on_mount: [{PubQuizzerWeb.AdminAuth, :mount_current_scope}] do
      live "/topics", TopicLive, :index

      live "/topics/:topic_id/questions", QuestionLive, :index
      live "/topics/:topic_id/questions/new", QuestionLive, :new
      live "/topics/:topic_id/questions/:id/edit", QuestionLive, :edit

      live "/events", EventLive, :index
      live "/events/new", EventLive, :new
      live "/events/:id", EventLive, :show
      live "/events/:id/results", ResultLive, :index

      live "/profile", ProfileLive, :index

      live "/users", UserLive, :index
    end
  end

  if Application.compile_env(:pub_quizzer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev", PubQuizzerWeb do
      pipe_through :browser

      get "/login-as/:email", DevAuthController, :login_as
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PubQuizzerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Catch-all — silent 404 for unmatched routes (e.g. Chrome DevTools probes)
  scope "/", PubQuizzerWeb do
    pipe_through :browser
    get "/*path", PageController, :not_found
  end
end
