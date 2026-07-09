defmodule Vehiscan.Infrastructure.Camera do
  @moduledoc """
  Esquema Ecto para las cámaras del sistema ALPR.
  Gestiona el inventario físico de cámaras y su estado operativo.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cameras" do
    field :code, :string
    field :type, :string
    field :location_name, :string
    field :latitude, :float
    field :longitude, :float
    field :orientation, :string
    field :status, :string, default: "active"
    field :stream_url, :string
    field :zone, :string
    field :source_type, :string, default: "video"

    has_many :alpr_events, Vehiscan.Monitoring.ALPREvent

    timestamps(type: :utc_datetime_usec)
  end

  @valid_statuses ~w(active inactive maintenance error)
  @valid_types ~w(fixed mobile ptz)
  @valid_source_types ~w(video directory youtube live_stream webcam)

  @doc false
  def changeset(camera, attrs) do
    camera
    |> cast(attrs, [:code, :type, :location_name, :latitude, :longitude, :orientation, :status, :stream_url, :zone, :source_type])
    |> validate_required([:code, :type, :location_name, :source_type])
    |> default_webcam_url()
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> unique_constraint(:code)
  end

  defp default_webcam_url(changeset) do
    source_type = get_field(changeset, :source_type)
    stream_url = get_field(changeset, :stream_url)

    if source_type == "webcam" and (is_nil(stream_url) or stream_url == "") do
      put_change(changeset, :stream_url, "0")
    else
      changeset
    end
  end
end
