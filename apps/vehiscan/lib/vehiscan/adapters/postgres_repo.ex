defmodule Vehiscan.Adapters.PostgresRepo do
  @moduledoc """
  Adaptador concreto de persistencia usando Ecto + PostgreSQL.
  Implementa el puerto `Vehiscan.Ports.RepoPort`.
  """
  @behaviour Vehiscan.Ports.RepoPort

  alias Vehiscan.Repo

  @impl true
  def insert(changeset), do: Repo.insert(changeset)

  @impl true
  def update(changeset), do: Repo.update(changeset)

  @impl true
  def delete(struct), do: Repo.delete(struct)

  @impl true
  def get(module, id), do: Repo.get(module, id)

  @impl true
  def get!(module, id), do: Repo.get!(module, id)

  @impl true
  def all(queryable), do: Repo.all(queryable)

  @impl true
  def one(queryable), do: Repo.one(queryable)

  @impl true
  def transaction(fun), do: Repo.transaction(fun)
end
