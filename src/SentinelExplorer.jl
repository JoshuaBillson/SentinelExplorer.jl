module SentinelExplorer

using DataFrames, Dates, WellKnownGeometry, GeoFormatTypes
import HTTP, JSON, ZipFile
using Pipe: @pipe

"""
    Point(lat, lon)

Construct a point located at the provided latitude and longitude.

# Parameters
- `lat`: The latitude of the point.
- `lon`: The longitude of the point.

# Example
p = Point(52.0, -114.25)
"""
struct Point{T}
    lat::T
    lon::T
    Point(lat::T, lon::T) where {T} = new{T}(lat, lon)
end

"""
    BoundingBox(ul, lr)

Construct a bounding box defined by the corners `ul` and `lr`.

All coordinates should be provided in latitude and longitude.

# Parameters
- `ul`: The upper-left corner of the box as a `Tuple{T,T}` of latitude and longitude.
- `lr`: The lower-right corner of the box as a `Tuple{T,T}` of latitude and longitude.

# Example
bb = BoundingBox((52.1, -114.4), (51.9, -114.1))
"""
struct BoundingBox{T}
    ul::Tuple{T,T}
    lr::Tuple{T,T}
    BoundingBox(ul::Tuple{T,T}, lr::Tuple{T,T}) where {T} = new{T}(ul, lr)
end

"""
    get_access_token()
    get_access_token(username, password)

Authenticate with your Copernicus Data Space credentials.

The username and password may be passed explicitly, or provided as a pair of environment variables.

In the case of the latter, `get_access_token()` expects your username and password to be provided as the 
environment variables "SENTINEL_EXPLORER_USER" and "SENTINEL_EXPLORER_PASS".

# Parameters
- `username`: Your Copernicus Data Space username.
- `password`: Your Copernicus Data Space password.

# Returns
An access token for downloading data.

# Example
```julia
token = get_access_token(ENV["SENTINEL_EXPLORER_USER"], ENV["SENTINEL_EXPLORER_PASS"])
token = get_access_token()  # Same as Above
```
"""
function get_access_token(username, password)
    data = Dict(
        "client_id" => "cdse-public",
        "username" => username,
        "password" => password,
        "grant_type" => "password")
    
    try
        auth_url = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
        response = HTTP.post(auth_url, body=data)
        return @pipe String(response.body) |> JSON.parse |> _["access_token"]
    catch e
        @error """
        Authentication failed with response code $(e.status)!

        Response:
        $(e.response)
        """
        return nothing
    end
end

function get_access_token()
    return get_access_token(ENV["SENTINEL_EXPLORER_USER"], ENV["SENTINEL_EXPLORER_PASS"])
end

