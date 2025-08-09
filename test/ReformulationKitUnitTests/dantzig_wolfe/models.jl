# Unit tests for model creation methods in dantzig_wolfe/models.jl

using JuMP, ReformulationKit, Test
using ReformulationKit: VariableMapping, ConstraintMapping

const RK = ReformulationKit

# Tests for _register_variables!()
function test_register_variables_creates_vars_ok()
    original_model, machines, jobs = create_mixed_gap()
    reform_model = Model()
    mapping = VariableMapping()
    
    # Test with x variables for machine 1
    var_infos = Dict(
        :x => Dict(
            (1, j) => RK._original_var_info(original_model, :x, (1, j)) for j in jobs
        )
    )
    
    RK._register_variables!(reform_model, mapping, original_model, var_infos)
    
    @test haskey(reform_model.obj_dict, :x)
    @test reform_model[:x] isa JuMP.Containers.SparseAxisArray
    @test length(reform_model[:x]) == length(jobs)
end

function test_register_variables_preserves_properties_ok()
    original_model = Model()
    @variable(original_model, x[1:2], Bin)
    reform_model = Model()
    mapping = VariableMapping()
    
    var_infos = Dict(
        :x => Dict(
            (i,) => RK._original_var_info(original_model, :x, (i,)) for i in 1:2
        )
    )
    
    RK._register_variables!(reform_model, mapping, original_model, var_infos)
    
    for i in 1:2
        reform_var = reform_model[:x][i]
        @test JuMP.is_binary(reform_var)
    end
end

function test_register_variables_updates_mapping_ok()
    original_model = Model()
    @variable(original_model, x)
    reform_model = Model()
    mapping = VariableMapping()
    
    var_infos = Dict(
        :x => Dict(
            () => RK._original_var_info(original_model, :x, ())
        )
    )
    
    RK._register_variables!(reform_model, mapping, original_model, var_infos)
    
    @test length(mapping) == 1
    @test original_model[:x] in keys(mapping)
    @test mapping[original_model[:x]] == reform_model[:x][()] # TODO: ugly!
end

# Tests for _register_constraints!()
function test_register_constraints_creates_constraints_ok()
    original_model, machines, jobs = create_mixed_gap()
    reform_model = Model()
    constr_mapping = ConstraintMapping()
    var_mapping = VariableMapping()
    
    # Create variables in reform model first
    @variable(reform_model, x[machines, jobs], Bin)
    @variable(reform_model, z[jobs], Int)
    
    # Create variable mapping
    for m in machines, j in jobs
        var_mapping[original_model[:x][m, j]] = reform_model[:x][m, j]
    end
    for j in jobs
        var_mapping[original_model[:z][j]] = reform_model[:z][j]
    end
    
    # Test constraint registration
    master_constrs = Dict(:assignment => Set([(j,) for j in jobs]))
    
    RK._register_constraints!(reform_model, constr_mapping, original_model, master_constrs, var_mapping)
    
    @test haskey(reform_model.obj_dict, :assignment)
    @test length(reform_model[:assignment]) == length(jobs)
end

function test_register_constraints_maps_variables_ok()
    original_model = Model()
    @variable(original_model, x[1:2])
    @constraint(original_model, test_constraint, sum(x) >= 1)
    
    reform_model = Model()
    @variable(reform_model, y[1:2])
    
    constr_mapping = ConstraintMapping()
    var_mapping = VariableMapping()
    for i in 1:2
        var_mapping[original_model[:x][i]] = reform_model[:y][i]
    end
    constrs = Dict(:test_constraint => Set([()]))
    
    RK._register_constraints!(reform_model, constr_mapping, original_model, constrs, var_mapping)
    
    @test haskey(reform_model.obj_dict, :test_constraint)
    reform_constraint = reform_model[:test_constraint][()]
    constraint_obj = JuMP.constraint_object(reform_constraint)
    
    # Check that the constraint uses reform variables
    @test reform_model[:y][1] in keys(constraint_obj.func.terms)
    @test reform_model[:y][2] in keys(constraint_obj.func.terms)
end

function test_register_constraints_preserves_sets_ok()
    original_model = Model()
    @variable(original_model, x)
    @constraint(original_model, eq_constraint, x == 5)
    @constraint(original_model, leq_constraint, x <= 10)
    @constraint(original_model, geq_constraint, x >= 2)
    
    reform_model = Model()
    @variable(reform_model, y)
    
    constr_mapping = ConstraintMapping()
    var_mapping = VariableMapping()
    var_mapping[original_model[:x]] = reform_model[:y]
    constrs = Dict(
        :eq_constraint => Set([()]),
        :leq_constraint => Set([()]),
        :geq_constraint => Set([()])
    )
    
    RK._register_constraints!(reform_model, constr_mapping, original_model, constrs, var_mapping)
    
    # Check constraint sets are preserved
    eq_obj = JuMP.constraint_object(reform_model[:eq_constraint][()]) # TODO: ugly
    leq_obj = JuMP.constraint_object(reform_model[:leq_constraint][()]) # TODO: ugly
    geq_obj = JuMP.constraint_object(reform_model[:geq_constraint][()]) # TODO: ugly
    
    @test eq_obj.set isa MOI.EqualTo{Float64}
    @test leq_obj.set isa MOI.LessThan{Float64}
    @test geq_obj.set isa MOI.GreaterThan{Float64}
