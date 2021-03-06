defmodule LogflareWeb.Auth.VercelAuth do
  @moduledoc """
  What we do when someone signs up and oauth's from the Vercel integration.
  """
  use LogflareWeb, :controller

  @config Application.get_env(:logflare, __MODULE__)

  def set_oauth_params(%{query_string: query_string} = conn, _params) do
    redirect_uri = "#{@config[:vercel_app_host]}/api/callback?#{query_string}"

    params = %{
      "client_id" => "#{@config[:client_id]}",
      "redirect_uri" => redirect_uri,
      "scope" => "read write",
      "response_type" => "code"
    }

    conn
    |> put_session(:oauth_params, params)
    |> redirect(to: Routes.auth_path(conn, :login))
  end
end