"""
    search(satellite; product=nothing, dates=nothing, tile=nothing, clouds=nothing, geom=nothing, max_results=100)

Search for satellite images matching the provided filters.

# Parameters
- `satellite`: One of "SENTINEL-1", "SENTINEL-2", or "SENTINEL-3".

# Keywords
- `product`: The product type to search for such as "L2A", "L1C", "GRD", etc.
- `dates`: The date range for image acquisition. Should be a tuple of `DateTime` objects.
- `tile`: Restrict results to a given tile. Only available for Sentinel-2.
- `clouds`: The maximum allowable cloud cover as a percentage. Not available for Sentinel-1.
- `geom`: A geometry specifying the region of interest. Can be a `Point`, `BoundingBox`, or any other `GeoInterface` compatible geometry.
- `max_results`: The maximum number of results to return (default = 100).

# Returns
A `DataFrame` with the columns `:Name`, `:AcquisitionDate`, `:PublicationDate`, `:CloudCover`, and `:Id`.

# Example
```julia
julia> geom = GeoDataFrames.read("test/data/roi.geojson").geometry[1];

julia> dates = (DateTime(2020, 8, 4), DateTime(2020, 8, 5));

julia> search("SENTINEL-2",  geom=geom, dates=dates)
3×5 DataFrame
 Row │ Name                               AcquisitionDate           Pub ⋯
     │ String                             String                    Str ⋯
─────┼───────────────────────────────────────────────────────────────────
   1 │ S2B_MSIL2A_20200804T183919_N0500…  2020-08-04T18:39:19.024Z  202 ⋯
   2 │ S2B_MSIL1C_20200804T183919_N0209…  2020-08-04T18:39:19.024Z  202
   3 │ S2B_MSIL1C_20200804T183919_N0500…  2020-08-04T18:39:19.024Z  202
                                                        3 columns omitted
```
"""
function search(satellite::String; product=nothing, dates=nothing, tile=nothing, clouds=nothing, geom=nothing, max_results=100)
    # Product Filter
    satellites = ["SENTINEL-1", "SENTINEL-2", "SENTINEL-3"]
    !(satellite in satellites) && throw(ArgumentError("satellite must be one of $satellites"))
    filters = ["Collection/Name eq '$satellite'"]
    
    # product Filter
    if !isnothing(product)
        push!(filters, "contains(Name,'$product')")
    end

    # Dates Filter
    if !isnothing(dates)
        dates[1] > dates[2] && throw(ArgumentError("dates must ordered from oldest to newest!"))
        start_string = Dates.format(dates[1], "yyyy-mm-ddTHH:MM:SS.sssZ")
        end_string = Dates.format(dates[2], "yyyy-mm-ddTHH:MM:SS.sssZ")
        df = "ContentDate/Start gt $start_string and ContentDate/Start lt $end_string"
        push!(filters, df)
    end

    # Tile Filter
    if !isnothing(tile)
        satellite != "SENTINEL-2" && throw(ArgumentError("tile filter is only supported for SENTINEL-2!"))
        dtype = "OData.CSC.StringAttribute"
        tf = "Attributes/$dtype/any(att:att/Name eq 'tileId' and att/$dtype/Value eq '$tile')"
        push!(filters, tf)
    end

    # Cloud Filter
    if !isnothing(clouds)
        satellite == "SENTINEL-1" && throw(ArgumentError("cloud filter is not supported for SENTINEL-1!"))
        dtype = "OData.CSC.DoubleAttribute"
        cf = "Attributes/$dtype/any(att:att/Name eq 'cloudCover' and att/$dtype/Value lt $clouds)"
        push!(filters, cf)
    end

    # Geometry Filter
    if !isnothing(geom)
        wkt = _to_wkt(geom)
        gf = "OData.CSC.Intersects(area=geography'SRID=4326;$wkt')"
        push!(filters, gf)
    end

    # Construct Query
    query_string = join(filters, " and ")
    query = Dict(
        "\$filter" => query_string, 
        "\$expand" => "Attributes", 
        "\$top" => max_results, 
        "\$orderby" => "ContentDate/Start asc" )
    url = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
    response = HTTP.get(url, query=query)

    # Process Results
    if response.status == 200
        # Read Results Into DataFrame
        df = @pipe response.body |> String |> JSON.parse |> _["value"] |> DataFrame

        # Throw Error if Results are Empty
        nrow(df) == 0 && throw(ErrorException("Search Returned Zero Results."))

        # Prepare DataFrame
        get_value(x) = isempty(x) ? missing : x[1]["Value"]
        get_clouds(xs) = filter(x -> x["Name"] == "cloudCover", xs) |> get_value
    
        @pipe df |>
        filter(:Online => identity, _) |>
        transform(_, :Attributes => ByRow(get_clouds) => :CloudCover) |>
        transform(_, :ContentDate => ByRow(x -> x["Start"]) => :AcquisitionDate) |>
        _[!,[:Name, :AcquisitionDate, :PublicationDate, :CloudCover, :Id]]
    else
        throw(ErrorException("Search Returned $(response.status)."))
    end
end

"""
    get_scene_id(scene)

Lookup the unique identifier for the provided scene.

# Parameters
- `scene`: The name of the Sentinel scene to lookup.

# Returns
The unique identifier for downloading the provided scene.

# Example
```julia
julia> scene = "S2B_MSIL2A_20200804T183919_N0500_R070_T11UPT_20230321T050221";

julia> get_scene_id(scene)
"29f0eaaf-0b15-412b-9597-16c16d4d79c6"
```
"""
function get_scene_id(scene)
    # Query Filters
    filters = String[]

    # Get Sensing Time
    m = match(r"(\d{8})T", scene)
    if !isnothing(m)
        sense_time = DateTime(m[1], "yyyymmdd")
        start_string = Dates.format(sense_time - Day(1), "yyyy-mm-ddTHH:MM:SS.sssZ")
        end_string = Dates.format(sense_time + Day(1), "yyyy-mm-ddTHH:MM:SS.sssZ")
        df = "ContentDate/Start gt $start_string and ContentDate/Start lt $end_string"
        push!(filters, df)
    end
    
    # Name Filter
    nf = "contains(Name,'$scene')"
    push!(filters, nf)

    # Prepare Query
    url = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
    query = Dict("\$filter" => join(filters, " and "), "\$expand" => "Attributes", )

    # Post Query
    response = @pipe HTTP.get(url, query=query).body |> String |> JSON.parse
    if isempty(response["value"])
        throw(ArgumentError("Could not locate any scene matching the provided name!"))
    end
    return response["value"][1]["Id"]