end

# Tests for _register_objective!()
function test_register_objective_filters_variables_ok()
    original_model, machines, jobs = create_mixed_gap()
    master_model = Model()
    subproblem1_model = Model()
    subproblem2_model = Model()
    
    # Create variables in all models
    @variable(master_model, z[jobs], Int)
    @variable(subproblem1_model, x[1:1, jobs], Bin)
    @variable(subproblem1_model, y[1:1, jobs] >= 0)
    @variable(subproblem2_model, x[2:2, jobs], Bin)
    @variable(subproblem2_model, y[2:2, jobs] >= 0)
    
    # Create complete variable mapping for all variables
    var_mapping = VariableMapping()
    for j in jobs
        var_mapping[original_model[:z][j]] = master_model[:z][j]
        var_mapping[original_model[:x][1, j]] = subproblem1_model[:x][1, j]
        var_mapping[original_model[:y][1, j]] = subproblem1_model[:y][1, j]
        var_mapping[original_model[:x][2, j]] = subproblem2_model[:x][2, j]
        var_mapping[original_model[:y][2, j]] = subproblem2_model[:y][2, j]
    end
    
    # Test master objective gets only master variables
    RK._register_objective!(master_model, original_model, var_mapping; is_master=true)
    
    master_obj = JuMP.objective_function(master_model)
    @test master_obj isa JuMP.AffExpr
    
    # Check only master variables are in objective
    master_vars_in_obj = [var for var in keys(master_obj.terms) if JuMP.owner_model(var) == master_model]
    @test length(master_vars_in_obj) == length(jobs)  # Only z variables
end

function test_register_objective_preserves_sense_ok()
    original_model = Model()
    @variable(original_model, x)
    @objective(original_model, Max, x)
    
    reform_model = Model()
    @variable(reform_model, y)
    var_mapping = VariableMapping()
    var_mapping[original_model[:x]] = reform_model[:y]
    
    RK._register_objective!(reform_model, original_model, var_mapping; is_master=true)
    
    @test JuMP.objective_sense(reform_model) == MOI.MAX_SENSE
end

function test_register_objective_preserves_coefficients_ok()
    original_model = Model()
    @variable(original_model, x[1:2])
    @objective(original_model, Min, 3*x[1] + 5*x[2])
    
    reform_model = Model()
    @variable(reform_model, y[1:2])
    var_mapping = VariableMapping()
    for i in 1:2
        var_mapping[original_model[:x][i]] = reform_model[:y][i]
    end
    
    RK._register_objective!(reform_model, original_model, var_mapping; is_master=true)
    
    reform_obj = JuMP.objective_function(reform_model)
    @test reform_obj.terms[reform_model[:y][1]] == 3.0
    @test reform_obj.terms[reform_model[:y][2]] == 5.0
end

function test_register_objective_subproblem_zero_constant_ok()
    original_model = Model()
    @variable(original_model, x[1:2])
    @objective(original_model, Min, 3*x[1] + 5*x[2] + 10)  # Objective with constant
    
    reform_model = Model()
    @variable(reform_model, y[1:2])
    var_mapping = VariableMapping()
    for i in 1:2
        var_mapping[original_model[:x][i]] = reform_model[:y][i]
    end
    
    # Test subproblem objective (is_master=false) removes constants
    RK._register_objective!(reform_model, original_model, var_mapping; is_master=false)
    
    reform_obj = JuMP.objective_function(reform_model)
    @test reform_obj.constant == 0.0  # Subproblem should have zero constant
    @test reform_obj.terms[reform_model[:y][1]] == 3.0
    @test reform_obj.terms[reform_model[:y][2]] == 5.0
end

function test_register_objective_master_preserves_constant_ok()
    original_model = Model()
    @variable(original_model, x[1:2])
    @objective(original_model, Min, 3*x[1] + 5*x[2] + 10)  # Objective with constant
    
    reform_model = Model()
    @variable(reform_model, y[1:2])
    var_mapping = VariableMapping()
    for i in 1:2
        var_mapping[original_model[:x][i]] = reform_model[:y][i]
    end
    
    # Test master objective (is_master=true) preserves constants
    RK._register_objective!(reform_model, original_model, var_mapping; is_master=true)
    
    reform_obj = JuMP.objective_function(reform_model)
    @test reform_obj.constant == 10.0  # Master should preserve constant
    @test reform_obj.terms[reform_model[:y][1]] == 3.0
    @test reform_obj.terms[reform_model[:y][2]] == 5.0
end

function test_unit_models()
    @testset "[models] variable registration" begin
        test_register_variables_creates_vars_ok()
        test_register_variables_preserves_properties_ok()
        test_register_variables_updates_mapping_ok()
    end

    @testset "[models] constraint registration" begin
        test_register_constraints_creates_constraints_ok()
        test_register_constraints_maps_variables_ok()
        test_register_constraints_preserves_sets_ok()
    end

    @testset "[models] objective registration" begin
        test_register_objective_filters_variables_ok()
        test_register_objective_preserves_sense_ok()
        test_register_objective_preserves_coefficients_ok()
        test_register_objective_subproblem_zero_constant_ok()
        test_register_objective_master_preserves_constant_ok()
    end
end