# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-06-30

### Added
- `Gridsquare.distance_between/2` function for calculating distance and bearing between two grid squares
- Returns distance in kilometers and miles, plus bearing in degrees
- Supports adjacent grid squares (east-west, north-south, diagonal) with optimized calculations
- Uses Haversine formula for non-adjacent grid squares

### Fixed
- Fixed ExDoc warning about missing LICENSE file in documentation generation
- Removed LICENSE from docs extras list in mix.exs
- Updated LICENSE link in README.md to point to GitHub repository instead of relative path

## [0.1.0] - 2025-06-24

### Added
- Initial release
- `Gridsquare.encode/2` and `Gridsquare.encode/3` functions for encoding latitude/longitude to Maidenhead grid references
- `Gridsquare.decode/1` function for decoding grid references to coordinates
- `Gridsquare.new/1` function for creating GridSquare structs
- Support for extended precision (6-20 characters)
- Comprehensive documentation and examples
- Test coverage for all functions

### Features
- Maidenhead Locator System grid square encoding/decoding
- Variable precision support (6-20 character grid references)
- Coordinate normalization and bounds checking
- Base 18, 10, and 24 conversion utilities
- Extended precision calculation with alternating base pairs 
