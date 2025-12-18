# Copyright (c) 2025 Nablarise. All rights reserved.
# Author: Guillaume Marques <guillaume@nablarise.com>
# SPDX-License-Identifier: Proprietary

"""
CouplingConstraintMapping

Stores the mapping from subproblem variables to their coefficients in master constraints.
Uses direct type-stable storage optimized for reduced cost computation and column addition.

Structure:
- MOI.VariableIndex => [(constraint_type, constraint_value, coefficient), ...]

This enables efficient access patterns:
- Reduced cost computation: iterate over all constraint coefficients for a variable
- Column addition: add variable to all relevant master constraints
"""
struct CouplingConstraintMapping
    # Using DataType because typeof(constraint_index) returns DataType, not Type{<:MOI.ConstraintIndex}
    data::Dict{MOI.VariableIndex, Vector{Tuple{DataType, Int64, Float64}}}
end

function CouplingConstraintMapping()
    return CouplingConstraintMapping(Dict{MOI.VariableIndex, Vector{Tuple{DataType, Int64, Float64}}}())
end


"""
    set_coefficient!(mapping::CouplingConstraintMapping, constraint_ref, variable_ref, coeff::Float64)

Add a constraint coefficient for a variable. Stores constraint type, value, and coefficient
as a tuple for efficient access during reduced cost computation and column addition.
"""
function set_coefficient!(mapping::CouplingConstraintMapping, constraint_ref, variable_ref, coeff::Float64)
    constraint_index = JuMP.index(constraint_ref)
    variable_index = JuMP.index(variable_ref)
    constraint_type = typeof(constraint_index)
    constraint_value = constraint_index.value
    
    # Initialize vector for this variable if needed
    if !haskey(mapping.data, variable_index)
        mapping.data[variable_index] = Vector{Tuple{DataType, Int64, Float64}}()
    end
    
    # Add constraint coefficient tuple
    push!(mapping.data[variable_index], (constraint_type, constraint_value, coeff))
end


"""
    get_variable_coefficients(mapping::CouplingConstraintMapping, variable_index::MOI.VariableIndex)

Get all constraint coefficients for a variable. Returns a vector of tuples containing:
(constraint_type, constraint_value, coefficient)

Note: constraint_type is DataType (returned by typeof(constraint_index)) rather than 
Type{<:MOI.ConstraintIndex} to avoid Julia type system conflicts.

This enables efficient patterns for:
- Reduced cost computation: reduced_cost = original_cost - sum(dual[constraint] * coeff for (type, value, coeff) in coefficients)
- Column addition: for (type, value, coeff) in coefficients -> add to constraint type(value)
"""
function get_variable_coefficients(mapping::CouplingConstraintMapping, variable_index::MOI.VariableIndex)
    return get(mapping.data, variable_index, Vector{Tuple{DataType, Int64, Float64}}())
end


"""
OriginalCostMapping

Stores the original objective function coefficients for subproblem variables.
Uses MOI.VariableIndex directly as it's a concrete type.
"""
struct OriginalCostMapping
    data::Dict{MOI.VariableIndex, Float64}
end

function OriginalCostMapping()
    return OriginalCostMapping(Dict{MOI.VariableIndex, Float64}())
end

"""
    get_cost(mapping::OriginalCostMapping, variable_index::MOI.VariableIndex)

Get the original cost of a variable using its MOI index.
"""
function get_cost(mapping::OriginalCostMapping, variable_index::MOI.VariableIndex)
    return get(mapping.data, variable_index, 0.0)
end


"""
    set_cost!(mapping::OriginalCostMapping, variable_ref, cost::Float64)

Set the original cost of a variable.
"""
function set_cost!(mapping::OriginalCostMapping, variable_ref, cost::Float64)
    variable_index = JuMP.index(variable_ref)
    mapping.data[variable_index] = cost
end

# Iteration support for backward compatibility
Base.iterate(mapping::CouplingConstraintMapping) = iterate(mapping.data)
Base.iterate(mapping::CouplingConstraintMapping, state) = iterate(mapping.data, state)

function Base.length(mapping::CouplingConstraintMapping)
    # Return number of variables that have constraint coefficients
    return length(mapping.data)
end

Base.keys(mapping::CouplingConstraintMapping) = keys(mapping.data)
Base.values(mapping::CouplingConstraintMapping) = values(mapping.data)

Base.iterate(mapping::OriginalCostMapping) = iterate(mapping.data)
Base.iterate(mapping::OriginalCostMapping, state) = iterate(mapping.data, state)
Base.length(mapping::OriginalCostMapping) = length(mapping.data)
Base.keys(mapping::OriginalCostMapping) = keys(mapping.data)
Base.values(mapping::OriginalCostMapping) = values(mapping.data)
Base.haskey(mapping::OriginalCostMapping, key::MOI.VariableIndex) = haskey(mapping.data, key)
Base.getindex(mapping::OriginalCostMapping, key::MOI.VariableIndex) = getindex(mapping.data, key)

# Show methods for debugging
function Base.show(io::IO, mapping::CouplingConstraintMapping)
    print(io, "CouplingConstraintMapping with $(length(mapping.data)) variables")
end

function Base.show(io::IO, mapping::OriginalCostMapping)
    print(io, "OriginalCostMapping with $(length(mapping.data)) variables")
end


