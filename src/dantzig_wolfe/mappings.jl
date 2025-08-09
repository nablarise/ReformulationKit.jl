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