defmodule Logflare.BillingAccounts do
  @moduledoc """
  The Billing context.
  """

  require Logger

  import Ecto.Query, warn: false
  alias Logflare.Repo
  alias Logflare.User
  alias __MODULE__
  alias Logflare.BillingAccounts.BillingAccount

  require Protocol
  Protocol.derive(Jason.Encoder, Stripe.List)
  Protocol.derive(Jason.Encoder, Stripe.Subscription)
  Protocol.derive(Jason.Encoder, Stripe.Plan)
  Protocol.derive(Jason.Encoder, Stripe.SubscriptionItem)
  Protocol.derive(Jason.Encoder, Stripe.Session)
  Protocol.derive(Jason.Encoder, Stripe.Invoice)
  Protocol.derive(Jason.Encoder, Stripe.LineItem)
  Protocol.derive(Jason.Encoder, Stripe.Price)

  @doc """
  Returns the list of billing_accounts.

  ## Examples

      iex> list_billing_accounts()
      [%BillingAccount{}, ...]

  """
  def list_billing_accounts do
    Repo.all(BillingAccount)
  end

  @doc """
  Gets a single billing_account by a keyword.
  """
  def get_billing_account_by(kv) do
    Repo.get_by(BillingAccount, kv)
  end

  @doc """
  Gets a single billing_account.

  Raises `Ecto.NoResultsError` if the Billing account does not exist.

  ## Examples

      iex> get_billing_account!(123)
      %BillingAccount{}

      iex> get_billing_account!(456)
      ** (Ecto.NoResultsError)

  """
  def get_billing_account!(id), do: Repo.get!(BillingAccount, id)

  @doc """
  Creates a billing_account.

  ## Examples

      iex> create_billing_account(%{field: value})
      {:ok, %BillingAccount{}}

      iex> create_billing_account(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_billing_account(%User{} = user, attrs \\ %{}) do
    user
    |> Ecto.build_assoc(:billing_account)
    |> BillingAccount.changeset(attrs)
    |> Repo.insert()
  end

  def sync_subscriptions(nil), do: :noop

  def sync_subscriptions(%BillingAccount{stripe_customer: stripe_customer_id} = billing_account) do
    with {:ok, subscriptions} <-
           BillingAccounts.Stripe.list_customer_subscriptions(stripe_customer_id) do
      attrs = %{stripe_subscriptions: subscriptions}

      update_billing_account(billing_account, attrs)
    else
      err -> err
    end
  end

  def sync_invoices(nil), do: :noop

  def sync_invoices(%BillingAccount{stripe_customer: stripe_customer_id} = billing_account) do
    with {:ok, invoices} <- BillingAccounts.Stripe.list_customer_invoices(stripe_customer_id) do
      attrs = %{stripe_invoices: invoices}

      update_billing_account(billing_account, attrs)
    else
      err -> err
    end
  end

  def sync_billing_account(
        %BillingAccount{stripe_customer: customer_id} = billing_account,
        attrs \\ %{}
      ) do
    with {:ok, subscriptions} <- BillingAccounts.Stripe.list_customer_subscriptions(customer_id),
         {:ok, invoices} <- BillingAccounts.Stripe.list_customer_invoices(customer_id) do
      attrs =
        Map.put(attrs, :stripe_subscriptions, subscriptions)
        |> Map.put(:stripe_invoices, invoices)

      update_billing_account(billing_account, attrs)
    else
      err -> err
    end
  end

  @doc """
  Updates a billing_account.

  ## Examples

      iex> update_billing_account(billing_account, %{field: new_value})
      {:ok, %BillingAccount{}}

      iex> update_billing_account(billing_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """

  def update_billing_account(%BillingAccount{} = billing_account, attrs) do
    billing_account
    |> BillingAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a BillingAccount.

  ## Examples

      iex> delete_billing_account(billing_account)
      {:ok, %BillingAccount{}}

      iex> delete_billing_account(billing_account)
      {:error, %Ecto.Changeset{}}

  """
  def delete_billing_account(%BillingAccount{} = billing_account) do
    Repo.delete(billing_account)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking billing_account changes.

  ## Examples

      iex> change_billing_account(billing_account)
      %Ecto.Changeset{source: %BillingAccount{}}

  """
  def change_billing_account(%BillingAccount{} = billing_account) do
    BillingAccount.changeset(billing_account, %{})
  end

  def get_billing_account_stripe_plan(billing_account) when is_nil(billing_account),
    do: {:ok, nil}

  def get_billing_account_stripe_plan(%BillingAccount{} = billing_account) do
    plan =
      case billing_account.stripe_subscriptions["data"] do
        nil ->
          nil

        [] ->
          nil

        list ->
          first = list |> hd
          first["plan"]
      end

    {:ok, plan}
  end

  def get_billing_account_stripe_subscription(billing_account) when is_nil(billing_account),
    do: {:ok, nil}

  def get_billing_account_stripe_subscription(%BillingAccount{} = billing_account) do
    sub =
      case billing_account.stripe_subscriptions["data"] do
        nil ->
          nil

        [] ->
          nil

        list ->
          list |> hd
      end

    {:ok, sub}
  end

  def get_billing_account_stripe_subscription_item(billing_account) when is_nil(billing_account),
    do: {:ok, nil}

  def get_billing_account_stripe_subscription_item(%BillingAccount{} = billing_account) do
    item =
      case billing_account.stripe_subscriptions["data"] do
        nil ->
          nil

        [] ->
          nil

        list ->
          sub = list |> hd

          sub["items"]["data"] |> hd
      end

    {:ok, item}
  end
end
