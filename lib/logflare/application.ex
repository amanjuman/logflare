defmodule Logflare.Application do
  @moduledoc false
  use Application
  alias Logflare.{Users, Sources, Tracker, Logs, BillingAccounts, Plans, PubSubRates}

  def start(_type, _args) do
    import Supervisor.Spec

    # TODO: Set node status in GCP when sigterm is received
    :ok =
      :gen_event.swap_sup_handler(
        :erl_signal_server,
        {:erl_signal_handler, []},
        {Logflare.SigtermHandler, []}
      )

    tracker_pool_size = Application.get_env(:logflare, Logflare.Tracker)[:pool_size]

    children = [
      Users.Cache,
      Sources.Cache,
      BillingAccounts.Cache,
      Plans.Cache,
      PubSubRates.Cache,
      Logs.LogEvents.Cache,
      Logs.RejectedLogEvents,
      {Phoenix.PubSub, name: Logflare.PubSub},
      worker(
        Tracker,
        [
          [
            name: Tracker,
            pubsub_server: Logflare.PubSub,
            broadcast_period: 1_000,
            down_period: 5_000,
            permdown_period: 30_000,
            pool_size: tracker_pool_size,
            log_level: false
          ]
        ]
      ),
      supervisor(Logflare.Repo, []),
      supervisor(LogflareWeb.Endpoint, []),
      {Task.Supervisor, name: Logflare.TaskSupervisor}
    ]

    topologies = Application.get_env(:libcluster, :topologies)

    dev_prod_children = [
      {Task.Supervisor, name: Logflare.TaskSupervisor},
      {Cluster.Supervisor, [topologies, [name: Logflare.ClusterSupervisor]]},
      supervisor(Logflare.Repo, []),
      {Phoenix.PubSub, name: Logflare.PubSub},
      {
        Logflare.Tracker,
        [
          name: Logflare.Tracker,
          pubsub_server: Logflare.PubSub,
          broadcast_period: 250,
          down_period: 5_000,
          permdown_period: 30_000,
          pool_size: tracker_pool_size,
          log_level: false
        ]
      },
      # supervisor(LogflareTelemetry.Supervisor, []),
      Users.Cache,
      Sources.Cache,
      BillingAccounts.Cache,
      Plans.Cache,
      PubSubRates.Cache,
      Logs.LogEvents.Cache,
      Sources.Buffers,
      Sources.BuffersCache,
      Logs.RejectedLogEvents,
      # init Counters before Manager as Manager calls Counters through table create
      supervisor(Sources.Counters, []),
      supervisor(Sources.RateCounters, []),
      supervisor(Logflare.PubSubRates, []),
      supervisor(Logflare.Source.Supervisor, []),
      supervisor(Logflare.SystemMetricsSup, []),
      supervisor(LogflareWeb.Endpoint, [])
    ]

    env = Application.get_env(:logflare, :env)

    children =
      if env == :test do
        children
      else
        dev_prod_children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Logflare.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    LogflareWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
