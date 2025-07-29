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
    subproblems::Dict{Any,Model}
end

master(reformulation::Reformulation) = reformulation.master_problem
subproblems(reformulation::Reformulation) = reformulation.subproblems

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

function _replace_vars_in_func(func::JuMP.AffExpr, original_to_subproblem_vars_mapping)
    terms = [original_to_subproblem_vars_mapping[var] => coeff for (var, coeff) in func.terms]
    return AffExpr(func.constant, terms...)
end

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

function _register_constraints!(reform_model, original_to_reform_constr_mapping, original_model, constr_by_names, original_to_reform_vars_mapping)
    for (constr_name, constr_by_indexes) in constr_by_names
        constrs = JuMP.Containers.container(
            (index...) -> begin
                original_constr = object_dictionary(original_model)[constr_name][index...]
                original_constr_obj = JuMP.constraint_object(original_constr)
                mapped_func = _replace_vars_in_func(
                    original_constr_obj.func,
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

function dantzig_wolfe_decomposition(model::Model, dw_annotation)
    # Parse variables and their annotations
    # TODO: master variables missing.
    sp_vars_partitionning = _partition_subproblem_variables(model, dw_annotation)

    master_constrs = _master_constraints(model, dw_annotation)
    sp_constrs_paritionning = _partition_subproblem_constraints(model, dw_annotation)


    # # Create master problem
    # 

    master_model = Model()
    JuMP.set_objective_sense(master_model, JuMP.objective_sense(model))

    # # Add convexity constraints (initially empty)
    # convexity_constraints = Dict()
    # for sp_id in subproblem_ids
    #     convexity_constraints[sp_id] = @constraint(master_model, 0 == 1)
    # end

    # # Add coupling constraints to master (initially empty, will be populated during column generation)
    # coupling_constraints = Dict()
    # for ((constr_name, idx), annotation) in constraint_to_destination
    #     if annotation isa MasterAnnotation
    #         # Get original constraint structure
    #         original_constr_ref = object_dictionary(model)[constr_name][idx...]
    #         original_constr = constraint_object(original_constr_ref)

    #         # Create empty constraint with same set but no variables initially
    #         empty_expr = AffExpr(0.0)
    #         coupling_constraints[(constr_name, idx)] = @constraint(master_model, empty_expr in original_constr.set)
    #     end
    # end

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

    original_to_reform_vars_mapping = Dict()
    for (sp_id, var_infos_by_names) in subproblem_var_infos
        sp_model = subproblem_models[sp_id]
        _register_variables!(sp_model, original_to_reform_vars_mapping, model, var_infos_by_names)
    end

    @show sp_constrs_paritionning
    @show original_to_reform_vars_mapping

    original_to_reform_constrs_mapping = Dict()
    # Create subproblem constraints
    for (sp_id, constr_by_names) in sp_constrs_paritionning
        sp_model = subproblem_models[sp_id]
        _register_constraints!(sp_model, original_to_reform_constrs_mapping, model, constr_by_names, original_to_reform_vars_mapping)
    end

    @show original_to_reform_constrs_mapping

    #     julia> obj = constraint_object(cstr[1])
    # ScalarConstraint{AffExpr, MathOptInterface.LessThan{Float64}}(x[1] + x[2] + x[3] + x[4] + x[5] + x[6] + x[7] + x[8] + x[9] + x[10], MathOptInterface.LessThan{Float64}(1.0))

    # julia> obj.
    # func
    # set
    # julia> obj.func
    # x[1] + x[2] + x[3] + x[4] + x[5] + x[6] + x[7] + x[8] + x[9] + x[10]

    # julia> obj.set
    # MathOptInterface.LessThan{Float64}(1.0)






    # for sp_id in keys(subproblem_var_infos)
    #     sp_model = Model()
    #     subproblem_models[sp_id] = sp_model
    #     coefficient_mappings[sp_id] = Dict()

    #     # Add variables to subproblem with proper names
    #     sp_variables = Dict()
    #     sp_var_infos = Dict()

    #     for ((var_name, idx), assigned_sp_id) in var_to_subproblem
    #         if assigned_sp_id == sp_id
    #             original_var = object_dictionary(model)[var_name][idx...]


    #             JuMP.VariableInfo(
    #                 JuMP.has_lower_bound(original_var),
    #                 JuMP.lower_bound(original_var),
    #                 JuMP.has_upper_bound(original_var),
    #                 JuMP.upper_bound(original_var),
    #                 JuMP.is_fixed(original_var),
    #                 JuMP.fix_value(original_var),
    #                 JuMP.has_start_value(original_var),
    #                 JuMP.start_value(original_var),
    #                 JuMP.is_binary(original_var),
    #                 JuMP.is_integer(original_var),
    #             )

    #             # Create variable with same properties and name
    #             if is_binary(original_var)
    #                 sp_var = @variable(sp_model, binary = true, base_name = string(var_name, idx))
    #             elseif is_integer(original_var)
    #                 sp_var = @variable(sp_model, integer = true, base_name = string(var_name, idx))
    #             else
    #                 sp_var = @variable(sp_model, base_name = string(var_name, idx))
    #             end

    #             # Set bounds if they exist
    #             if has_lower_bound(original_var)
    #                 set_lower_bound(sp_var, lower_bound(original_var))
    #             end
    #             if has_upper_bound(original_var)
    #                 set_upper_bound(sp_var, upper_bound(original_var))
    #             end

    #             sp_variables[(var_name, idx)] = sp_var
    #         end
    #     end

    #     #Containers.container((i,j) -> i+j, I)

    #     # Add subproblem constraints
    #     for ((constr_name, idx), annotation) in constraint_to_destination
    #         if annotation isa SubproblemAnnotation && annotation.id == sp_id
    #             # Get original constraint and recreate it with subproblem variables
    #             original_constr_ref = object_dictionary(model)[constr_name][idx...]
    #             original_constr = constraint_object(original_constr_ref)

    #             # Build constraint expression with subproblem variables
    #             constraint_expr = AffExpr(0.0)
    #             for (var_ref, coeff) in linear_terms(original_constr.func)
    #                 # Find the variable in our subproblem
    #                 var_found = false
    #                 for ((var_name, var_idx), sp_var) in sp_variables
    #                     if object_dictionary(model)[var_name][var_idx...] == var_ref
    #                         add_to_expression!(constraint_expr, coeff, sp_var)
    #                         var_found = true
    #                         break
    #                     end
    #                 end
    #                 if !var_found
    #                     # Variable not in this subproblem - skip it (it belongs to another subproblem)
    #                     # This can happen for coupling constraints that involve multiple subproblems
    #                     continue
    #                 end
    #             end

    #             # Add constant if exists
    #             if isa(original_constr.func, AffExpr)
    #                 constraint_expr.constant += original_constr.func.constant
    #             end

    #             # Create the constraint with the same set
    #             @constraint(sp_model, constraint_expr in original_constr.set)
    #         end
    #     end

    #     # Add objective function (subproblem gets portion of original objective)
    #     original_obj = objective_function(model)
    #     if isa(original_obj, AffExpr) || isa(original_obj, QuadExpr)
    #         subproblem_obj = AffExpr(0.0)
    #         for (var_ref, coeff) in linear_terms(original_obj)
    #             # Check if this variable belongs to this subproblem
    #             for ((var_name, var_idx), sp_var) in sp_variables
    #                 if object_dictionary(model)[var_name][var_idx...] == var_ref
    #                     add_to_expression!(subproblem_obj, coeff, sp_var)
    #                     break
    #                 end
    #             end
    #         end

    #         # Add constant if this is the first subproblem (to avoid double counting)
    #         if sp_id == first(sort(collect(subproblem_ids))) && isa(original_obj, AffExpr)
    #             subproblem_obj.constant += original_obj.constant
    #         end

    #         @objective(sp_model, objective_sense(model), subproblem_obj)
    #     end

    #     # Store coefficient mapping for convexity constraint
    #     coefficient_mappings[sp_id][:convexity] = 1.0
    # end

    # Convert to vector format
    #subproblems_vector = [subproblem_models[sp_id] for sp_id in sort(collect(subproblem_ids))]

    return Reformulation(master_model, subproblem_models)
end

export dantzig_wolfe_decomposition, dantzig_wolfe_subproblem, dantzig_wolfe_master

end # module ReformulationKit
