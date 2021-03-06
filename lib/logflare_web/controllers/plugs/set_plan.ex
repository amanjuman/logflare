defmodule LogflareWeb.Plugs.SetPlan do
  @moduledoc """
  Assigns team user if browser session is present in conn
  """
  import Plug.Conn

  alias Logflare.BillingAccounts
  alias Logflare.User
  alias Logflare.Plans

  def init(_), do: nil

  def call(%{assigns: %{user: %User{}}} = conn, opts), do: set_plan(conn, opts)

  def call(conn, _opts), do: conn

  defp set_plan(%{assigns: %{user: user}} = conn, _opts) do
    if user.billing_enabled? do
      billing_account = BillingAccounts.get_billing_account_by(user_id: user.id)

      cond do
        {:ok, nil} == BillingAccounts.get_billing_account_stripe_plan(billing_account) ->
          plan = Plans.get_plan_by(name: "Free")

          conn
          |> assign(:plan, plan)

        true ->
          {:ok, stripe_plan} = BillingAccounts.get_billing_account_stripe_plan(billing_account)

          plan = Plans.get_plan_by(stripe_id: stripe_plan["id"])

          conn
          |> assign(:plan, plan)
      end
    else
      plan = Plans.legacy_plan()

      conn
      |> assign(:plan, plan)
    end
  end
end
