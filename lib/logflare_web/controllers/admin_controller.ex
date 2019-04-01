defmodule LogflareWeb.AdminController do
  use LogflareWeb, :controller
  import Ecto.Query, only: [from: 2]

  alias Logflare.Repo
  alias Logflare.SourceData
  alias Logflare.TableBuffer

  def dashboard(conn, _params) do
    query =
      from(s in "sources",
        order_by: s.name,
        select: %{
          name: s.name,
          id: s.id,
          token: s.token
        }
      )

    sources =
      for source <- Repo.all(query) do
        {:ok, token} = Ecto.UUID.load(source.token)

        log_count = SourceData.get_log_count(source)
        rate = SourceData.get_rate(source)
        timestamp = SourceData.get_latest_date(source)
        average_rate = SourceData.get_avg_rate(source)
        max_rate = SourceData.get_max_rate(source)
        buffer_count = TableBuffer.get_count(token)

        Map.put(source, :log_count, log_count)
        |> Map.put(:rate, rate)
        |> Map.put(:token, token)
        |> Map.put(:latest, timestamp)
        |> Map.put(:avg, average_rate)
        |> Map.put(:max, max_rate)
        |> Map.put(:buffer, buffer_count)
      end

    sorted_sources = Enum.sort_by(sources, &Map.fetch(&1, :latest), &>=/2)

    render(conn, "dashboard.html", sources: sorted_sources)
  end
end
