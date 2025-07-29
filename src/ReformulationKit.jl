module ReformulationKit

using JuMP, MathOptInterface

include("indexes.jl")

struct SubproblemAnnotation
    id::Any
end

struct MasterAnnotation
end

dantzig_wolfe_subproblem(id) = SubproblemAnnotation(id)
dantzig_wolfe_master() = MasterAnnotation()

struct Reformulation
    master_problem::Model
    subproblems::Dict{Any,Model} # subproblem_id => JuMP model
    convexity_constraints_lb::Dict{Any,Any} # subproblem_id => JuMP constraint
    convexity_constraints_ub::Dict{Any,Any}
end

master(reformulation::Reformulation) = reformulation.master_problem
subproblems(reformulation::Reformulation) = reformulation.subproblems

# Extract VariableInfo from original model variable for reformulation
function _original_var_info(original_model, var_name, index)
    original_var = object_dictionary(original_model)[var_name][index...]
    has_upper_bound = JuMP.has_upper_bound(original_var)
    has_lower_bound = JuMP.has_lower_bound(original_var)
    is_fixed = JuMP.is_fixed(original_var)
    return JuMP.VariableInfo(
        has_lower_bound,
        has_lower_bound ? JuMP.lower_bound(original_var) : -Inf,
        has_upper_bound,
        has_upper_bound ? JuMP.upper_bound(original_var) : Inf,
        JuMP.is_fixed(original_var),
        is_fixed ? JuMP.fix_value(original_var) : nothing,
        JuMP.has_start_value(original_var),
        JuMP.start_value(original_var),
        JuMP.is_binary(original_var),
        JuMP.is_integer(original_var),
    )
end

# Partition variables annotated for master problem by variable name and index
function _master_variables(model, dw_annotation)
    master_vars = Dict{Symbol,Set{Tuple}}()

    for (var_name, var_obj) in object_dictionary(model)
        # Only process variables, not constraints
        if var_obj isa AbstractArray && length(var_obj) > 0 && first(var_obj) isa AbstractVariableRef
            for idx in _eachindex(var_obj)
                annotation = dw_annotation(Val(var_name), Tuple(idx)...)
                if annotation isa MasterAnnotation
                    if !haskey(master_vars[annotation.id], var_name)
                        master_vars[annotation.id][var_name] = Set{Tuple}()
                    end
                    push!(master_vars[annotation.id][var_name], Tuple(idx))
                end
            end
        elseif var_obj isa AbstractVariableRef
            annotation = dw_annotation(Val(var_name))
            if annotation isa MasterAnnotation
                if !haskey(master_vars[annotation.id], var_name)
                    master_vars[annotation.id][var_name] = Set{Tuple{}}(())
                end
            end
        end
    end
    return master_vars
end

# Partition variables by subproblem ID based on annotations
function _partition_subproblem_variables(model, dw_annotation)
    sp_vars_partitionning = Dict{Any,Dict{Symbol,Set{Tuple}}}()
    for (var_name, var_obj) in object_dictionary(model)
        # Only process variables, not constraints
        if var_obj isa AbstractArray && length(var_obj) > 0 && first(var_obj) isa AbstractVariableRef
            for idx in _eachindex(var_obj)
                annotation = dw_annotation(Val(var_name), Tuple(idx)...)
                if annotation isa SubproblemAnnotation
                    if !haskey(sp_vars_partitionning, annotation.id)
                        sp_vars_partitionning[annotation.id] = Dict{Symbol,Set{Tuple}}()
                    end
                    if !haskey(sp_vars_partitionning[annotation.id], var_name)
                        sp_vars_partitionning[annotation.id][var_name] = Set{Tuple}()
                    end
                    push!(sp_vars_partitionning[annotation.id][var_name], Tuple(idx))
                end
            end
        elseif var_obj isa AbstractVariableRef
            annotation = dw_annotation(Val(var_name))
            if annotation isa SubproblemAnnotation
                if !haskey(sp_vars_partitionning, annotation.id)
                    sp_vars_partitionning[annotation.id] = Dict{Symbol,Set{Tuple}}()
                end
                if !haskey(sp_vars_partitionning[annotation.id], var_name)
                    sp_vars_partitionning[annotation.id][var_name] = Set{Tuple{}}(())
                end
            end
        end
    end
    return sp_vars_partitionning
