module ReformulationKit

using JuMP, MathOptInterface

const MOI = MathOptInterface

include("indexes.jl")

struct SubproblemAnnotation
    id::Any
end

struct MasterAnnotation
end

dantzig_wolfe_subproblem(id) = SubproblemAnnotation(id)
dantzig_wolfe_master() = MasterAnnotation()

include("dantzig_wolfe/mappings.jl")
include("dantzig_wolfe/reformulation.jl")
include("dantzig_wolfe/partitionning.jl")
include("dantzig_wolfe/models.jl")
include("dantzig_wolfe/macro.jl")


"""
    dantzig_wolfe_decomposition(model::Model, dw_annotation) -> DantzigWolfeReformulation

Perform Dantzig-Wolfe decomposition of a JuMP optimization model based on user-provided 
variable and constraint annotations.

# Arguments
- `model::Model`: The original JuMP model to decompose
- `dw_annotation`: Annotation function that determines the assignment of variables and 
  constraints to master problem or subproblems. Should return either:
  - `dantzig_wolfe_master()` for master problem assignment
  - `dantzig_wolfe_subproblem(id)` for subproblem assignment with given ID

# Annotation Function Pattern
The annotation function should follow this pattern:
```julia
dw_annotation(::Val{:variable_name}, indices...) -> SubproblemAnnotation | MasterAnnotation
dw_annotation(::Val{:constraint_name}, indices...) -> SubproblemAnnotation | MasterAnnotation
```

# Returns
A `DantzigWolfeReformulation` containing:
- `master_problem::Model`: The master problem with coupling constraints and convexity constraints
- `subproblems::Dict{Any,Model}`: Dictionary mapping subproblem IDs to their JuMP models
- `convexity_constraints_lb::Dict{Any,Any}`: Lower bound convexity constraints for each subproblem
- `convexity_constraints_ub::Dict{Any,Any}`: Upper bound convexity constraints for each subproblem

# Process Overview
1. **Variable Partitioning**: Variables are partitioned between master and subproblems based on annotations
2. **Constraint Partitioning**: Constraints are assigned to master (coupling) or subproblems based on annotations
3. **Model Creation**: Separate JuMP models are created for master and each subproblem
4. **Variable Registration**: Variables are recreated in their assigned models with original properties
5. **Constraint Registration**: Constraints are recreated using mapped variables
6. **Objective Decomposition**: Original objective is split so each model gets terms for its variables only
7. **Convexity Constraints**: Empty convexity constraints are added to master for each subproblem
8. **Mapping Setup**: Internal mappings are created for column generation support

# Subproblem Extensions
Each subproblem model gets the following extensions in `model.ext`:
- `:dw_coupling_constr_mapping`: CouplingConstraintMapping storing master constraint to subproblem variable coefficients using type-stable MOI indices
- `:dw_sp_var_original_cost`: OriginalCostMapping storing subproblem variables to their original objective coefficients using MOI.VariableIndex

# Example
```julia
# Define annotation function
dw_annotation(::Val{:x}, machine, job) = dantzig_wolfe_subproblem(machine)
dw_annotation(::Val{:demand}, job) = dantzig_wolfe_master()
dw_annotation(::Val{:capacity}, machine) = dantzig_wolfe_subproblem(machine)

# Create original model
model = Model()
@variable(model, x[1:2, 1:3], Bin)
@constraint(model, demand[j in 1:3], sum(x[m,j] for m in 1:2) >= 1)
@constraint(model, capacity[m in 1:2], sum(x[m,j] for j in 1:3) <= 2)
@objective(model, Min, sum(x[m,j] for m in 1:2, j in 1:3))

# Perform decomposition
reformulation = dantzig_wolfe_decomposition(model, dw_annotation)

# Access results
master = master(reformulation)
subproblems = subproblems(reformulation)
```

# Notes
- Variables and constraints not annotated will cause errors
- Each subproblem must have at least one variable
- Master problem contains coupling constraints that involve multiple subproblems
- Convexity constraints are initially infeasible and need to be populated during column generation
- The decomposition preserves all variable properties (bounds, types, etc.)
"""
function dantzig_wolfe_decomposition(model::Model, dw_annotation)
    # Parse variables and their annotations
    # TODO: master variables missing.
    master_vars = _master_variables(model, dw_annotation)
    sp_vars_partitionning = _partition_subproblem_variables(model, dw_annotation)

    master_constrs = _master_constraints(model, dw_annotation)
    sp_constrs_paritionning = _partition_subproblem_constraints(model, dw_annotation)

    # Create master problem
    master_model = Model()
    JuMP.set_objective_sense(master_model, JuMP.objective_sense(model))

    original_to_reform_vars_mapping = VariableMapping()
    original_to_reform_constrs_mapping = ConstraintMapping()

    master_var_infos = Dict(
        var_name => Dict(
            index => _original_var_info(model, var_name, index) for index in indexes
        ) for (var_name, indexes) in master_vars
    )
    _register_variables!(master_model, original_to_reform_vars_mapping, model, master_var_infos)


    # Create subproblems
    subproblem_ids = keys(sp_vars_partitionning)
    subproblem_models = Dict(sp_id... => Model() for sp_id in subproblem_ids)

    # Create subroblem variables
    subproblem_var_infos = Dict(
        sp_id => Dict(
            var_name => Dict(
                index => _original_var_info(model, var_name, index) for index in indexes
            ) for (var_name, indexes) in var_by_names
        ) for (sp_id, var_by_names) in sp_vars_partitionning
    )

    for (sp_id, var_infos_by_names) in subproblem_var_infos
        sp_model = subproblem_models[sp_id]
        _register_variables!(sp_model, original_to_reform_vars_mapping, model, var_infos_by_names)
    end

    # Create subproblem constraints
    for (sp_id, constr_by_names) in sp_constrs_paritionning
        sp_model = subproblem_models[sp_id]
        _register_constraints!(sp_model, original_to_reform_constrs_mapping, model, constr_by_names, original_to_reform_vars_mapping)
    end

    # Create master constraints
    _register_constraints!(master_model, original_to_reform_constrs_mapping, model, master_constrs, original_to_reform_vars_mapping)
    
    # Create objectives
    for (sp_id, sp_model) in subproblem_models
        _register_objective!(sp_model, model, original_to_reform_vars_mapping; is_master=false)
    end
    _register_objective!(master_model, model, original_to_reform_vars_mapping; is_master=true)

    # Add convexity constraints (initially empty)
    convexity_constraints_lb = Dict()
    convexity_constraints_ub = Dict()

    @constraint(master_model, conv_lb[sp_id in subproblem_ids], 0 >= 0)
    @constraint(master_model, conv_ub[sp_id in subproblem_ids], 0 <= 1)

    for sp_id in subproblem_ids
        convexity_constraints_lb[sp_id] = conv_lb[sp_id]
        convexity_constraints_ub[sp_id] = conv_ub[sp_id]
    end

    _subproblem_solution_to_master_constr_mapping!(
        subproblem_models, master_model, original_to_reform_vars_mapping, original_to_reform_constrs_mapping
    )

    _subproblem_solution_to_original_cost_mapping!(
        subproblem_models, master_model, model, original_to_reform_vars_mapping
    )

    return DantzigWolfeReformulation(master_model, subproblem_models, convexity_constraints_lb, convexity_constraints_ub)
end

export dantzig_wolfe_decomposition, dantzig_wolfe_subproblem, dantzig_wolfe_master, @dantzig_wolfe

end # module ReformulationKit
