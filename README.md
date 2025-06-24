# Gridsquare

[![Hex.pm](https://img.shields.io/hexpm/v/gridsquare.svg)](https://hex.pm/packages/gridsquare)
[![Hex.pm](https://img.shields.io/hexpm/dt/gridsquare.svg)](https://hex.pm/packages/gridsquare)
[![Hex.pm](https://img.shields.io/hexpm/l/gridsquare.svg)](https://hex.pm/packages/gridsquare)
[![CI](https://github.com/gmcintire/gridsquare/workflows/CI/badge.svg)](https://github.com/gmcintire/gridsquare/actions)

GridSquare calculator for encoding/decoding between latitude/longitude and Maidenhead Locator System grid references.

The Maidenhead Locator System is used by ham radio operators to exchange approximate locations. It uses a base conversion system with changing radix:
- First pair: base 18 (A-R) for 10° lat × 20° lon fields
- Second pair: base 10 (0-9) for 1° lat × 2° lon squares
- Third pair: base 24 (A-X) for 2.5' lat × 5' lon subsquares
- Fourth pair: base 10 (0-9) for extended subsquares
- Can be extended indefinitely with alternating base 10/base 24 pairs

## Installation

The package can be installed by adding `gridsquare` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gridsquare, "~> 0.1.0"}
  ]
end
```

## Usage

### Encoding coordinates to grid square

```elixir
# Basic encoding (6-character precision)
Gridsquare.encode(-111.866785, 40.363840)
# Returns: %Gridsquare.EncodeResult{grid_reference: "DN40bi", subsquare: "dn40bi"}

# Extended precision (10-character precision)
Gridsquare.encode(-111.866785, 40.363840, 10)
# Returns: %Gridsquare.EncodeResult{grid_reference: "DN40BI00OR", subsquare: "dn40bi"}
```

### Decoding grid square to coordinates

```elixir
Gridsquare.decode("DN40bi")
# Returns: %Gridsquare.DecodeResult{
#   latitude: 40.35416666666667,
#   longitude: -111.875,
#   width: 0.08333333333333333,
#   height: 0.041666666666666664
# }
```

### Creating a GridSquare struct

```elixir
grid = Gridsquare.new("DN40bi")
# Returns: %Gridsquare.GridSquare{
#   grid_reference: "DN40bi",
#   center: %{latitude: 40.35416666666667, longitude: -111.875},
#   width: 0.08333333333333333,
#   height: 0.041666666666666664
# }

# Access the center coordinates
grid.center.latitude   # 40.35416666666667
grid.center.longitude  # -111.875

# Access the dimensions
grid.width   # 0.08333333333333333 (5 minutes)
grid.height  # 0.041666666666666664 (2.5 minutes)
```

## API Reference

### `Gridsquare.encode(longitude, latitude, precision \\ 6)`

Encodes latitude and longitude coordinates to a Maidenhead grid square reference.

**Parameters:**
- `longitude` (float): Longitude coordinate (-180 to 180)
- `latitude` (float): Latitude coordinate (-90 to 90)
- `precision` (integer): Number of characters in the grid reference (6 to 20, default: 6)

**Returns:** `%Gridsquare.EncodeResult{grid_reference: String.t(), subsquare: String.t()}`

### `Gridsquare.decode(grid_reference)`

Decodes a Maidenhead grid square reference to latitude and longitude coordinates.

**Parameters:**
- `grid_reference` (String.t()): The grid square reference to decode

**Returns:** `%Gridsquare.DecodeResult{latitude: float(), longitude: float(), width: float(), height: float()}`

### `Gridsquare.new(grid_reference)`

Creates a GridSquare struct from a grid reference.

**Parameters:**
- `grid_reference` (String.t()): The grid square reference

**Returns:** `%Gridsquare.GridSquare{grid_reference: String.t(), center: %{latitude: float(), longitude: float()}, width: float(), height: float()}`

## Precision Levels

The precision parameter controls how many characters are in the resulting grid reference:

- **6 characters** (default): Field + Square + Subsquare (2.5' × 5' precision)
- **8 characters**: Adds first extended pair (base 10)
- **10 characters**: Adds second extended pair (base 24)
- **12 characters**: Adds third extended pair (base 10)
- And so on...

Each additional pair increases precision by approximately 10x.

## Examples

```elixir
# High precision encoding for precise location
precise_grid = Gridsquare.encode(-111.866785, 40.363840, 12)
# %Gridsquare.EncodeResult{grid_reference: "DN40BI00OR12", subsquare: "dn40bi"}

# Decode back to coordinates
precise_location = Gridsquare.decode("DN40BI00OR12")
# Returns %Gridsquare.DecodeResult{} with much higher precision
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request

## License

This project is licensed under the GPLv2 License - see the [LICENSE](LICENSE) file for details.

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at <https://hexdocs.pm/gridsquare>.

