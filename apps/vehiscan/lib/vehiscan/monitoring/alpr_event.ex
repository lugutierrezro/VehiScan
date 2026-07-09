defmodule Vehiscan.Monitoring.ALPREvent do
  @moduledoc """
  Esquema Ecto para los eventos de lectura ALPR.
  Representa cada captura realizada por una cámara del sistema.
  Incluye índice GIN en normalized_plate para búsquedas eficientes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alpr_events" do
    field :normalized_plate, :string
    field :original_plate, :string
    field :confidence, :float
    field :plate_image_url, :string
    field :context_image_url, :string
    field :status, :string, default: "new"
    field :location_name, :string

    belongs_to :camera, Vehiscan.Infrastructure.Camera
    has_many :alerts, Vehiscan.Monitoring.Alert

    timestamps(type: :utc_datetime_usec)
  end

  @valid_statuses ~w(new processed alerted dismissed)

  @doc false
  def changeset(event, attrs) do
    has_string_keys? = Enum.any?(attrs, fn {k, _} -> is_binary(k) end)

    attrs =
      cond do
        has_string_keys? && !Map.has_key?(attrs, "normalized_plate") ->
          original = Map.get(attrs, "original_plate")
          if original, do: Map.put(attrs, "normalized_plate", original), else: attrs

        !has_string_keys? && !Map.has_key?(attrs, :normalized_plate) ->
          original = Map.get(attrs, :original_plate)
          if original, do: Map.put(attrs, :normalized_plate, original), else: attrs

        true ->
          attrs
      end

    event
    |> cast(attrs, [:normalized_plate, :original_plate, :confidence, :plate_image_url,
                    :context_image_url, :status, :location_name, :camera_id])
    |> validate_required([:normalized_plate, :original_plate, :confidence])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_inclusion(:status, @valid_statuses)
    |> normalize_plate()
  end

  defp normalize_plate(changeset) do
    case get_change(changeset, :normalized_plate) do
      nil -> changeset
      plate ->
        normalized = plate |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
        put_change(changeset, :normalized_plate, normalized)
    end
  end

  @doc "Verifica si la confianza de lectura supera el umbral recomendado (75%)."
  def high_confidence?(%__MODULE__{confidence: confidence}), do: confidence >= 75.0

  @doc "Extrae el nombre del archivo de imagen de recorte a partir de los atributos guardados."
  def get_crop_filename(%__MODULE__{plate_image_url: plate_image_url}), do: get_crop_filename(plate_image_url)
  def get_crop_filename(plate_image_url) when is_binary(plate_image_url) do
    if String.starts_with?(plate_image_url, "attributes|") do
      plate_image_url
      |> String.split("|")
      |> Enum.find(&String.starts_with?(&1, "crop:"))
      |> case do
        nil -> nil
        crop_str ->
          crop_str
          |> String.replace("crop:", "")
          |> String.split(["/", "\\"])
          |> List.last()
      end
    else
      nil
    end
  end
  def get_crop_filename(_), do: nil

  @doc "Retorna la ruta URL para cargar la imagen de recorte en la interfaz."
  def get_crop_url(event = %__MODULE__{}) do
    case get_crop_filename(event) do
      nil -> nil
      filename ->
        if String.match?(filename, ~r/^vehicle_-?\d+_frame_\d+\.(jpg|jpeg|png)$/i) do
          "/crops/#{filename}"
        else
          nil
        end
    end
  end
  def get_crop_url(_), do: nil

  @doc "Extrae la clase de vehículo a partir de los atributos guardados."
  def get_class(%__MODULE__{plate_image_url: plate_image_url}), do: get_class(plate_image_url)
  def get_class(plate_image_url) when is_binary(plate_image_url) do
    if String.starts_with?(plate_image_url, "attributes|") do
      plate_image_url
      |> String.split("|")
      |> Enum.find(&String.starts_with?(&1, "class:"))
      |> case do
        nil -> "unknown"
        class_str -> String.replace(class_str, "class:", "")
      end
    else
      "unknown"
    end
  end
  def get_class(_), do: "unknown"

  @doc "Extrae el color dominante del vehículo a partir de los atributos guardados."
  def get_color(%__MODULE__{plate_image_url: plate_image_url}), do: get_color(plate_image_url)
  def get_color(plate_image_url) when is_binary(plate_image_url) do
    if String.starts_with?(plate_image_url, "attributes|") do
      plate_image_url
      |> String.split("|")
      |> Enum.find(&String.starts_with?(&1, "color:"))
      |> case do
        nil -> "unknown"
        color_str -> String.replace(color_str, "color:", "")
      end
    else
      "unknown"
    end
  end
  def get_color(_), do: "unknown"
end