end

# Partition constraints annotated for master problem by constraint name and index
function _master_constraints(model, dw_annotation)
    master_constrs = Dict{Symbol,Set{Tuple}}()

    for (constr_name, constr_obj) in object_dictionary(model)
        # Only process constraints, not variables
        if constr_obj isa AbstractArray && length(constr_obj) > 0 && first(constr_obj) isa ConstraintRef
            for idx in _eachindex(constr_obj)
                annotation = dw_annotation(Val(constr_name), Tuple(idx)...)
                if annotation isa MasterAnnotation
                    if !haskey(master_constrs, constr_name)
                        master_constrs[constr_name] = Set{Tuple}()
                    end
                    push!(master_constrs[constr_name], Tuple(idx))
                end
            end
        elseif constr_obj isa ConstraintRef
            annotation = dw_annotation(Val(constr_name))
            if annotation isa MasterAnnotation
                if !haskey(master_constrs, constr_name)
                    master_constrs[constr_name] = Set{Tuple}(())
                end
            end
        end
    end
    return master_constrs
end

# Partition constraints by subproblem ID based on annotations
function _partition_subproblem_constraints(model, dw_annotation)
    sp_constrs_partitionning = Dict{Any,Dict{Symbol,Set{Tuple}}}()
    for (constr_name, constr_obj) in object_dictionary(model)
        # Only process constraints, not variables
        if constr_obj isa AbstractArray && length(constr_obj) > 0 && first(constr_obj) isa ConstraintRef
            for idx in _eachindex(constr_obj)
                annotation = dw_annotation(Val(constr_name), Tuple(idx)...)
                if annotation isa SubproblemAnnotation
                    if !haskey(sp_constrs_partitionning, annotation.id)
                        sp_constrs_partitionning[annotation.id] = Dict{Symbol,Set{Tuple}}()
                    end
                    if !haskey(sp_constrs_partitionning[annotation.id], constr_name)
                        sp_constrs_partitionning[annotation.id][constr_name] = Set{Tuple}()
                    end
                    push!(sp_constrs_partitionning[annotation.id][constr_name], Tuple(idx))
                end
            end
        elseif constr_obj isa ConstraintRef
            annotation = dw_annotation(Val(constr_name))
            if annotation isa SubproblemAnnotation
                if !haskey(sp_constrs_partitionning, annotation.id)
                    sp_constrs_partitionning[annotation.id] = Dict{Symbol,Set{Tuple}}()
                end
                if !haskey(sp_constrs_partitionning[annotation.id], constr_name)
                    sp_constrs_partitionning[annotation.id][constr_name] = Set{Tuple}()
                end
            end
        end
    end
    return sp_constrs_partitionning
end

function _replace_vars_in_func(func::JuMP.AffExpr, target_model, original_to_subproblem_vars_mapping)
    terms = [
        original_to_subproblem_vars_mapping[var] => coeff 
        for (var, coeff) in func.terms
        if JuMP.owner_model(original_to_subproblem_vars_mapping[var]) == target_model
    ]
    return AffExpr(func.constant, terms...)
end

# Create and register variables in reform model, updating variable mapping
function _register_variables!(reform_model, original_to_reform_mapping, original_model, var_infos_by_names)
    for (var_name, var_infos_by_indexes) in var_infos_by_names
        vars = Containers.container(
            (index...) -> begin
                var = JuMP.build_variable(() -> error("todo."), var_infos_by_indexes[index])
                jump_var_name = if JuMP.set_string_names_on_creation(reform_model)
                    JuMP.string(var_name, "[", JuMP.string(index), "]")
                else
                    ""
                end
                original_var = object_dictionary(original_model)[var_name][index...]
                original_to_reform_mapping[original_var] = JuMP.add_variable(reform_model, var, jump_var_name)
            end,
            collect(keys(var_infos_by_indexes))
        )
        reform_model[var_name] = vars
    end
end

