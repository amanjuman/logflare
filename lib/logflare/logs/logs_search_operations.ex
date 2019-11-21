defmodule Logflare.Logs.SearchOperations do
  @moduledoc false
  alias Logflare.Google.BigQuery.{GenUtils, SchemaUtils}
  alias Logflare.{Source, Sources, EctoQueryBQ}
  alias Logflare.Logs.Search.Parser
  alias Logflare.Logs.Search.Utils
  import Ecto.Query

  alias GoogleApi.BigQuery.V2.Api
  alias GoogleApi.BigQuery.V2.Model.QueryRequest

  use Logflare.GenDecorators
  @decorate_all pass_through_on_error_field()

  @default_limit 100
  @default_processed_bytes_limit 10_000_000_000

  # Note that this is only a timeout for the request, not the query.
  # If the query takes longer to run than the timeout value, the call returns without any results and with the 'jobComplete' flag set to false.
  @query_request_timeout 60_000

  defmodule SearchOperation do
    @moduledoc """
    Logs search options and result
    """
    use TypedStruct

    typedstruct do
      field :source, Source.t()
      field :querystring, String.t()
      field :query, Ecto.Query.t()
      field :query_result, term()
      field :sql_params, {term(), term()}
      field :tailing?, boolean
      field :tailing_initial?, boolean
      field :rows, [map()], default: []
      field :pathvalops, [map()]
      field :chart, map(), default: nil
      field :error, term()
      field :stats, :map
      field :use_local_time, boolean
      field :user_local_timezone, :string
      field :search_chart_period, atom()
      field :search_chart_aggregate, atom(), default: :avg
      field :timestamp_truncator, term()
    end
  end

  alias SearchOperation, as: SO

  def do_query(%SO{} = so) do
    %SO{source: %Source{token: source_id}} = so
    project_id = GenUtils.get_project_id(source_id)
    conn = GenUtils.get_conn()

    {sql, params} = so.sql_params

    query_request = %QueryRequest{
      query: sql,
      useLegacySql: false,
      useQueryCache: true,
      parameterMode: "POSITIONAL",
      queryParameters: params,
      dryRun: false,
      timeoutMs: @query_request_timeout
    }

    dry_run = %{query_request | dryRun: true}

    result =
      Api.Jobs.bigquery_jobs_query(
        conn,
        project_id,
        body: dry_run
      )

    with {:ok, response} <- result,
         is_within_limit? =
           String.to_integer(response.totalBytesProcessed) <= @default_processed_bytes_limit,
         {:total_bytes_processed, true} <- {:total_bytes_processed, is_within_limit?} do
      Api.Jobs.bigquery_jobs_query(
        conn,
        project_id,
        body: query_request
      )
    else
      {:total_bytes_processed, false} ->
        {:error,
         "Query halted: total bytes processed for this query is expected to be larger than #{
           div(@default_processed_bytes_limit, 1_000_000_000)
         } GB"}

      errtup ->
        errtup
    end
    |> Utils.put_result_in(so, :query_result)
    |> prepare_query_result()
  end

  def prepare_query_result(%SO{} = so) do
    query_result =
      so.query_result
      |> Map.update(:totalBytesProcessed, 0, &Utils.maybe_string_to_integer/1)
      |> Map.update(:totalRows, 0, &Utils.maybe_string_to_integer/1)
      |> AtomicMap.convert(%{safe: false})

    %{so | query_result: query_result}
  end

  def order_by_default(%SO{} = so) do
    %{so | query: order_by(so.query, desc: :timestamp)}
  end

  def apply_limit_to_query(%SO{} = so) do
    %{so | query: limit(so.query, @default_limit)}
  end

  def put_stats(%SO{} = so) do
    stats =
      so.stats
      |> Map.merge(%{
        total_rows: so.query_result.total_rows,
        total_bytes_processed: so.query_result.total_bytes_processed
      })
      |> Map.put(
        :total_duration,
        System.monotonic_time(:millisecond) - so.stats.start_monotonic_time
      )

    %{so | stats: stats}
  end

  def process_query_result(%SO{} = so) do
    %{schema: schema, rows: rows} = so.query_result
    rows = SchemaUtils.merge_rows_with_schema(schema, rows)
    %{so | rows: rows}
  end

  def default_from(%SO{} = so) do
    %{so | query: from(so.source.bq_table_id)}
  end

  def apply_to_sql(%SO{} = so) do
    %{so | sql_params: EctoQueryBQ.SQL.to_sql(so.query)}
  end

  def apply_wheres(%SO{} = so) do
    %{so | query: EctoQueryBQ.where_nesteds(so.query, so.pathvalops)}
  end

  def parse_querystring(%SO{} = so) do
    schema =
      so.source
      |> Sources.Cache.get_bq_schema()

    with {:ok, %{search: search, chart: chart}} <- Parser.parse(so.querystring, schema) do
      so = Utils.put_result_in({:ok, search}, so, :pathvalops)
      Utils.put_result_in({:ok, chart}, so, :chart)
    else
      err ->
        Utils.put_result_in(err, so, :pathvalops)
    end
  end

  def partition_or_streaming(%SO{tailing?: true, tailing_initial?: true} = so) do
    query =
      where(
        so.query,
        [log],
        fragment(
          "TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 24 HOUR) > CURRENT_TIMESTAMP() OR _PARTITIONTIME IS NULL"
        )
      )

    so
    |> Map.put(:query, query)
    |> drop_timestamp_pathvalops
  end

  def partition_or_streaming(%SO{tailing?: true} = so) do
    so
    |> Map.update!(
      :query,
      &where(&1, [l], fragment("_PARTITIONTIME IS NULL"))
    )
    |> drop_timestamp_pathvalops
  end

  def partition_or_streaming(%SO{} = so), do: so

  def drop_timestamp_pathvalops(%SO{} = so) do
    %{so | pathvalops: Enum.reject(so.pathvalops, &(&1.path === "timestamp"))}
  end

  def verify_path_in_schema(%SO{} = so) do
    flatmap =
      so.source
      |> Sources.Cache.get_bq_schema()
      |> Logflare.Logs.Validators.BigQuerySchemaChange.to_typemap()
      |> Iteraptor.to_flatmap()
      |> Enum.map(fn {k, v} -> {String.replace(k, ".fields", ""), v} end)
      |> Enum.map(fn {k, _} -> String.trim_trailing(k, ".t") end)

    result =
      Enum.reduce_while(so.pathvalops, :ok, fn %{path: path}, _ ->
        if path in flatmap do
          {:cont, :ok}
        else
          {:halt, {:error, "#{path} not present in source schema"}}
        end
      end)

    Utils.put_result_in(result, so)
  end

  def apply_local_timestamp_correction(%SO{} = so) do
    pathvalops =
      Enum.map(so.pathvalops, fn
        %{path: "timestamp", value: value} = pvo ->
          if so.user_local_timezone do
            value =
              value
              |> Timex.to_datetime(so.user_local_timezone)
              |> Timex.Timezone.convert("Etc/UTC")
              |> Timex.to_naive_datetime()

            %{pvo | value: value}
          end

        pvo ->
          pvo
      end)

    %{so | pathvalops: pathvalops}
  end

  def apply_select_all_schema(%SO{} = so) do
    top_level_fields =
      so.source
      |> Sources.Cache.get_bq_schema()
      |> Logflare.Logs.Validators.BigQuerySchemaChange.to_typemap()
      |> Map.keys()

    %{so | query: select(so.query, ^top_level_fields)}
  end

  def apply_select_timestamp(%SO{} = so) do
    query =
      case so.search_chart_period do
        :day ->
          select(so.query, [t, ...], %{
            timestamp: fragment("TIMESTAMP_TRUNC(?, DAY)", t.timestamp)
          })

        :hour ->
          select(so.query, [t, ...], %{
            timestamp: fragment("TIMESTAMP_TRUNC(?, HOUR)", t.timestamp)
          })

        :minute ->
          select(so.query, [t, ...], %{
            timestamp: fragment("TIMESTAMP_TRUNC(?, MINUTE)", t.timestamp)
          })

        :second ->
          select(so.query, [t, ...], %{
            timestamp: fragment("TIMESTAMP_TRUNC(?, SECOND)", t.timestamp)
          })
      end

    %{so | query: query}
  end

  def apply_group_by_timestamp_period(%SO{} = so) do
    truncator = timestamp_truncator(so)

    group_by = [
      truncator
    ]

    query = group_by(so.query, ^group_by)
    %{so | query: query}
  end

  def exclude_limit(%SO{} = so) do
    %{so | query: Ecto.Query.exclude(so.query, :limit)}
  end

  def add_to_query(%SO{} = so) do
    %{so | query: Ecto.Query.exclude(so.query, :limit)}
  end

  defp timestamp_truncator(%SO{} = so) do
    case so.search_chart_period do
      :day -> dynamic([t], fragment("TIMESTAMP_TRUNC(?, DAY)", t.timestamp))
      :hour -> dynamic([t], fragment("TIMESTAMP_TRUNC(?, HOUR)", t.timestamp))
      :minute -> dynamic([t], fragment("TIMESTAMP_TRUNC(?, MINUTE)", t.timestamp))
      :second -> dynamic([t], fragment("TIMESTAMP_TRUNC(?, SECOND)", t.timestamp))
    end
  end

  def apply_numeric_aggs(%SO{chart: chart = %{value: chart_value}} = so)
      when chart_value in [:integer, :float] do
    query =
      case so.search_chart_period do
        :day ->
          so.query
          |> where(
            [t, ...],
            fragment("TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 30 DAY) > CURRENT_TIMESTAMP()")
          )
          |> limit(30)

        :hour ->
          so.query
          |> where(
            [t, ...],
            fragment("TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 168 HOUR) > CURRENT_TIMESTAMP()")
          )
          |> limit(168)

        :minute ->
          so.query
          |> where(
            [t, ...],
            fragment("TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 120 HOUR) > CURRENT_TIMESTAMP()")
          )
          |> limit(120)

        :second ->
          so.query
          |> where(
            [t, ...],
            fragment("TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 180 SECOND) > CURRENT_TIMESTAMP()")
          )
          |> limit(180)
      end

    query = EctoQueryBQ.join_nested(query, chart)

    last_chart_field =
      so.chart.path
      |> String.split(".")
      |> List.last()
      |> String.to_existing_atom()

    query =
      case so.search_chart_aggregate do
        :sum -> select_merge(query, [..., l], %{value: sum(field(l, ^last_chart_field))})
        :avg -> select_merge(query, [..., l], %{value: avg(field(l, ^last_chart_field))})
        :count -> select_merge(query, [..., l], %{value: count(field(l, ^last_chart_field))})
      end

    query = order_by(query, [t, ...], desc: 1)
    %{so | query: query}
  end

  def apply_numeric_aggs(%SO{} = so) do
    query =
      select_merge(so.query, [c, ...], %{
        count: count(c)
      })

    query =
      case so.search_chart_period do
        :day -> limit(query, 30)
        :hour -> limit(query, 168)
        :minute -> limit(query, 120)
        :second -> limit(query, 180)
      end

    query = order_by(query, [t, ...], desc: 1)
    %{so | query: query}
  end

  def row_keys_to_descriptive_names(%SO{} = so) do
    rows =
      so.rows
      |> Enum.map(fn row ->
        row
        |> Enum.map(fn {k, v} ->
          case k do
            "f0_" ->
              {:ok, v} =
                v
                |> Timex.from_unix(:microseconds)
                |> Timex.format("{RFC822z}")

              {"timestamp", v}

            "f1_" ->
              {"value", v}
          end
        end)
        |> Map.new()
      end)

    %{so | rows: rows}
  end
end