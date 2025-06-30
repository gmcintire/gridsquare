defmodule GridsquareTest do
  use ExUnit.Case

  doctest Gridsquare

  describe "encode/2" do
    test "encodes basic coordinates to grid square" do
      result = Gridsquare.encode(-111.866785, 40.363840)
      assert %Gridsquare.EncodeResult{} = result
      assert result.grid_reference == "DN40bi"
      assert result.subsquare == "dn40bi"
    end

    test "encodes with extended precision" do
      result = Gridsquare.encode(-111.866785, 40.363840, 10)
      assert %Gridsquare.EncodeResult{} = result
      assert String.starts_with?(result.grid_reference, "DN40BI")
      assert result.subsquare == "dn40bi"
    end

    test "handles coordinates at field boundaries" do
      result = Gridsquare.encode(-180.0, -90.0)
      assert %Gridsquare.EncodeResult{} = result
      assert result.grid_reference == "AA00aa"
    end

    test "handles coordinates at other field boundaries" do
      result = Gridsquare.encode(180.0, 90.0)
      assert %Gridsquare.EncodeResult{} = result
      assert result.grid_reference == "RR99xx"
    end

    test "normalizes longitude values" do
      result1 = Gridsquare.encode(200.0, 0.0)
      result2 = Gridsquare.encode(-160.0, 0.0)
      assert %Gridsquare.EncodeResult{} = result1
      assert %Gridsquare.EncodeResult{} = result2
      assert result1.grid_reference == result2.grid_reference
    end

    test "clamps latitude values" do
      result1 = Gridsquare.encode(0.0, 100.0)
      result2 = Gridsquare.encode(0.0, 90.0)
      assert %Gridsquare.EncodeResult{} = result1
      assert %Gridsquare.EncodeResult{} = result2
      assert result1.grid_reference == result2.grid_reference
    end
  end

  describe "decode/1" do
    test "decodes basic grid square" do
      result = Gridsquare.decode("DN40bi")
      assert %Gridsquare.DecodeResult{} = result
      assert_in_delta result.latitude, 40.35416666666667, 0.001
      assert_in_delta result.longitude, -111.875, 0.001
      assert_in_delta result.width, 0.08333333333333333, 0.001
      assert_in_delta result.height, 0.041666666666666664, 0.001
    end

    test "handles uppercase input" do
      result1 = Gridsquare.decode("DN40BI")
      result2 = Gridsquare.decode("dn40bi")
      assert %Gridsquare.DecodeResult{} = result1
      assert %Gridsquare.DecodeResult{} = result2
      assert result1.latitude == result2.latitude
      assert result1.longitude == result2.longitude
    end

    test "decodes field boundaries" do
      result = Gridsquare.decode("AA00aa")
      assert %Gridsquare.DecodeResult{} = result
      assert_in_delta result.latitude, -89.97916666666667, 0.001
      assert_in_delta result.longitude, -179.95833333333334, 0.001
    end
  end

  describe "new/1" do
    test "creates grid square struct" do
      grid = Gridsquare.new("DN40bi")
      assert %Gridsquare.GridSquare{} = grid
      assert grid.grid_reference == "DN40bi"
      assert_in_delta grid.center.latitude, 40.35416666666667, 0.001
      assert_in_delta grid.center.longitude, -111.875, 0.001
      assert_in_delta grid.width, 0.08333333333333333, 0.001
      assert_in_delta grid.height, 0.041666666666666664, 0.001
    end
  end

  describe "round trip encoding/decoding" do
    test "basic round trip" do
      original_lon = -111.866785
      original_lat = 40.363840

      encoded = Gridsquare.encode(original_lon, original_lat)
      assert %Gridsquare.EncodeResult{} = encoded
      decoded = Gridsquare.decode(encoded.grid_reference)
      assert %Gridsquare.DecodeResult{} = decoded

      # Should be within the precision of a subsquare
      assert_in_delta decoded.longitude, original_lon, 0.1
      assert_in_delta decoded.latitude, original_lat, 0.1
    end

    test "round trip with extended precision" do
      original_lon = -111.866785
      original_lat = 40.363840

      encoded = Gridsquare.encode(original_lon, original_lat, 8)
      assert %Gridsquare.EncodeResult{} = encoded
      decoded = Gridsquare.decode(encoded.grid_reference)
      assert %Gridsquare.DecodeResult{} = decoded

      # Should be more precise
      assert_in_delta decoded.longitude, original_lon, 0.01
      assert_in_delta decoded.latitude, original_lat, 0.01
    end
  end

  describe "edge cases" do
    test "handles zero coordinates" do
      result = Gridsquare.encode(0.0, 0.0)
      assert %Gridsquare.EncodeResult{} = result
      assert result.grid_reference == "JJ00aa"
    end

    test "handles prime meridian" do
      result = Gridsquare.encode(0.0, 51.5)
      assert %Gridsquare.EncodeResult{} = result
      assert String.starts_with?(result.grid_reference, "JO")
    end

    test "handles equator" do
      result = Gridsquare.encode(0.0, 0.0)
      assert %Gridsquare.EncodeResult{} = result
      assert String.at(result.grid_reference, 1) == "J"
    end
  end

  describe "invalid input and edge cases" do
    test "decode with malformed grid reference (too short)" do
      assert_raise FunctionClauseError, fn -> Gridsquare.decode("A") end
    end

    test "decode with malformed grid reference (nonexistent chars)" do
      assert_raise FunctionClauseError, fn -> Gridsquare.decode("ZZZZZZ") end
    end

    test "encode with minimum precision (6)" do
      result = Gridsquare.encode(-111.866785, 40.363840, 6)
      assert %Gridsquare.EncodeResult{} = result
      assert String.length(result.grid_reference) == 6
    end

    test "encode with maximum precision (20)" do
      result = Gridsquare.encode(-111.866785, 40.363840, 20)
      assert %Gridsquare.EncodeResult{} = result
      assert String.length(result.grid_reference) == 20
    end

    test "encode clamps precision below 6" do
      assert_raise FunctionClauseError, fn -> Gridsquare.encode(-111.866785, 40.363840, 5) end
    end

    test "encode clamps precision above 20" do
      assert_raise FunctionClauseError, fn -> Gridsquare.encode(-111.866785, 40.363840, 21) end
    end
  end

  describe "distance_between/2" do
    test "calculates distance between adjacent north-south subsquares" do
      grid = Gridsquare.decode("DN40bi")
      h_deg = grid.height
      r = 6371.0
      h_rad = h_deg * :math.pi() / 180.0
      expected_km = r * h_rad
      expected_mi = expected_km * 0.621371
      result = Gridsquare.distance_between("DN40bi", "DN40bj")
      assert %Gridsquare.DistanceResult{} = result
      assert_in_delta result.distance_km, expected_km, 0.01
      assert_in_delta result.distance_mi, expected_mi, 0.01
      assert_in_delta result.bearing_degrees, 0.0, 0.1
    end

    test "calculates distance between adjacent east-west subsquares" do
      # Find the east-adjacent subsquare to DN40bi
      # DN40bi is at longitude -111.875, width is 0.083333... degrees
      # So east-adjacent should be at -111.791666...
      grid = Gridsquare.decode("DN40bi")
      lat = grid.latitude
      w_deg = grid.width
      r = 6371.0
      w_rad = w_deg * :math.pi() / 180.0
      expected_km = r * w_rad * :math.cos(lat * :math.pi() / 180.0)
      expected_mi = expected_km * 0.621371
      result = Gridsquare.distance_between("DN40bi", "DN40ci")
      assert %Gridsquare.DistanceResult{} = result
      assert_in_delta result.distance_km, expected_km, 0.01
      assert_in_delta result.distance_mi, expected_mi, 0.01
      assert_in_delta result.bearing_degrees, 90.0, 0.1
    end

    test "calculates distance between diagonal subsquares" do
      # DN40bi (lat: 40.354166..., lon: -111.875)
      # DN40cj (lat: 40.395833..., lon: -111.791666...)
      grid = Gridsquare.decode("DN40bi")
      lat = grid.latitude
      w_deg = grid.width
      h_deg = grid.height
      r = 6371.0
      w_rad = w_deg * :math.pi() / 180.0
      h_rad = h_deg * :math.pi() / 180.0
      width_km = r * w_rad * :math.cos(lat * :math.pi() / 180.0)
      height_km = r * h_rad
      expected_km = :math.sqrt(width_km * width_km + height_km * height_km)
      expected_mi = expected_km * 0.621371
      result = Gridsquare.distance_between("DN40bi", "DN40cj")
      assert %Gridsquare.DistanceResult{} = result
      assert_in_delta result.distance_km, expected_km, 0.01
      assert_in_delta result.distance_mi, expected_mi, 0.01
      assert result.bearing_degrees > 0 and result.bearing_degrees < 90
    end

    test "calculates distance between non-adjacent grid squares" do
      result = Gridsquare.distance_between("DN40bi", "DN41bi")
      assert %Gridsquare.DistanceResult{} = result
      assert result.distance_km > 100
      assert result.distance_mi > 60
      assert result.bearing_degrees >= 0 and result.bearing_degrees <= 360
    end

    test "handles extended precision grid references" do
      result = Gridsquare.distance_between("DN40bi", "DN40bj")
      assert %Gridsquare.DistanceResult{} = result
      assert result.distance_km > 0
      assert result.distance_mi > 0
      assert result.bearing_degrees >= 0 and result.bearing_degrees <= 360
    end

    test "distance_mi is correctly calculated from distance_km" do
      result = Gridsquare.distance_between("DN40bi", "DN40bj")
      assert %Gridsquare.DistanceResult{} = result
      # Verify that miles is approximately 0.621371 times kilometers, rounded to 2 decimals
      assert result.distance_mi == Float.round(result.distance_km * 0.621371, 2)
    end
  end
end