"""
VariableMapping

Stores the mapping from original variables to reformulation variables in Dantzig-Wolfe decomposition.
Each original variable in the problem is mapped to its corresponding variable in either the master
problem or one of the subproblems.

This mapping is essential for:
- Translating constraints from the original formulation to the reformulated models
- Mapping objective function coefficients to the appropriate submodels
- Maintaining variable relationships during decomposition

Fields:
- mapping::Dict{JuMP.VariableRef, JuMP.VariableRef}: Direct mapping from original to reform variables
"""
struct VariableMapping
    mapping::Dict{JuMP.VariableRef, JuMP.VariableRef}
end

function VariableMapping()
    return VariableMapping(Dict{JuMP.VariableRef, JuMP.VariableRef}())
end

# Base methods to make VariableMapping behave like a dictionary
Base.getindex(mapping::VariableMapping, key::JuMP.VariableRef) = mapping.mapping[key]
Base.setindex!(mapping::VariableMapping, value::JuMP.VariableRef, key::JuMP.VariableRef) = mapping.mapping[key] = value
Base.haskey(mapping::VariableMapping, key::JuMP.VariableRef) = haskey(mapping.mapping, key)
Base.keys(mapping::VariableMapping) = keys(mapping.mapping)
Base.values(mapping::VariableMapping) = values(mapping.mapping)
Base.iterate(mapping::VariableMapping) = iterate(mapping.mapping)
Base.iterate(mapping::VariableMapping, state) = iterate(mapping.mapping, state)
Base.length(mapping::VariableMapping) = length(mapping.mapping)

# Show method for debugging
function Base.show(io::IO, mapping::VariableMapping)
    print(io, "VariableMapping with $(length(mapping.mapping)) variable mappings")
end

"""
ConstraintMapping

Stores the mapping from original constraints to reformulation constraints in Dantzig-Wolfe decomposition.
Each original constraint in the problem is mapped to its corresponding constraint in either the master
problem or one of the subproblems.

This mapping is essential for:
- Translating constraints from the original formulation to the reformulated models
- Maintaining constraint relationships during decomposition
- Enabling efficient constraint access and updates

Fields:
- mapping::Dict{JuMP.ConstraintRef, JuMP.ConstraintRef}: Direct mapping from original to reform constraints
"""
struct ConstraintMapping
    mapping::Dict{JuMP.ConstraintRef, JuMP.ConstraintRef}
end

function ConstraintMapping()
    return ConstraintMapping(Dict{JuMP.ConstraintRef, JuMP.ConstraintRef}())
end

# Base methods to make ConstraintMapping behave like a dictionary
Base.getindex(mapping::ConstraintMapping, key::JuMP.ConstraintRef) = mapping.mapping[key]
Base.setindex!(mapping::ConstraintMapping, value::JuMP.ConstraintRef, key::JuMP.ConstraintRef) = mapping.mapping[key] = value
Base.haskey(mapping::ConstraintMapping, key::JuMP.ConstraintRef) = haskey(mapping.mapping, key)
Base.keys(mapping::ConstraintMapping) = keys(mapping.mapping)
Base.values(mapping::ConstraintMapping) = values(mapping.mapping)
Base.iterate(mapping::ConstraintMapping) = iterate(mapping.mapping)
Base.iterate(mapping::ConstraintMapping, state) = iterate(mapping.mapping, state)
Base.length(mapping::ConstraintMapping) = length(mapping.mapping)

# Show method for debugging
function Base.show(io::IO, mapping::ConstraintMapping)
    print(io, "ConstraintMapping with $(length(mapping.mapping)) constraint mappings")
end

"""
    reformulation_kit_callbacks.jl

Default callback implementation for ReformulationKit's Dantzig-Wolfe reformulations.
This implementation works with ReformulationKit's existing mapping data structures
(CouplingConstraintMapping and OriginalCostMapping).
"""

"""
    RK.MappingBasedCallbacks <: AbstractColumnGenerationCallbacks

Default callback implementation that works with ReformulationKit's mapping data structures.

This callback wraps ReformulationKit's `CouplingConstraintMapping` and `OriginalCostMapping`
to provide the column generation interface. It allows MatheuristicKit to work with
ReformulationKit without circular dependencies.

# Fields
- `coupling_constr_mapping::RK.CouplingConstraintMapping`: Maps subproblem variables to their coefficients in master coupling constraints
- `original_cost_mapping::RK.OriginalCostMapping`: Maps subproblem variables to their original objective coefficients

# Example
```julia
# In ReformulationKit's dantzig_wolfe_decomposition:
coupling_mapping = CouplingConstraintMapping()
cost_mapping = OriginalCostMapping()
# ... populate mappings ...

callbacks = MappingBasedCallbacks(coupling_mapping, cost_mapping)
subproblem.ext[:dw_colgen_callbacks] = callbacks
```
"""
struct MappingBasedCallbacks #<: AbstractColumnGenerationCallbacks
    coupling_constr_mapping::CouplingConstraintMapping
    original_cost_mapping::OriginalCostMapping
end

init_mapping_based_callback!(model::JuMP.Model) = model.ext[:dw_colgen_callbacks] = MappingBasedCallbacks(CouplingConstraintMapping(), OriginalCostMapping())
coupling_mapping(model::JuMP.Model) = model.ext[:dw_colgen_callbacks].coupling_constr_mapping
cost_mapping(model::JuMP.Model) = model.ext[:dw_colgen_callbacks].original_cost_mapping
coupling_mapping_of_owner_model(var::JuMP.VariableRef) = JuMP.owner_model(var).ext[:dw_colgen_callbacks].coupling_constr_mapping
cost_mapping_of_owner_model(var::JuMP.VariableRef) = JuMP.owner_model(var).ext[:dw_colgen_callbacks].original_cost_mapping