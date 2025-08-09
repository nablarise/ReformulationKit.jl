# ReformulationKit.jl

ReformulationKit automatically rewrites JuMP models into decomposed forms (e.g., Dantzig-Wolfe), based on simple annotations. It generates the master and subproblem models, letting you focus on modeling while it handles the reformulation logic.

## Quick Example

```julia
using JuMP, ReformulationKit

const RK = ReformulationKit

# Create original model
model = Model()
@variable(model, x[1:2, 1:3], Bin)  # machines × jobs
@constraint(model, demand[j in 1:3], sum(x[m,j] for m in 1:2) >= 1)
@constraint(model, capacity[m in 1:2], sum(x[m,j] for j in 1:3) <= 2)
@objective(model, Min, sum(x[m,j] for m in 1:2, j in 1:3))

# Define annotations: which variables/constraints go where
dw_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine)
dw_annotation(::Val{:demand}, job) = RK.dantzig_wolfe_master()
dw_annotation(::Val{:capacity}, machine) = RK.dantzig_wolfe_subproblem(machine)

# Decompose automatically
reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)

# Access results
master = RK.master(reformulation)      # Master problem with coupling constraints
subproblems = RK.subproblems(reformulation)    # Dict of subproblem models by ID
```

The package handles all the complex reformulation logic - variable mapping, constraint translation, objective decomposition, and column generation setup.