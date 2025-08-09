function get_scalar_object(model, object_name, index)
    return object_dictionary(model)[object_name][index...]
end

function get_scalar_object(model,  object_name, ::Tuple{})
    return object_dictionary(model)[object_name]
end

# Extract VariableInfo from original model variable for reformulation
function _original_var_info(original_model, var_name, index)
    original_var = get_scalar_object(original_model, var_name, index)
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


function _replace_vars_in_func(func::JuMP.AffExpr, target_model, original_to_subproblem_vars_mapping::VariableMapping)
    terms = [
        original_to_subproblem_vars_mapping[var] => coeff 
        for (var, coeff) in func.terms
        if JuMP.owner_model(original_to_subproblem_vars_mapping[var]) == target_model
    ]
    return AffExpr(func.constant, terms...)
end

function _replace_vars_in_func(single_var::JuMP.VariableRef, target_model, original_to_subproblem_vars_mapping::VariableMapping)
    if JuMP.owner_model(original_to_subproblem_vars_mapping[single_var]) == target_model
        return original_to_subproblem_vars_mapping[single_var]
    end
    return 0.0
end

# Create and register variables in reform model, updating variable mapping
function _register_variables!(reform_model, original_to_reform_mapping::VariableMapping, original_model, var_infos_by_names)
    for (var_name, var_infos_by_indexes) in var_infos_by_names
        vars = Containers.container(
            (index...) -> begin
                var = JuMP.build_variable(() -> error("todo."), var_infos_by_indexes[index])
                jump_var_name = if JuMP.set_string_names_on_creation(reform_model)
                    JuMP.string(var_name, "[", JuMP.string(index), "]")
                else
                    ""
                end
                original_var = get_scalar_object(original_model, var_name, index)
                original_to_reform_mapping[original_var] = JuMP.add_variable(reform_model, var, jump_var_name)
            end,
            sort(collect(keys(var_infos_by_indexes)))
        )
        reform_model[var_name] = vars
    end
end

# Create and register constraints in reform model using mapped variables
function _register_constraints!(reform_model, original_to_reform_constr_mapping::ConstraintMapping, original_model, constr_by_names, original_to_reform_vars_mapping::VariableMapping)
    for (constr_name, constr_by_indexes) in constr_by_names
        constrs = JuMP.Containers.container(
            (index...) -> begin
                original_constr = get_scalar_object(original_model, constr_name, index)
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
            sort(collect(constr_by_indexes))
        )
        reform_model[constr_name] = constrs
    end
end

function _populate_subproblem_mapping(master_model, original_constr_expr::AffExpr, reform_constr, original_to_reform_vars_mapping::VariableMapping)
    for (original_var, value) in original_constr_expr.terms
        reform_var = original_to_reform_vars_mapping[original_var]
        if JuMP.owner_model(reform_var) != master_model
            set_coefficient!(JuMP.owner_model(reform_var).ext[:dw_coupling_constr_mapping], reform_constr, reform_var, value)
        end
    end
end

function _subproblem_solution_to_master_constr_mapping!(subproblem_models, master_model, original_to_reform_vars_mapping::VariableMapping, original_to_reform_constrs_mapping::ConstraintMapping)
    for (sp_id, subproblem_model) in subproblem_models
        subproblem_model.ext[:dw_coupling_constr_mapping] = CouplingConstraintMapping()
    end

    for (original_constr, reform_constr) in original_to_reform_constrs_mapping
        if JuMP.owner_model(reform_constr) == master_model
            original_constr_object = JuMP.constraint_object(original_constr)
            _populate_subproblem_mapping(master_model, original_constr_object.func, reform_constr, original_to_reform_vars_mapping)
        end
    end
end

function _populate_cost_mapping(master_model, original_obj_expr::JuMP.AffExpr, original_to_reform_vars_mapping::VariableMapping)
    for (original_var, cost) in original_obj_expr.terms
        reform_var = original_to_reform_vars_mapping[original_var]
        if JuMP.owner_model(reform_var) != master_model
            set_cost!(JuMP.owner_model(reform_var).ext[:dw_sp_var_original_cost], reform_var, cost)
        end
    end
end

function _populate_cost_mapping(master_model, single_var::JuMP.VariableRef, original_to_reform_vars_mapping::VariableMapping)
    reform_var = original_to_reform_vars_mapping[single_var]
    if JuMP.owner_model(reform_var) != master_model
        set_cost!(JuMP.owner_model(reform_var).ext[:dw_sp_var_original_cost], reform_var, 1.0)
    end
end

function _subproblem_solution_to_original_cost_mapping!(subproblem_models, master_model, original_model, original_to_reform_vars_mapping::VariableMapping)
    for (sp_id, subproblem_model) in subproblem_models
        subproblem_model.ext[:dw_sp_var_original_cost] = OriginalCostMapping()
    end
    _populate_cost_mapping(master_model, JuMP.objective_function(original_model), original_to_reform_vars_mapping)
end

function _register_objective!(reform_model, model, original_to_reform_vars_mapping::VariableMapping)
    # Get original objective function and sense
    original_obj_func = JuMP.objective_function(model)
    original_obj_sense = JuMP.objective_sense(model)
    
    # Create new AffExpr with filtered terms and original constant
    reform_obj_func = _replace_vars_in_func(original_obj_func, reform_model, original_to_reform_vars_mapping)
        
    # Set objective on reform_model
    JuMP.set_objective_sense(reform_model, original_obj_sense)
    JuMP.set_objective_function(reform_model, reform_obj_func)
end