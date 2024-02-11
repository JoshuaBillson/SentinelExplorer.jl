using SentinelExplorer
using Test, GeoDataFrames, Dates, Logging
using Pipe: @pipe

roi = [ 
    [-114.4, 52.1], 
    [-114.1, 52.1], 
    [-114.1, 51.9], 
    [-114.4, 51.9], 
    [-114.4, 52.1]
]

@testset "SentinelExplorer.jl" begin
    # Test Geometry to WKT
    geom = GeoDataFrames.read("data/roi.geojson").geometry[1]
    wkt = SentinelExplorer._to_wkt(geom)
    wkt_test = @pipe roi |> map(x -> join(x, " "), _) |> join(_, ",") |> "POLYGON (($_))"
    @test wkt == wkt_test

    # Test Bounding Box to WKT
    bb = BoundingBox((52.1, -114.4), (51.9, -114.1))
    wkt = SentinelExplorer._to_wkt(bb)
    @test wkt == wkt_test

    # Test Point to WKT
    p = Point(52.0, -114.25)
    wkt = SentinelExplorer._to_wkt(p)
    @test wkt == "POINT (-114.25 52.0)"

    # Test Search by Geometry
    dates = (DateTime(2020, 8, 4), DateTime(2020, 8, 5))
    result = search("SENTINEL-2", product="L2A", geom=geom, dates=dates)[1,:Name]
    @test !isnothing(match(r"S2B_MSIL2A_20200804T183919_N\d{4}_R\d{3}_T11UPT", result))

    # Test Search by Bounding Box
    result = search("SENTINEL-2", product="L2A", geom=bb, dates=dates)[1,:Name]
    @test !isnothing(match(r"S2B_MSIL2A_20200804T183919_N\d{4}_R\d{3}_T11UPT", result))

    # Test Search by Point
    result = search("SENTINEL-2", product="L2A", geom=p, dates=dates)[1,:Name]
    @test !isnothing(match(r"S2B_MSIL2A_20200804T183919_N\d{4}_R\d{3}_T11UPT", result))

    # Test Search By Tile
    result = search("SENTINEL-2", product="L2A", tile="11UPT", dates=dates)[1,:Name]
    @test !isnothing(match(r"S2B_MSIL2A_20200804T183919_N\d{4}_R\d{3}_T11UPT", result))

    # Test Scene ID
    scene, id_test = search("SENTINEL-2", product="L2A", tile="11UPT", dates=dates)[1,[:Name,:Id]]
    id = get_scene_id(scene)
    @test id == id_test
    @test_throws ArgumentError get_scene_id("foo")

    # Test Authentication
    token_success = get_access_token(ENV["SENTINEL_EXPLORER_USER"], ENV["SENTINEL_EXPLORER_PASS"])
    @test token_success isa String
    Logging.with_logger(Logging.NullLogger()) do
        token_fail = get_access_token(ENV["SENTINEL_EXPLORER_USER"], "fail")
        @test isnothing(token_fail)
    end

    # Test Download
    downloaded = download_scene(scene, token_success, unzip=true)
    @test isdir(downloaded)
    rm(downloaded, recursive=true)
end