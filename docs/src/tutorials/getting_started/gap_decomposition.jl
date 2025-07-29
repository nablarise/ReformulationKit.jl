# # Generalized Assignment Problem with Dantzig-Wolfe Decomposition
#
# This tutorial demonstrates how to use ReformulationKit to automatically reformulate 
# a Generalized Assignment Problem (GAP) using Dantzig-Wolfe decomposition.

# ## Problem Description
#
# The Generalized Assignment Problem assigns jobs to machines with capacity constraints.
# Each assignment has a cost, and jobs can be penalized if not assigned. 
#
# Mathematical formulation:
# ```math
# \begin{align}
# \min \quad & \sum_{m,j} c_{mj} x_{mj} + \sum_j p_j \cdot \text{penalty}_j \\
# \text{s.t.} \quad & \sum_m x_{mj} + \text{penalty}_j \geq 1 \quad \forall j \quad \text{(assignment)} \\
# & \sum_j w_{mj} x_{mj} \leq Q_m \quad \forall m \quad \text{(capacity)} \\
# & x_{mj} \in \{0,1\}, \quad \text{penalty}_j \geq 0
# \end{align}
# ```

# ## Setup and Data

using JuMP, ReformulationKit

# Problem dimensions and data
machines = 1:2
jobs = 1:3
assignment_costs = [1 2 3; 4 5 6]  # Cost matrix: machines × jobs
penalty_costs = [10, 12, 8]        # Penalty for unassigned jobs
weights = [1 1 1; 1 1 1]           # Resource consumption (uniform)
capacities = [2, 2]                # Machine capacities

nothing # hide

# ## JuMP Model

# Create the complete GAP model:
model = Model()

# Variables
@variable(model, x[machines, jobs], Bin);    # Assignment variables
@variable(model, penalty[jobs] >= 0);        # Penalty variables

# Constraints
@constraint(model, assignment[j in jobs], 
    sum(x[m, j] for m in machines) + penalty[j] >= 1);  # Each job assigned or penalized

@constraint(model, knapsack[m in machines], 
    sum(weights[m, j] * x[m, j] for j in jobs) <= capacities[m]);  # Machine capacity

# Objective
@objective(model, Min, 
    sum(assignment_costs[m, j] * x[m, j] for m in machines, j in jobs) + 
    sum(penalty_costs[j] * penalty[j] for j in jobs));

println(model)

# ## Annotation Function
#
# The annotation function determines decomposition structure.
# It receives as argument the name first and then the indices of the variable or the constraint.
# You must annotate all constraints and variables.

gap_annotation(::Val{:x}, machine, job) = dantzig_wolfe_subproblem(machine)
gap_annotation(::Val{:penalty}, job) = dantzig_wolfe_master()
gap_annotation(::Val{:assignment}, job) = dantzig_wolfe_master()
gap_annotation(::Val{:knapsack}, machine) = dantzig_wolfe_subproblem(machine)

nothing # hide

# ## Decomposition

# Perform the automatic decomposition:
reformulation = dantzig_wolfe_decomposition(model, gap_annotation);

println(master(reformulation))

println(subproblems(reformulation)[1])

# ## Results Analysis

# **Master Problem** (coordinates job assignments):
master_problem = master(reformulation)
println(master_problem)

# **Subproblems** (machine-specific decisions):
subproblems_dict = subproblems(reformulation);

# Each subproblem handles one machine's assignment decisions within capacity
for m in machines
    sp = subproblems_dict[m]
    println("-- subproblem for machine $m --")
    println(sp)
end
