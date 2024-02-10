using SentinelExplorer
using Documenter

DocMeta.setdocmeta!(SentinelExplorer, :DocTestSetup, :(using SentinelExplorer); recursive=true)

makedocs(;
    modules=[SentinelExplorer],
    authors="Joshua Billson",
    sitename="SentinelExplorer.jl",
    format=Documenter.HTML(;
        canonical="https://JoshuaBillson.github.io/SentinelExplorer.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JoshuaBillson/SentinelExplorer.jl",
    devbranch="main",
)
