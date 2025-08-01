# Copyright (c) 2025 Nablarise. All rights reserved.
# Author: Guillaume Marques <guillaume@nablarise.com>
# SPDX-License-Identifier: Proprietary

"""
CouplingConstraintMapping

Stores the mapping between master constraints and subproblem variables with their coefficients.
Uses type-stable storage with constraint types separated for performance.

Structure:
- First level: Type{<:MOI.ConstraintIndex} (constraint type)
- Second level: Int64 (constraint index value) 
- Third level: MOI.VariableIndex => Float64 (variable to coefficient mapping)
"""
struct CouplingConstraintMapping
    data::Dict{Type{<:MOI.ConstraintIndex}, Dict{Int64, Dict{MOI.VariableIndex, Float64}}}
end

function CouplingConstraintMapping()
    return CouplingConstraintMapping(Dict{Type{<:MOI.ConstraintIndex}, Dict{Int64, Dict{MOI.VariableIndex, Float64}}}())
end

"""
    get_coefficient(mapping::CouplingConstraintMapping, constraint_ref, variable_ref)

Get the coefficient of a variable in a constraint.
"""
function get_coefficient(mapping::CouplingConstraintMapping, constraint_ref, variable_ref)
    constraint_index = JuMP.index(constraint_ref)
    variable_index = JuMP.index(variable_ref)
    constraint_type = typeof(constraint_index)
    constraint_value = constraint_index.value
    
    if haskey(mapping.data, constraint_type) && 
       haskey(mapping.data[constraint_type], constraint_value) &&
       haskey(mapping.data[constraint_type][constraint_value], variable_index)
        return mapping.data[constraint_type][constraint_value][variable_index]
    end
    return 0.0
end

"""
    set_coefficient!(mapping::CouplingConstraintMapping, constraint_ref, variable_ref, coeff::Float64)

Set the coefficient of a variable in a constraint.
"""
function set_coefficient!(mapping::CouplingConstraintMapping, constraint_ref, variable_ref, coeff::Float64)
    constraint_index = JuMP.index(constraint_ref)
    variable_index = JuMP.index(variable_ref)
    constraint_type = typeof(constraint_index)
    constraint_value = constraint_index.value
    
    # Initialize nested structure if needed
    if !haskey(mapping.data, constraint_type)
        mapping.data[constraint_type] = Dict{Int64, Dict{MOI.VariableIndex, Float64}}()
    end
    if !haskey(mapping.data[constraint_type], constraint_value)
        mapping.data[constraint_type][constraint_value] = Dict{MOI.VariableIndex, Float64}()
    end
    
    mapping.data[constraint_type][constraint_value][variable_index] = coeff
end

"""
    initialize_constraint!(mapping::CouplingConstraintMapping, constraint_ref)

Initialize storage for a constraint.
"""
function initialize_constraint!(mapping::CouplingConstraintMapping, constraint_ref)
    constraint_index = JuMP.index(constraint_ref)
    constraint_type = typeof(constraint_index)
    constraint_value = constraint_index.value
    
    if !haskey(mapping.data, constraint_type)
        mapping.data[constraint_type] = Dict{Int64, Dict{MOI.VariableIndex, Float64}}()
    end
    if !haskey(mapping.data[constraint_type], constraint_value)
        mapping.data[constraint_type][constraint_value] = Dict{MOI.VariableIndex, Float64}()
    end
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
    get_cost(mapping::OriginalCostMapping, variable_ref)

Get the original cost of a variable.
"""
function get_cost(mapping::OriginalCostMapping, variable_ref)
    variable_index = JuMP.index(variable_ref)
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
    total_constraints = 0
    for constraint_type_dict in values(mapping.data)
        total_constraints += length(constraint_type_dict)
    end
    return total_constraints
end

Base.keys(mapping::CouplingConstraintMapping) = keys(mapping.data)
Base.values(mapping::CouplingConstraintMapping) = values(mapping.data)

Base.iterate(mapping::OriginalCostMapping) = iterate(mapping.data)
Base.iterate(mapping::OriginalCostMapping, state) = iterate(mapping.data, state)
Base.length(mapping::OriginalCostMapping) = length(mapping.data)
Base.keys(mapping::OriginalCostMapping) = keys(mapping.data)
Base.values(mapping::OriginalCostMapping) = values(mapping.data)

# Show methods for debugging
function Base.show(io::IO, mapping::CouplingConstraintMapping)
    print(io, "CouplingConstraintMapping with $(length(mapping.data)) constraint types")
end

function Base.show(io::IO, mapping::OriginalCostMapping)
    print(io, "OriginalCostMapping with $(length(mapping.data)) variables")
end