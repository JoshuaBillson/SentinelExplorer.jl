# SentinelExplorer

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JoshuaBillson.github.io/SentinelExplorer.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JoshuaBillson.github.io/SentinelExplorer.jl/dev/)
[![Build Status](https://github.com/JoshuaBillson/SentinelExplorer.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JoshuaBillson/SentinelExplorer.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JoshuaBillson/SentinelExplorer.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JoshuaBillson/SentinelExplorer.jl)

`SentinelExplorer.jl` is a pure Julia package for querying and downloading Sentinel data from the [Copernicus Data Space Ecosystem](https://dataspace.copernicus.eu/).

# Installation

To install this package, start the Julia REPL and open the package manager by typing `]`.
You can then install `SentinelExplorer` from the official Julia repository like so:

```
(@v1.9) pkg> add SentinelExplorer
```

# Quick Start

```julia
using SentinelExplorer, GeoDataFrames, Dates

# Only Necessary if `SENTINEL_EXPLORER_USER` and `SENTINEL_EXPLORER_PASS` are not Already Set
authenticate("my_username", "my_password")

# Load Region of Interest From External GeoJSON or Shapefile
roi = GeoDataFrames.read("data/roi.geojson").geometry |> first

# Define Region of Interest as a Bounding Box
bb = BoundingBox((52.1, -114.4), (51.9, -114.1))

# Define Region of Interest Centered on a Point
p = Point(52.0, -114.25)

# Search For Sentinel-2 Imagery Intersecting our ROI Between August 1 2020 and August 9 2020
dates = (DateTime(2020, 8, 1), DateTime(2020, 8, 9))
results_1 = search("SENTINEL-2", dates=dates, geom=roi)

# Limit Search to Scenes with no More Than 15% Clouds
results_2 = search("SENTINEL-2", dates=dates, geom=roi, clouds=15)

# Further Limit to L2A Products
results_3 = search("SENTINEL-2", dates=dates, geom=roi, clouds=15, product="L2A")

# Retrieve Result with Lowest Cloud Cover
scene = sort(results_3, :CloudCover) |> first

# Download Scene
download_scene(scene.Name; unzip=true)
```

# Integration with DataDeps

```julia
using SentinelExplorer, DataDeps, SatelliteDataSources, Rasters

# Register Data Dependency
DataDep(
    "S2B_MSIL2A_20200804T183919_N0500_R070_T11UPT_20230321T050221", 
    "Sentinel 2 Test Data", 
    "S2B_MSIL2A_20200804T183919_N0500_R070_T11UPT_20230321T050221", 
    "b320ecdaf31bf8555a37b426623adde7becd5d3b00e9b62c65fb49738290a4c4",
    fetch_method = download_scene,
    post_fetch_method = unpack
) |> register

# Only Necessary if `SENTINEL_EXPLORER_USER` and `SENTINEL_EXPLORER_PASS` are not Already Set
authenticate("my_username", "my_password")

# Download Data and Read Green and NIR Bands
src = datadep"S2B_MSIL2A_20200804T183919_N0500_R070_T11UPT_20230321T050221"
sentinel_2_10m = SatelliteDataSources.Sentinel2{10}(src)
green, nir = RasterStack(sentinel_2_10m, [:green, :nir])

# Convert DNs to Reflectance
green = green .* 0.0001f0
nir = nir .* 0.0001f0

# Compute NDWI
ndwi = (green .- nir) ./ (green .+ nir)
```