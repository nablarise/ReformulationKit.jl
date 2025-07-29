```@meta
CurrentModule = ReformulationKit
```

# ReformulationKit.jl

ReformulationKit automatically rewrites JuMP models into decomposed forms (e.g., Dantzig-Wolfe), based on simple annotations. It generates the master and subproblem models, letting you focus on modeling while it handles the reformulation logic.

## Overview

Modern optimization problems often benefit from decomposition techniques that exploit their structure.

ReformulationKit makes decomposition easy through a simple annotation-based approach:
- **Automatic reformulation**: Transform your compact JuMP model with only additional code.
- **Structure-aware**: Leverages problem structure through user annotations  
- **Algorithm ready**: Generates all necessary mappings for advanced algorithms
- **JuMP integration**: Works seamlessly with the Julia optimization ecosystem

## Quick Example

Here's how to decompose a Generalized Assignment Problem:

```julia
using JuMP, ReformulationKit

# Define annotation function
gap_annotation(::Val{:x}, machine, job) = dantzig_wolfe_subproblem(machine)
gap_annotation(::Val{:assignment}, job) = dantzig_wolfe_master()
gap_annotation(::Val{:capacity}, machine) = dantzig_wolfe_subproblem(machine)

# Create your JuMP model as usual
model = Model()
@variable(model, x[1:2, 1:3], Bin)
@constraint(model, assignment[j in 1:3], sum(x[m,j] for m in 1:2) >= 1)
@constraint(model, capacity[m in 1:2], sum(x[m,j] for j in 1:3) <= 2)
@objective(model, Min, sum(x[m,j] for m in 1:2, j in 1:3))

# Perform decomposition
reformulation = dantzig_wolfe_decomposition(model, gap_annotation)

# Access the results
master = master(reformulation)           # Master problem with coupling constraints
subproblems = subproblems(reformulation) # Dict of subproblems by ID
```

The decomposition automatically:
- Partitions variables between master and subproblems based on annotations
- Creates coupling constraints in the master for coordination
- Generates capacity constraints in machine-specific subproblems
- Sets up mappings for column generation algorithm

## Getting Started

Ready to decompose your optimization problems? Start with our [GAP Tutorial](tutorials/getting_started/gap_decomposition.md), which walks through a complete example of applying Dantzig-Wolfe decomposition to the Generalized Assignment Problem.

For installation instructions, see [Installation](installation.md).
