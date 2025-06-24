defmodule Gridsquare do
  @moduledoc """
  GridSquare calculator for encoding/decoding between latitude/longitude and
  Maidenhead Locator System grid references.

  The Maidenhead Locator System is used by ham radio operators to exchange
  approximate locations. It uses a base conversion system with changing radix:
  - First pair: base 18 (A-R) for 10° lat × 20° lon fields
  - Second pair: base 10 (0-9) for 1° lat × 2° lon squares
  - Third pair: base 24 (A-X) for 2.5' lat × 5' lon subsquares
  - Fourth pair: base 10 (0-9) for extended subsquares
  - Can be extended indefinitely with alternating base 10/base 24 pairs
  """

  @typedoc "Longitude in degrees (-180.0 to 180.0)"
  @type longitude :: float()
  @typedoc "Latitude in degrees (-90.0 to 90.0)"
  @type latitude :: float()
  @typedoc "Precision (number of characters in grid reference, 6 to 20)"
  @type precision :: 6..20
  @typedoc "Maidenhead grid reference string (uppercase/lowercase, 6-20 chars)"
  @type grid_reference :: <<_::48, _::_*8>>
  @typedoc "Subsquare string (lowercase, 6 chars)"
  @type subsquare :: <<_::48>>
  @typedoc "Field index (0-17)"
  @type field_index :: 0..17
  @typedoc "Square index (0-9)"
  @type square_index :: 0..9
  @typedoc "Subsquare index (0-23)"
  @type subsquare_index :: 0..23
  @typedoc "Base18 char (A-R)"
  @type base18_char :: String.t()
  @typedoc "Base24 char (A-X)"
  @type base24_char :: String.t()
  @typedoc "Longitude normalized to -180.0 <= x < 180.0"
  @type normalized_longitude :: float()
  @typedoc "Latitude normalized to -90.0 <= x < 90.0"
  @type normalized_latitude :: float()
  @typedoc "Width of grid square in degrees"
  @type grid_width :: float()
  @typedoc "Height of grid square in degrees"
  @type grid_height :: float()

  defmodule EncodeResult do
    @moduledoc false
    @enforce_keys [:grid_reference, :subsquare]
    defstruct [:grid_reference, :subsquare]
    @typedoc "Result of encode/3"
    @type t :: %__MODULE__{
              grid_reference: Gridsquare.grid_reference(),
              subsquare: Gridsquare.subsquare()
            }
  end

  defmodule DecodeResult do
    @moduledoc false
    @enforce_keys [:latitude, :longitude, :width, :height]
    defstruct [:latitude, :longitude, :width, :height]
    @typedoc "Result of decode/1"
    @type t :: %__MODULE__{
              latitude: Gridsquare.latitude(),
              longitude: Gridsquare.longitude(),
              width: Gridsquare.grid_width(),
              height: Gridsquare.grid_height()
            }
  end

  defmodule GridSquare do
    @moduledoc false
    @enforce_keys [:grid_reference, :center, :width, :height]
    defstruct [:grid_reference, :center, :width, :height]
    @typedoc "GridSquare struct"
    @type t :: %__MODULE__{
              grid_reference: Gridsquare.grid_reference(),
              center: %{latitude: Gridsquare.latitude(), longitude: Gridsquare.longitude()},
              width: Gridsquare.grid_width(),
              height: Gridsquare.grid_height()
            }
  end

  @type encode_result :: EncodeResult.t()
  @type decode_result :: DecodeResult.t()
  @type grid_square :: GridSquare.t()

  @typedoc "Internal coordinates for extended precision"
  @type coordinates :: %{
          lon: longitude(),
          lat: latitude(),
          field_lon: field_index(),
          field_lat: field_index(),
          square_lon: square_index(),
          square_lat: square_index(),
          subsquare_lon: subsquare_index(),
          subsquare_lat: subsquare_index()
        }

  @doc """
  Encodes latitude and longitude to a grid square reference.

  ## Examples

      iex> Gridsquare.encode(-111.866785, 40.363840)
      %Gridsquare.EncodeResult{grid_reference: "DN40bi", subsquare: "dn40bi"}

      iex> Gridsquare.encode(-111.866785, 40.363840, 10)
      %Gridsquare.EncodeResult{grid_reference: "DN40BI00OR", subsquare: "dn40bi"}
  """
  @spec encode(longitude(), latitude(), precision()) :: encode_result()
  def encode(lon, lat, precision \\ 6) when precision >= 6 and precision <= 20 do
    {normalized_lon, normalized_lat} = normalize_coordinates(lon, lat)
    {field_lon, field_lat} = calculate_fields(normalized_lon, normalized_lat)

    {square_lon, square_lat} =
      calculate_squares(normalized_lon, normalized_lat, field_lon, field_lat)

    {subsquare_lon, subsquare_lat} =
      calculate_subsquares(
        normalized_lon,
        normalized_lat,
        field_lon,
        field_lat,
        square_lon,
        square_lat
      )

    # Ensure we don't exceed bounds
    field_lon = min(field_lon, 17)
    field_lat = min(field_lat, 17)
    square_lon = min(square_lon, 9)
    square_lat = min(square_lat, 9)
    subsquare_lon = min(subsquare_lon, 23)
    subsquare_lat = min(subsquare_lat, 23)

    # Build the reference
    field = "#{to_base18(field_lon)}#{to_base18(field_lat)}"
    square = "#{square_lon}#{square_lat}"
    subsquare = "#{to_base24(subsquare_lon)}#{to_base24(subsquare_lat)}"

    base_reference = field <> square <> subsquare

    # Add extended precision if requested
    extended_reference =
      if precision > 6 do
        coordinates = %{
          lon: normalized_lon,
          lat: normalized_lat,
          field_lon: field_lon,
          field_lat: field_lat,
          square_lon: square_lon,
          square_lat: square_lat,
          subsquare_lon: subsquare_lon,
          subsquare_lat: subsquare_lat
        }

        add_extended_precision(coordinates, precision)
      else
        base_reference
      end

    grid_ref = format_grid_reference(extended_reference)

    %EncodeResult{grid_reference: grid_ref, subsquare: String.downcase(base_reference)}
  end

  @doc """
  Decodes a grid square reference to latitude and longitude.

  ## Examples

      iex> Gridsquare.decode("DN40bi")
      %Gridsquare.DecodeResult{latitude: 40.35416666666667, longitude: -111.875, width: 0.08333333333333333, height: 0.041666666666666664}
  """
  @spec decode(grid_reference()) :: decode_result()
  def decode(grid_reference) when is_binary(grid_reference) do
    grid_reference = String.upcase(grid_reference)

    # Parse field (first pair - base 18)
    field_lon = from_base18(String.at(grid_reference, 0))
    field_lat = from_base18(String.at(grid_reference, 1))

    # Parse square (second pair - base 10)
    square_lon = String.to_integer(String.at(grid_reference, 2))
    square_lat = String.to_integer(String.at(grid_reference, 3))

    # Parse subsquare (third pair - base 24)
    subsquare_lon = from_base24(String.at(grid_reference, 4))
    subsquare_lat = from_base24(String.at(grid_reference, 5))

    # Calculate center coordinates (Ruby gem logic)
    lon = -180 + field_lon * 20 + square_lon * 2 + subsquare_lon * (2 / 24) + 2 / 24 / 2
    lat = -90 + field_lat * 10 + square_lat + subsquare_lat * (1 / 24) + 1 / 24 / 2

    # Calculate dimensions
    # 5 minutes
    width = 2 / 24
    # 2.5 minutes
    height = 1 / 24

    %DecodeResult{latitude: lat, longitude: lon, width: width, height: height}
  end

  @doc """
  Creates a new GridSquare struct from a grid reference.

  ## Examples

      iex> grid = Gridsquare.new("DN40bi")
      iex> grid.center
      %{latitude: 40.35416666666667, longitude: -111.875}
      iex> grid.width
      0.08333333333333333
      iex> grid.height
      0.041666666666666664
  """
  @spec new(grid_reference()) :: grid_square()
  def new(grid_reference) when is_binary(grid_reference) do
    decoded = decode(grid_reference)

    %GridSquare{
      grid_reference: grid_reference,
      center: %{latitude: decoded.latitude, longitude: decoded.longitude},
      width: decoded.width,
      height: decoded.height
    }
  end

  # Private helper functions

  @spec to_base18(field_index()) :: base18_char()
  defp to_base18(n) when n >= 0 and n < 18 do
    String.at("ABCDEFGHIJKLMNOPQR", n)
  end

  @spec from_base18(base18_char()) :: field_index()
  defp from_base18(char)
       when char in [
              "A",
              "B",
              "C",
              "D",
              "E",
              "F",
              "G",
              "H",
              "I",
              "J",
              "K",
              "L",
              "M",
              "N",
              "O",
              "P",
              "Q",
              "R"
            ] do
    Enum.find_index(
      ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R"],
      &(&1 == char)
    )
  end

  @spec to_base24(subsquare_index()) :: base24_char()
  defp to_base24(n) when n >= 0 and n < 24 do
    String.at("ABCDEFGHIJKLMNOPQRSTUVWX", n)
  end

  @spec from_base24(base24_char()) :: subsquare_index()
  defp from_base24(char)
       when char in [
              "A",
              "B",
              "C",
              "D",
              "E",
              "F",
              "G",
              "H",
              "I",
              "J",
              "K",
              "L",
              "M",
              "N",
              "O",
              "P",
              "Q",
              "R",
              "S",
              "T",
              "U",
              "V",
              "W",
              "X"
            ] do
    Enum.find_index(
      [
        "A",
        "B",
        "C",
        "D",
        "E",
        "F",
        "G",
        "H",
        "I",
        "J",
        "K",
        "L",
        "M",
        "N",
        "O",
        "P",
        "Q",
        "R",
        "S",
        "T",
        "U",
        "V",
        "W",
        "X"
      ],
      &(&1 == char)
    )
  end

  @spec add_extended_precision(coordinates(), precision()) :: grid_reference()
  defp add_extended_precision(
         %{
           lon: lon,
           lat: lat,
           field_lon: field_lon,
           field_lat: field_lat,
           square_lon: square_lon,
           square_lat: square_lat,
           subsquare_lon: subsquare_lon,
           subsquare_lat: subsquare_lat
         },
         precision
       ) do
    base_reference =
      "#{to_base18(field_lon)}#{to_base18(field_lat)}#{square_lon}#{square_lat}#{to_base24(subsquare_lon)}#{to_base24(subsquare_lat)}"

    # Calculate remaining precision levels
    remaining_pairs = div(precision - 6, 2)

    # Remove the base components we've already accounted for
    current_lon = lon - (-180 + field_lon * 20 + square_lon * 2 + subsquare_lon * (2 / 24))
    current_lat = lat - (-90 + field_lat * 10 + square_lat + subsquare_lat * (1 / 24))

    {extended, _} =
      Enum.reduce(1..remaining_pairs, {base_reference, {current_lon, current_lat}}, fn i,
                                                                                       {acc,
                                                                                        {curr_lon,
                                                                                         curr_lat}} ->
        if rem(i, 2) == 1 do
          # Base 10 pair
          lon_divisor = 2 / (24 * :math.pow(10, div(i - 1, 2)))
          lat_divisor = 1 / (24 * :math.pow(10, div(i - 1, 2)))

          extended_lon = trunc(curr_lon / lon_divisor)
          extended_lat = trunc(curr_lat / lat_divisor)

          new_lon = curr_lon - extended_lon * lon_divisor
          new_lat = curr_lat - extended_lat * lat_divisor

          {acc <> "#{extended_lon}#{extended_lat}", {new_lon, new_lat}}
        else
          # Base 24 pair
          lon_divisor = 2 / (24 * :math.pow(10, div(i - 1, 2)) * 24)
          lat_divisor = 1 / (24 * :math.pow(10, div(i - 1, 2)) * 24)

          extended_lon = trunc(curr_lon / lon_divisor)
          extended_lat = trunc(curr_lat / lat_divisor)

          new_lon = curr_lon - extended_lon * lon_divisor
          new_lat = curr_lat - extended_lat * lat_divisor

          {acc <> "#{to_base24(extended_lon)}#{to_base24(extended_lat)}", {new_lon, new_lat}}
        end
      end)

    extended
  end

  @spec format_grid_reference(grid_reference()) :: grid_reference()
  defp format_grid_reference(extended_reference) do
    if String.length(extended_reference) == 6 do
      String.upcase(String.slice(extended_reference, 0, 4)) <>
        String.downcase(String.slice(extended_reference, 4, 2))
    else
      String.upcase(extended_reference)
    end
  end

  @spec normalize_coordinates(longitude(), latitude()) ::
          {normalized_longitude(), normalized_latitude()}
  defp normalize_coordinates(lon, lat) do
    # Normalize longitude to -180 to 180 range
    cond_result =
      cond do
        lon < -180 -> lon + 360
        lon > 180 -> lon - 360
        true -> lon
      end

    normalized_lon =
      then(cond_result, fn l ->
        if l == 180, do: 179.999999, else: l
      end)

    # Clamp latitude to just below 90
    normalized_lat =
      cond do
        lat < -90 -> -90
        lat >= 90 -> 89.999999
        true -> lat
      end

    {normalized_lon, normalized_lat}
  end

  @spec calculate_fields(normalized_longitude(), normalized_latitude()) ::
          {field_index(), field_index()}
  defp calculate_fields(lon, lat) do
    # Calculate field (first pair - base 18)
    field_lon = ((lon + 180) / 20) |> Float.floor() |> trunc()
    field_lat = ((lat + 90) / 10) |> Float.floor() |> trunc()
    {field_lon, field_lat}
  end

  @spec calculate_squares(
          normalized_longitude(),
          normalized_latitude(),
          field_index(),
          field_index()
        ) :: {square_index(), square_index()}
  defp calculate_squares(lon, lat, field_lon, field_lat) do
    # Calculate square (second pair - base 10)
    square_lon = ((lon + 180 - field_lon * 20) / 2) |> Float.floor() |> trunc()
    square_lat = (lat + 90 - field_lat * 10) |> Float.floor() |> trunc()
    {square_lon, square_lat}
  end

  @spec calculate_subsquares(
          normalized_longitude(),
          normalized_latitude(),
          field_index(),
          field_index(),
          square_index(),
          square_index()
        ) :: {subsquare_index(), subsquare_index()}
  defp calculate_subsquares(lon, lat, field_lon, field_lat, square_lon, square_lat) do
    # Calculate subsquare (third pair - base 24)
    subsquare_lon =
      ((lon + 180 - field_lon * 20 - square_lon * 2) / (2 / 24)) |> Float.floor() |> trunc()

    subsquare_lat =
      ((lat + 90 - field_lat * 10 - square_lat) / (1 / 24)) |> Float.floor() |> trunc()

    {subsquare_lon, subsquare_lat}
  end
end
