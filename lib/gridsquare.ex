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
    @moduledoc """
    Result struct for Gridsquare.encode/3.
    """
    @enforce_keys [:grid_reference, :subsquare]
    defstruct [:grid_reference, :subsquare]
    @typedoc "Result of encode/3"
    @type t :: %__MODULE__{
            grid_reference: Gridsquare.grid_reference(),
            subsquare: Gridsquare.subsquare()
          }
  end

  defmodule DecodeResult do
    @moduledoc """
    Result struct for Gridsquare.decode/1.
    """
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
    @moduledoc """
    Struct representing a decoded grid square.
    """
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

  defmodule DistanceResult do
    @moduledoc """
    Result struct for Gridsquare.distance_between/2.
    """
    @enforce_keys [:distance_km, :distance_mi, :bearing_degrees]
    defstruct [:distance_km, :distance_mi, :bearing_degrees]
    @typedoc "Result of distance_between/2"
    @type t :: %__MODULE__{
            distance_km: float(),
            distance_mi: float(),
            bearing_degrees: float()
          }
  end

  @type encode_result :: EncodeResult.t()
  @type decode_result :: DecodeResult.t()
  @type grid_square :: GridSquare.t()
  @type distance_result :: DistanceResult.t()

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
      %Gridsquare.EncodeResult{grid_reference: "DN40BI57XH", subsquare: "dn40bi"}
  """
  @spec encode(longitude(), latitude(), precision()) :: encode_result()
  def encode(lon, lat, precision \\ 6)
      when precision >= 6 and precision <= 20 and rem(precision, 2) == 0 do
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

    # Calculate base offset (without centering)
    base_lon = -180 + field_lon * 20 + square_lon * 2 + subsquare_lon * (2 / 24)
    base_lat = -90 + field_lat * 10 + square_lat + subsquare_lat * (1 / 24)

    # Starting divisors at subsquare level
    base_lon_div = 2 / 24
    base_lat_div = 1 / 24

    # Parse extended precision pairs if present
    {lon, lat, width, height} =
      decode_extended_pairs(
        grid_reference,
        base_lon,
        base_lat,
        base_lon_div,
        base_lat_div
      )

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

  @doc """
  Calculates the distance and direction between two grid squares.

  Returns a struct with:
  - `distance_km`: Distance in kilometers
  - `distance_mi`: Distance in miles
  - `bearing_degrees`: Bearing in degrees (0-360)

  ## Examples

      iex> result = Gridsquare.distance_between("DN40bi", "DN40bj")
      iex> %Gridsquare.DistanceResult{distance_km: distance_km, distance_mi: distance_mi, bearing_degrees: bearing_degrees} = result
      iex> distance_km > 0
      true
      iex> distance_mi > 0
      true
      iex> bearing_degrees >= 0 and bearing_degrees <= 360
      true

      iex> result = Gridsquare.distance_between("DN40bi", "DN40ci")
      iex> %Gridsquare.DistanceResult{distance_km: distance_km, distance_mi: distance_mi, bearing_degrees: bearing_degrees} = result
      iex> distance_km > 0
      true
      iex> distance_mi > 0
      true
      iex> bearing_degrees >= 0 and bearing_degrees <= 360
      true

      iex> result = Gridsquare.distance_between("DN40bi", "DN40cj")
      iex> %Gridsquare.DistanceResult{distance_km: distance_km, distance_mi: distance_mi, bearing_degrees: bearing_degrees} = result
      iex> distance_km > 0
      true
      iex> distance_mi > 0
      true
      iex> bearing_degrees >= 0 and bearing_degrees <= 360
      true
  """
  @spec distance_between(grid_reference(), grid_reference()) :: distance_result()
  def distance_between(grid_ref1, grid_ref2) when is_binary(grid_ref1) and is_binary(grid_ref2) do
    # Use full-precision centers for distance calculation
    grid1 = new(grid_ref1)
    grid2 = new(grid_ref2)

    c1 = grid1.center
    c2 = grid2.center

    # Normalize to 6-char subsquare level for adjacency detection
    sub1 = new(String.slice(grid_ref1, 0, 6))
    sub2 = new(String.slice(grid_ref2, 0, 6))
    w_deg = sub1.width
    h_deg = sub1.height

    # Calculate deltas using subsquare-level centers for adjacency detection
    lon_delta = abs(sub1.center.longitude - sub2.center.longitude)
    lat_delta = abs(sub1.center.latitude - sub2.center.latitude)

    calculate_distance_result(c1, c2, lon_delta, lat_delta, w_deg, h_deg)
  end

  @doc false
  @spec calculate_distance_result(
          %{latitude: float(), longitude: float()},
          %{latitude: float(), longitude: float()},
          float(),
          float(),
          float(),
          float()
        ) :: distance_result()
  defp calculate_distance_result(c1, c2, lon_delta, lat_delta, w_deg, h_deg) do
    cond do
      east_west_adjacent?(lat_delta, lon_delta, w_deg) ->
        calculate_east_west_distance(c1, c2, w_deg)

      north_south_adjacent?(lon_delta, lat_delta, h_deg) ->
        calculate_north_south_distance(c1, c2, h_deg)

      diagonal_adjacent?(lon_delta, lat_delta, w_deg, h_deg) ->
        calculate_diagonal_distance(c1, c2, w_deg, h_deg)

      true ->
        calculate_center_to_center_distance(c1, c2)
    end
  end

  @doc false
  @spec east_west_adjacent?(float(), float(), float()) :: boolean()
  defp east_west_adjacent?(lat_delta, lon_delta, w_deg) do
    lat_delta < 1.0e-3 and abs(lon_delta - w_deg) < 1.0e-3
  end

  @doc false
  @spec north_south_adjacent?(float(), float(), float()) :: boolean()
  defp north_south_adjacent?(lon_delta, lat_delta, h_deg) do
    lon_delta < 1.0e-3 and abs(lat_delta - h_deg) < 1.0e-3
  end

  @doc false
  @spec diagonal_adjacent?(float(), float(), float(), float()) :: boolean()
  defp diagonal_adjacent?(lon_delta, lat_delta, w_deg, h_deg) do
    abs(lon_delta - w_deg) < 1.0e-3 and abs(lat_delta - h_deg) < 1.0e-3
  end

  @doc false
  @spec calculate_east_west_distance(
          %{latitude: float(), longitude: float()},
          %{latitude: float(), longitude: float()},
          float()
        ) :: distance_result()
  defp calculate_east_west_distance(c1, c2, w_deg) do
    d_km = calculate_width_km(c1.latitude, w_deg)
    d_mi = Float.round(d_km * 0.621371, 2)
    bearing = if c2.longitude > c1.longitude, do: 90.0, else: 270.0
    %DistanceResult{distance_km: d_km, distance_mi: d_mi, bearing_degrees: bearing}
  end

  @doc false
  @spec calculate_north_south_distance(
          %{latitude: float(), longitude: float()},
          %{latitude: float(), longitude: float()},
          float()
        ) :: distance_result()
  defp calculate_north_south_distance(c1, c2, h_deg) do
    d_km = calculate_height_km(h_deg)
    d_mi = Float.round(d_km * 0.621371, 2)
    bearing = if c2.latitude > c1.latitude, do: 0.0, else: 180.0
    %DistanceResult{distance_km: d_km, distance_mi: d_mi, bearing_degrees: bearing}
  end

  @doc false
  @spec calculate_diagonal_distance(
          %{latitude: float(), longitude: float()},
          %{latitude: float(), longitude: float()},
          float(),
          float()
        ) :: distance_result()
  defp calculate_diagonal_distance(c1, c2, w_deg, h_deg) do
    width_km = calculate_width_km(c1.latitude, w_deg)
    height_km = calculate_height_km(h_deg)
    d_km = :math.sqrt(:math.pow(width_km, 2) + :math.pow(height_km, 2))
    d_mi = Float.round(d_km * 0.621371, 2)
    bearing = calculate_bearing(c1, c2)
    %DistanceResult{distance_km: d_km, distance_mi: d_mi, bearing_degrees: bearing}
  end

  @doc false
  @spec calculate_center_to_center_distance(
          %{latitude: float(), longitude: float()},
          %{latitude: float(), longitude: float()}
        ) :: distance_result()
  defp calculate_center_to_center_distance(c1, c2) do
    d_km = haversine_distance(c1, c2)
    d_mi = Float.round(d_km * 0.621371, 2)
    bearing = calculate_bearing(c1, c2)
    %DistanceResult{distance_km: d_km, distance_mi: d_mi, bearing_degrees: bearing}
  end

  @doc false
  @spec calculate_width_km(float(), float()) :: float()
  defp calculate_width_km(lat, w_deg) do
    # Earth's radius in km
    r = 6371.0
    # Convert width in degrees to radians
    w_rad = w_deg * :math.pi() / 180.0
    # Calculate arc length at given latitude
    r * w_rad * :math.cos(lat * :math.pi() / 180.0)
  end

  @doc false
  @spec calculate_height_km(float()) :: float()
  defp calculate_height_km(h_deg) do
    r = 6371.0
    h_rad = h_deg * :math.pi() / 180.0
    r * h_rad
  end

  # Private helper functions

  @spec to_base18(field_index()) :: base18_char()
  defp to_base18(n) when n >= 0 and n < 18 do
    String.at("ABCDEFGHIJKLMNOPQR", n)
  end

  @spec from_base18(base18_char()) :: field_index()
  defp from_base18(<<c>>) when c in ?A..?R, do: c - ?A

  @spec to_base24(subsquare_index()) :: base24_char()
  defp to_base24(n) when n >= 0 and n < 24 do
    String.at("ABCDEFGHIJKLMNOPQRSTUVWX", n)
  end

  @spec from_base24(base24_char()) :: subsquare_index()
  defp from_base24(<<c>>) when c in ?A..?X, do: c - ?A

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

    # Start with subsquare divisors and chain through each pair
    init_lon_div = 2 / 24
    init_lat_div = 1 / 24

    {extended, _, _} =
      Enum.reduce(
        1..remaining_pairs,
        {base_reference, {current_lon, current_lat}, {init_lon_div, init_lat_div}},
        fn i, {acc, {curr_lon, curr_lat}, {prev_lon_div, prev_lat_div}} ->
          if rem(i, 2) == 1 do
            # Base 10 pair - subdivide previous level by 10
            lon_divisor = prev_lon_div / 10
            lat_divisor = prev_lat_div / 10

            extended_lon = min(trunc(curr_lon / lon_divisor), 9)
            extended_lat = min(trunc(curr_lat / lat_divisor), 9)

            new_lon = curr_lon - extended_lon * lon_divisor
            new_lat = curr_lat - extended_lat * lat_divisor

            {acc <> "#{extended_lon}#{extended_lat}", {new_lon, new_lat},
             {lon_divisor, lat_divisor}}
          else
            # Base 24 pair - subdivide previous level by 24
            lon_divisor = prev_lon_div / 24
            lat_divisor = prev_lat_div / 24

            extended_lon = min(trunc(curr_lon / lon_divisor), 23)
            extended_lat = min(trunc(curr_lat / lat_divisor), 23)

            new_lon = curr_lon - extended_lon * lon_divisor
            new_lat = curr_lat - extended_lat * lat_divisor

            {acc <> "#{to_base24(extended_lon)}#{to_base24(extended_lat)}", {new_lon, new_lat},
             {lon_divisor, lat_divisor}}
          end
        end
      )

    extended
  end

  @spec decode_extended_pairs(String.t(), float(), float(), float(), float()) ::
          {float(), float(), float(), float()}
  defp decode_extended_pairs(grid_reference, base_lon, base_lat, lon_div, lat_div) do
    len = String.length(grid_reference)

    if len <= 6 do
      # No extended pairs - center within subsquare
      {base_lon + lon_div / 2, base_lat + lat_div / 2, lon_div, lat_div}
    else
      remaining = String.slice(grid_reference, 6, len - 6)

      pairs =
        for i <- 0..(div(String.length(remaining), 2) - 1),
            do: String.slice(remaining, i * 2, 2)

      {final_lon, final_lat, final_lon_div, final_lat_div} =
        Enum.reduce(
          Enum.with_index(pairs, 1),
          {base_lon, base_lat, lon_div, lat_div},
          &decode_pair/2
        )

      # Center within the final grid cell
      {final_lon + final_lon_div / 2, final_lat + final_lat_div / 2, final_lon_div,
       final_lat_div}
    end
  end

  defp decode_pair({pair, i}, {curr_lon, curr_lat, prev_lon_div, prev_lat_div})
       when rem(i, 2) == 1 do
    # Base 10 pair
    curr_lon_div = prev_lon_div / 10
    curr_lat_div = prev_lat_div / 10
    val_lon = String.to_integer(String.at(pair, 0))
    val_lat = String.to_integer(String.at(pair, 1))

    {curr_lon + val_lon * curr_lon_div, curr_lat + val_lat * curr_lat_div, curr_lon_div,
     curr_lat_div}
  end

  defp decode_pair({pair, _i}, {curr_lon, curr_lat, prev_lon_div, prev_lat_div}) do
    # Base 24 pair
    curr_lon_div = prev_lon_div / 24
    curr_lat_div = prev_lat_div / 24
    val_lon = from_base24(String.at(pair, 0))
    val_lat = from_base24(String.at(pair, 1))

    {curr_lon + val_lon * curr_lon_div, curr_lat + val_lat * curr_lat_div, curr_lon_div,
     curr_lat_div}
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
    # Normalize longitude to -180 to 180 range using modular arithmetic
    temp = :math.fmod(lon + 180, 360)
    temp = if temp < 0, do: temp + 360, else: temp
    normalized_lon = temp - 180

    # fmod maps both 180.0 and -180.0 to -180.0; preserve the convention
    # that positive 180.0 input maps to 179.999999 (eastern edge)
    normalized_lon =
      cond do
        normalized_lon == -180.0 and lon > 0 -> 179.999999
        normalized_lon == 180.0 -> 179.999999
        true -> normalized_lon
      end

    # Clamp latitude to just below 90
    normalized_lat =
      cond do
        lat < -90 -> -90.0
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

  # Distance and bearing calculation functions

  @doc false
  @spec haversine_distance(%{latitude: float(), longitude: float()}, %{
          latitude: float(),
          longitude: float()
        }) :: float()
  defp haversine_distance(%{latitude: lat1, longitude: lon1}, %{latitude: lat2, longitude: lon2}) do
    # Convert degrees to radians
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat_rad = (lat2 - lat1) * :math.pi() / 180
    delta_lon_rad = (lon2 - lon1) * :math.pi() / 180

    # Earth's radius in kilometers
    earth_radius_km = 6371

    # Haversine formula
    a =
      :math.sin(delta_lat_rad / 2) * :math.sin(delta_lat_rad / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon_rad / 2) * :math.sin(delta_lon_rad / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Round to 2 decimal places
    Float.round(earth_radius_km * c, 2)
  end

  @doc false
  @spec calculate_bearing(%{latitude: float(), longitude: float()}, %{
          latitude: float(),
          longitude: float()
        }) :: float()
  defp calculate_bearing(%{latitude: lat1, longitude: lon1}, %{latitude: lat2, longitude: lon2}) do
    # Convert degrees to radians
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lon_rad = (lon2 - lon1) * :math.pi() / 180

    # Calculate bearing
    y = :math.sin(delta_lon_rad) * :math.cos(lat2_rad)

    x =
      :math.cos(lat1_rad) * :math.sin(lat2_rad) -
        :math.sin(lat1_rad) * :math.cos(lat2_rad) * :math.cos(delta_lon_rad)

    bearing_rad = :math.atan2(y, x)
    bearing_deg = bearing_rad * 180 / :math.pi()

    # Normalize to 0-360 degrees using fmod for floating point
    normalized_bearing = :math.fmod(bearing_deg + 360, 360)

    # Round to 1 decimal place
    Float.round(normalized_bearing, 1)
  end
end
