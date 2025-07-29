using Documenter, Literate, ReformulationKit

# Generate tutorials from Literate.jl sources
tutorials_src = joinpath(@__DIR__, "src", "tutorials")
tutorials_dest = joinpath(@__DIR__, "src", "tutorials")

# Process GAP tutorial
gap_tutorial_src = joinpath(tutorials_src, "getting_started", "gap_decomposition.jl")
if isfile(gap_tutorial_src)
    Literate.markdown(gap_tutorial_src, joinpath(tutorials_dest, "getting_started"))
end

makedocs(;
    modules=[ReformulationKit],
    authors="Guillaume Marques <guillaume@nablarise.com>",
    repo="https://github.com/nablarise/ReformulationKit.jl/blob/{commit}{path}#{line}",
    sitename="ReformulationKit.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://nablarise.github.io/ReformulationKit.jl",
        edit_link="main",
    ),
    pages=[
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Tutorials" => [
            "Getting Started" => [
                "GAP Decomposition" => "tutorials/getting_started/gap_decomposition.md",
            ],
        ],
        "Manual" => [
            # Manual pages will be added later
        ],
        "Developer Documentation" => [
            # Developer docs will be added later
        ],
    ],
    doctest=false,  # Disable doctests for now
    warnonly=true   # Continue despite warnings
)

deploydocs(;
    repo="github.com/nablarise/ReformulationKit.jl",
    devbranch="main",
)