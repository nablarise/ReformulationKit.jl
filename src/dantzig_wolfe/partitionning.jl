# Partition variables annotated for master problem by variable name and index
function _master_variables(model, dw_annotation)
    master_vars = Dict{Symbol,Set{Tuple}}()

    for (var_name, var_obj) in object_dictionary(model)
        # Only process variables, not constraints
        if var_obj isa AbstractArray && length(var_obj) > 0 && first(var_obj) isa AbstractVariableRef
            for idx in _eachindex(var_obj)
                annotation = dw_annotation(Val(var_name), Tuple(idx)...)
                if annotation isa MasterAnnotation
                    if !haskey(master_vars, var_name)
                        master_vars[var_name] = Set{Tuple}()
                    end
                    push!(master_vars[var_name], Tuple(idx))
                end
            end
        elseif var_obj isa AbstractVariableRef
            annotation = dw_annotation(Val(var_name))
            if annotation isa MasterAnnotation
                if !haskey(master_vars, var_name)
                    master_vars[var_name] = Set{Tuple}([()])
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
                    sp_vars_partitionning[annotation.id][var_name] = Set{Tuple}([()])
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
                    master_constrs[constr_name] = Set{Tuple}([()])
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
                    sp_constrs_partitionning[annotation.id][constr_name] = Set{Tuple}([()])
                end
            end
        end
    end
    return sp_constrs_partitionning
end