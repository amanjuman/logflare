defmodule LogflareWeb.TeamUserController do
  use LogflareWeb, :controller
  use Phoenix.HTML

  plug LogflareWeb.Plugs.AuthMustBeOwner when action in [:delete]

  alias Logflare.TeamUsers
  alias Logflare.Google.BigQuery
  alias Logflare.Google.CloudResourceManager

  def edit(%{assigns: %{team_user: team_user}} = conn, _params) do
    changeset = TeamUsers.TeamUser.changeset(team_user, %{})

    render(conn, "edit.html", changeset: changeset, team_user: team_user)
  end

  def update(%{assigns: %{team_user: team_user}} = conn, %{"team_user" => params}) do
    case TeamUsers.update_team_user(team_user, params) do
      {:ok, _team_user} ->
        conn
        |> put_flash(:info, "Profile updated!")
        |> redirect(to: Routes.team_user_path(conn, :edit))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Something went wrong!")
        |> render("edit.html", changeset: changeset, team_user: team_user)
    end
  end

  def delete(%{assigns: %{user: user}} = conn, %{"id" => team_user_id} = _params) do
    team_user = TeamUsers.get_team_user!(team_user_id)

    case TeamUsers.delete_team_user(team_user) do
      {:ok, _team_user} ->
        CloudResourceManager.set_iam_policy()
        BigQuery.patch_dataset_access(user)

        conn
        |> put_flash(:info, "Member profile deleted!")
        |> redirect(to: Routes.user_path(conn, :edit))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Something went wrong!")
        |> redirect(to: Routes.user_path(conn, :edit))
    end
  end

  def delete_self(%{assigns: %{team_user: team_user, user: user}} = conn, _params) do
    case TeamUsers.delete_team_user(team_user) do
      {:ok, _team_user} ->
        CloudResourceManager.set_iam_policy()
        BigQuery.patch_dataset_access(user)

        conn
        |> configure_session(drop: true)
        |> put_flash(:info, "Profile deleted!")
        |> redirect(to: Routes.auth_path(conn, :login, team_user_deleted: true))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Something went wrong!")
        |> render("edit.html", changeset: changeset, team_user: team_user)
    end
  end

  def change_team(%{assigns: %{team_user: _team_user, user: _user}} = conn, %{
        "user_id" => user_id,
        "team_user_id" => team_user_id
      }) do
    conn
    |> put_session(:user_id, user_id)
    |> put_session(:team_user_id, team_user_id)
    |> put_flash(:info, "Team changed!")
    |> redirect(to: Routes.source_path(conn, :dashboard))
  end

  def change_team(%{assigns: %{team_user: _team_user, user: _user}} = conn, %{
        "user_id" => user_id
      }) do
    conn
    |> put_session(:user_id, user_id)
    |> delete_session(:team_user_id)
    |> put_flash(:info, "Team changed!")
    |> redirect(to: Routes.source_path(conn, :dashboard))
  end

  def change_team(%{assigns: %{user: _user}} = conn, %{
        "user_id" => user_id,
        "team_user_id" => team_user_id
      }) do
    conn
    |> put_session(:user_id, user_id)
    |> put_session(:team_user_id, team_user_id)
    |> put_flash(:info, "Team changed!")
    |> redirect(to: Routes.source_path(conn, :dashboard))
  end
end
