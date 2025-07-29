# Installation

## Prerequisites

ReformulationKit.jl requires Julia 1.6 or later and depends on the JuMP ecosystem for optimization modeling.

## Package Installation

ReformulationKit.jl is not yet registered in the Julia General Registry. Install it directly from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/nablarise/ReformulationKit.jl")
```

## Development Installation

For development or to access the latest features:

```julia
using Pkg
Pkg.develop(url="https://github.com/nablarise/ReformulationKit.jl")
```

## Quick Verification

Test your installation with this simple example:

```julia
using JuMP, ReformulationKit

# Create a simple model
model = Model()
@variable(model, x[1:2, 1:2], Bin)
@constraint(model, coupling[j in 1:2], sum(x[i,j] for i in 1:2) >= 1)
@constraint(model, local_constr[i in 1:2], sum(x[i,j] for j in 1:2) <= 1)
@objective(model, Min, sum(x[i,j] for i in 1:2, j in 1:2))

# Define annotation function
test_annotation(::Val{:x}, i, j) = dantzig_wolfe_subproblem(i)
test_annotation(::Val{:coupling}, j) = dantzig_wolfe_master()
test_annotation(::Val{:local_constr}, i) = dantzig_wolfe_subproblem(i)

# Perform decomposition
reformulation = dantzig_wolfe_decomposition(model, test_annotation)

# Verify the result
println("Installation successful! Reformulation type: $(typeof(reformulation))")
println("Master variables: $(num_variables(master(reformulation)))")
println("Subproblems: $(length(subproblems(reformulation)))")
```

If this runs without errors and prints the expected output, your installation is working correctly.

## Troubleshooting

### Common Issues

**Package not found**: Ensure you have an active internet connection and that Git is available on your system.

**Dependency conflicts**: Try updating your Julia packages:
```julia
using Pkg
Pkg.update()
```

**Julia version**: ReformulationKit requires Julia 1.6+. Check your version:
```julia
versioninfo()
```

### Getting Help

If you encounter installation issues:
1. Check the [GitHub Issues](https://github.com/nablarise/ReformulationKit.jl/issues) for known problems
2. Create a new issue with your Julia version and error message
3. Join the Julia discourse for general Julia installation help

## Next Steps

Once installed, head to the [GAP Tutorial](tutorials/getting_started/gap_decomposition.md) to learn how to use ReformulationKit for decomposing optimization problems.