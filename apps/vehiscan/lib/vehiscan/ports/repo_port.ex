defmodule Vehiscan.Ports.RepoPort do
  @moduledoc """
  Puerto (interfaz) para operaciones de persistencia.
  Define el contrato que cualquier adaptador de base de datos debe cumplir.
  Permite desacoplar el dominio del motor de base de datos concreto.
  """

  @doc "Inserta un nuevo registro."
  @callback insert(struct :: Ecto.Changeset.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc "Actualiza un registro existente."
  @callback update(struct :: Ecto.Changeset.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc "Elimina un registro."
  @callback delete(struct :: Ecto.Schema.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc "Obtiene un registro por su clave primaria."
  @callback get(module :: module(), id :: term()) :: Ecto.Schema.t() | nil

  @doc "Obtiene un registro por su clave primaria o lanza una excepción."
  @callback get!(module :: module(), id :: term()) :: Ecto.Schema.t()

  @doc "Retorna todos los registros de un esquema."
  @callback all(queryable :: Ecto.Queryable.t()) :: [Ecto.Schema.t()]

  @doc "Ejecuta una consulta Ecto."
  @callback one(queryable :: Ecto.Queryable.t()) :: Ecto.Schema.t() | nil

  @doc "Ejecuta múltiples operaciones en una transacción atómica."
  @callback transaction(fun :: fun()) :: {:ok, term()} | {:error, term()}
end