# Create and register constraints in reform model using mapped variables
function _register_constraints!(reform_model, original_to_reform_constr_mapping, original_model, constr_by_names, original_to_reform_vars_mapping)
    for (constr_name, constr_by_indexes) in constr_by_names
        constrs = JuMP.Containers.container(
            (index...) -> begin
                original_constr = object_dictionary(original_model)[constr_name][index...]
                original_constr_obj = JuMP.constraint_object(original_constr)
                mapped_func = _replace_vars_in_func(
                    original_constr_obj.func,
                    reform_model,
                    original_to_reform_vars_mapping
                )
                constr = JuMP.build_constraint(() -> error("todo."), mapped_func, original_constr_obj.set)
                jump_constr_name = if JuMP.set_string_names_on_creation(reform_model)
                    JuMP.string(constr_name, "[", JuMP.string(index), "]")
                else
                    ""
                end
                original_to_reform_constr_mapping[original_constr] = JuMP.add_constraint(reform_model, constr, jump_constr_name)
            end,
            collect(constr_by_indexes)
        )
        reform_model[constr_name] = constrs
    end
end

function _populate_subproblem_mapping(master_model, original_constr_expr::AffExpr, reform_constr, original_to_reform_vars_mapping )
    for (original_var, value) in original_constr_expr.terms
        reform_var = original_to_reform_vars_mapping[original_var]
        if JuMP.owner_model(reform_var) != master_model
            JuMP.owner_model(reform_var).ext[:dw_mapping][reform_var][reform_constr] = value
        end
    end
end

function _subproblem_solution_to_master_constr_mapping!(subproblem_models, master_model, original_to_reform_vars_mapping, original_to_reform_constrs_mapping)
    println("-------")
    println("--------")
    @show master
    @show original_to_reform_vars_mapping
    @show original_to_reform_constrs_mapping

    for (sp_id, subproblem_model) in subproblem_models
        subproblem_model.ext[:dw_mapping] = Dict{Any, Dict{Any,Float64}}() # var_id => Dict(constr_id => coeff))
    end

    for reform_var in values(original_to_reform_vars_mapping)
        if JuMP.owner_model(reform_var) != master_model
            JuMP.owner_model(reform_var).ext[:dw_mapping][reform_var] = Dict()
        end
    end

    for (original_constr, reform_constr) in original_to_reform_constrs_mapping
        if JuMP.owner_model(reform_constr) == master_model
            original_constr_object = JuMP.constraint_object(original_constr)
            _populate_subproblem_mapping(master_model, original_constr_object.func, reform_constr, original_to_reform_vars_mapping)
        end
    end
end

# Perform Dantzig-Wolfe decomposition of a JuMP model based on variable/constraint annotations
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

    original_to_reform_vars_mapping = Dict()
    original_to_reform_constrs_mapping = Dict()

    master_var_infos = Dict(
        var_name => Dict(
            index => _original_var_info(model, var_name, index) for index in indexes
        ) for (var_name, indexes) in master_vars
    )
    _register_variables!(master_model, original_to_reform_vars_mapping, model, master_vars)


    # Create subproblems
    subproblem_ids = keys(sp_vars_partitionning)
    subproblem_models = Dict(sp_id... => Model() for sp_id in subproblem_ids)
    coefficient_mappings = Dict(sp_id => Dict() for sp_id in subproblem_ids)

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

    # Add convexity constraints (initially empty)
    convexity_constraints_lb = Dict()
    convexity_constraints_ub = Dict()
    for sp_id in subproblem_ids
        convexity_constraints_lb[sp_id] = @constraint(master_model, 0 >= 1)
        convexity_constraints_ub[sp_id] = @constraint(master_model, 0 <= 1)
    end

    _subproblem_solution_to_master_constr_mapping!(
        subproblem_models, master_model, original_to_reform_vars_mapping, original_to_reform_constrs_mapping
    )

    return Reformulation(master_model, subproblem_models, convexity_constraints_lb, convexity_constraints_ub)
end

export dantzig_wolfe_decomposition, dantzig_wolfe_subproblem, dantzig_wolfe_master

end # module ReformulationKit