end

"""
    download_scene(scene, access_token; dir=pwd(), unzip=false)

Download the requested Sentinel scene using the provided access token.

# Parameters
- `scene`: The name of the Sentinel scene to download.
- `access_token`: A token returned by a previous call to `get_access_token`.

# Keywords
- `dir`: The destination directory of the downloaded scene (default = pwd()).
- `unzip`: If true, unzips and deletes the downloaded zip file (default = false).

# Example
```julia
julia> scene = "S2B_MSIL2A_20200804T183919_N0500_R070_T11UPT_20230321T050221";

julia> get_scene_id(scene)
"29f0eaaf-0b15-412b-9597-16c16d4d79c6"
```
"""
function download_scene(scene, access_token; dir=pwd(), unzip=false)
    # Lookup Scene ID
    id = get_scene_id(scene)

    # Prepare Headers
    url = "https://zipper.dataspace.copernicus.eu/odata/v1/Products($id)/\$value"
    headers = Dict("Authorization" => "Bearer $access_token")

    # Download Scene
    downloaded = HTTP.download(url, dir, headers=headers)
    if unzip
        # Unzip and Remove ZipFile
        _unzip(downloaded)
        rm(downloaded)

        # Return Path to Unzipped Filed
        name = match(r"^(.*)\.zip$", basename(downloaded))[1]
        filter(x -> !isnothing(match(Regex(name), x)), readdir(dir, join=true)) |> first
    else
        return downloaded
    end
end

function _to_wkt(geom)
    return getwkt(geom) |> GeoFormatTypes.val |> _latlon_to_lonlat
end

function _to_wkt(geom::Point)
    return "POINT ($(geom.lon) $(geom.lat))"
end

function _to_wkt(geom::BoundingBox)
    lat_top = geom.ul[1]
    lat_bottom = geom.lr[1]
    lon_left = geom.ul[2]
    lon_right = geom.lr[2]
    points = [(lat_top, lon_left), (lat_top, lon_right), (lat_bottom, lon_right), (lat_bottom, lon_left), (lat_top, lon_left)]
    return @pipe points |> map(x -> join(reverse(x), " "), _) |> join(_, ",") |> "POLYGON (($_))"
end

function _latlon_to_lonlat(wkt::String)
    lon_lat = @pipe wkt |>
    eachmatch(r"(-?\d+\.\d*\s-?\d+\.\d*)", _) |>  # Extract Lat/Lon Values
    first.(collect(_)) |>                         # Extract Matches
    split.(_, " ") |>                             # Split Lat/Lon at Space
    reverse.(_) |>                                # Reverse Lat/Lon
    join.(_, " ") |>                              # Join Lon/Lat With Space
    join(_, ",")                                  # Join Coordinates With Commas

    shape, paren = match(r"([A-Z]+\s?\(+)[^)]*(\)+)", wkt) .|> string
    return join([shape, lon_lat, paren], "")
end

function _unzip(file,exdir="")
    fileFullPath = isabspath(file) ?  file : joinpath(pwd(),file)
    basePath = dirname(fileFullPath)
    outPath = (exdir == "" ? basePath : (isabspath(exdir) ? exdir : joinpath(pwd(),exdir)))
    isdir(outPath) ? "" : mkdir(outPath)
    zarchive = ZipFile.Reader(fileFullPath)
    for f in zarchive.files
        fullFilePath = joinpath(outPath,f.name)
        if (endswith(f.name,"/") || endswith(f.name,"\\"))
            mkdir(fullFilePath)
        else
            src = read(f)
            mkpath(dirname(fullFilePath))
            write(fullFilePath, src)
        end
    end
    close(zarchive)
end

export Point, BoundingBox, get_access_token, search, get_scene_id, download_scene


end
