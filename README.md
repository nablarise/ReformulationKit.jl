# ReformulationKit.jl

ReformulationKit automatically rewrites JuMP models into decomposed forms (e.g., Dantzig-Wolfe), based on simple annotations. It generates the master and subproblem models, letting you focus on modeling while it handles the reformulation logic.


## Quick Example

```julia
using JuMP, ReformulationKit

# Create original model
model = Model()
@variable(model, x[1:2, 1:3], Bin)  # machines × jobs
@constraint(model, demand[j in 1:3], sum(x[m,j] for m in 1:2) >= 1)
@constraint(model, capacity[m in 1:2], sum(x[m,j] for j in 1:3) <= 2)
@objective(model, Min, sum(x[m,j] for m in 1:2, j in 1:3))

# Decompose with declarative syntax
reformulation = @dantzig_wolfe model begin
    x[m, _] => subproblem(m)         # Variables x[m,j] go to subproblem m
    demand[_] => master()            # Demand constraints go to master
    capacity[m] => subproblem(m)     # Capacity constraints go to subproblem m
end

# Access results
master = master(reformulation)             # Master problem with coupling constraints
subproblems = subproblems(reformulation)   # Dict of subproblem models by ID
```

The package handles all the complex reformulation logic - variable mapping, constraint translation, objective decomposition, and column generation setup.